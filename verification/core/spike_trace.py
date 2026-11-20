"""Run the pinned Spike on a core test ELF and read its retirement trace.

Spike (riscv-software-src/riscv-isa-sim, pinned by spike_commit in
verification/tool-versions.txt, built by verification/core/spike_setup.sh) is
the independent per-instruction reference: it never sees the DUT. The
invocation is fixed here so there is exactly one documented, reproducible way
to produce a reference trace:

    spike --isa=rv32imc_zicsr -m0x80000000:0x200000 --log-commits <elf>

One hart (hart 0) in machine mode; 2 MiB of RAM at 0x80000000 (build_tests.py's
MEM_WORDS), ELF entry 0x80000080 (verification/core/link.ld). --log-commits
writes one line per retired instruction to stderr:

    core   0: 3 0x000000a2 (0x00642023) mem 0x80003000 0x80002001
    core   0: 3 0x80000092 (0x30529073) c773_mtvec 0x80002001

priv (3 = M), pc, encoded instruction (4 or 8 hex digits: a 2- or 4-byte
length), then that instruction's architectural effects: integer register
writes (a write to x0 is never logged - it is architecturally discarded), CSR
writes (c<number>_<name>; the number is decimal), loads (mem <addr>, with the
loaded value in the register write) and stores (mem <addr> <value>).

Spike's reset rom commits below 0x80000000 before jumping to the ELF entry;
those records are dropped (their register effects are still applied to the
tracked state) so the trace starts at the entry. Execution stops at the store
to the ELF's tohost, which model_test.h's RVMODEL_HALT writes with 1; Spike's
host interface notices within one 5000-commit interleave and exits, so the raw
log carries up to 4999 post-store self-loop commits that the reader cuts off.

A trapping instruction never retires, so a synchronous exception shows up as a
retirement gap: the reader emits an exception record where the trapping
instruction would have retired, with epc (the pc that did not retire, when
unambiguous) and handler (the first committed handler instruction). Every
synchronous exception enters the handler at the mtvec BASE - the vectored
mode's base+4*cause offset applies to interrupts only - so the reader accepts
a gap only when the next pc equals the mtvec base it tracked from the CSR
writes; anything else is reported as malformed. mcause and the trap mepc are
architectural and show up in the trace as the handler's own csrr register
writes.

Implementation-dependent fields (spec/decisions/0011): Spike's mtvec is fully
writable WARL, so the reference reproduces exactly the mtvec it is given. CVE2
forces MODE=vectored with a 256-byte-aligned base. The intersection - a
vectored mtvec whose base is 256-byte aligned - reads back identically on
both, and is the only shape reference traces may be compared on; a write
outside it reads back differently on the DUT, so downstream comparison code
must not feed such writes to the monitor. The deterministic program in
test_spike_trace.py writes only the representable shape.

Usage (after verification/core/setup.sh and spike_setup.sh):

    python3 -I verification/core/spike_trace.py [--json OUT] ELF...

Failures raise TraceError naming the program.
"""

import json
import os
import re
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent
BUILD = REPO / "verification" / "build"

BASE = 0x80000000
MEM_BYTES = 0x200000
ISA = "rv32imc_zicsr"

MTVEC, MEPC = 0x305, 0x341


class TraceError(Exception):
    pass


def pin(key):
    val = None
    for line in (REPO / "verification" / "tool-versions.txt").read_text().splitlines():
        if line.startswith(key + "="):
            val = line.split("=", 1)[1]
    if not val:
        raise TraceError(f"no pin for {key} in verification/tool-versions.txt")
    return val


def spike_paths():
    """(spike bin, env) with the pinned dtc on PATH: spike forks the external
    dtc at every startup to build its device tree (riscv/dts.cc)."""
    spike = BUILD / "spike" / pin("spike_commit") / "bin" / "spike"
    dtc = BUILD / "dtc" / pin("dtc_release")
    if not spike.is_file():
        raise TraceError(
            f"{spike} not found - run verification/core/spike_setup.sh first")
    env = dict(os.environ)
    env["PATH"] = f"{dtc / 'bin'}{os.pathsep}{env.get('PATH', '')}"
    env["LD_LIBRARY_PATH"] = f"{dtc / 'lib'}{os.pathsep}{env.get('LD_LIBRARY_PATH', '')}"
    return spike, env


def run_spike(elf, timeout=600):
    """Run the pinned Spike on <elf>; returns the raw commit log (stderr)."""
    spike, env = spike_paths()
    r = subprocess.run(
        [str(spike), f"--isa={ISA}", f"-m{BASE:#x}:{MEM_BYTES:#x}", "--log-commits", str(elf)],
        capture_output=True, text=True, timeout=timeout, env=env)
    if r.returncode != 0:
        tail = "\n".join(r.stderr.splitlines()[-10:])
        raise TraceError(f"{Path(elf).name}: spike exited {r.returncode}\n{tail}")
    return r.stderr


_LINE = re.compile(
    r"^core\s+(\d+):\s*(\d+)\s+(0x[0-9a-f]{8})\s+\((0x[0-9a-f]{4}|0x[0-9a-f]{8})\)\s*(.*)$")


def _sext(v, bits):
    return v - (1 << bits) if v & (1 << (bits - 1)) else v


def _imm_jal(e):
    return _sext(((e >> 31) & 1) << 20 | ((e >> 21) & 0x3ff) << 1 | ((e >> 20) & 1) << 11
                 | ((e >> 12) & 0xff) << 12, 21)


def _imm_branch(e):
    return _sext(((e >> 31) & 1) << 12 | ((e >> 25) & 0x3f) << 5 | ((e >> 8) & 0xf) << 1
                 | ((e >> 7) & 1) << 11, 13)


def _imm_jalr(e):
    return _sext(e >> 20, 12)


def _imm_cj(e):
    return _sext(((e >> 12) & 1) << 11 | ((e >> 11) & 1) << 4 | ((e >> 9) & 3) << 8
                 | ((e >> 8) & 1) << 10 | ((e >> 7) & 1) << 6 | ((e >> 6) & 1) << 7
                 | ((e >> 5) & 1) << 3 | ((e >> 3) & 3) << 1 | ((e >> 2) & 1) << 5, 12)


def _imm_cb(e):
    return _sext(((e >> 12) & 1) << 8 | ((e >> 10) & 3) << 3 | ((e >> 5) & 3) << 6
                 | ((e >> 3) & 3) << 1 | ((e >> 2) & 1) << 5, 9)


def next_pcs(enc, pc, regs, csrs):
    """The set of pcs the instruction at <pc> may retire to next, or None when
    the target cannot be modelled from the trace (mret with no tracked mepc).
    Register jumps always resolve: the tracked GPRs start at 0 and Spike logs
    every GPR write."""
    if enc & 3 == 3:
        op = enc & 0x7f
        if op == 0x6f:
            return {(pc + _imm_jal(enc)) & 0xffffffff}
        if op == 0x67:
            v = regs[(enc >> 15) & 31]
            return {(v + _imm_jalr(enc)) & 0xfffffffe}
        if op == 0x63:
            return {(pc + 4) & 0xffffffff, (pc + _imm_branch(enc)) & 0xffffffff}
        if enc == 0x30200073:  # mret
            mepc = csrs.get(MEPC)
            return None if mepc is None else {mepc}
        return {(pc + 4) & 0xffffffff}
    q, f3 = enc & 3, (enc >> 13) & 7
    if q == 1:
        if f3 in (1, 5):  # c.jal (RV32) / c.j
            return {(pc + _imm_cj(enc)) & 0xffffffff}
        if f3 in (6, 7):  # c.beqz / c.bnez
            return {(pc + 2) & 0xffffffff, (pc + _imm_cb(enc)) & 0xffffffff}
    elif q == 2 and f3 == 4 and (enc & 0x7c) == 0 and ((enc >> 7) & 31) != 0:
        # c.jr (funct4 1000) / c.jalr (funct4 1001), rs2 == 0; c.ebreak has rs1 == 0
        v = regs[(enc >> 7) & 31]
        return {v & 0xfffffffe}
    return {pc + 2}


def _effects(tokens, name, lineno):
    rd = rd_val = None
    csr, loads, stores = [], [], []

    def bad(why, t):
        return TraceError(f"{name}: line {lineno}: {why} at effect {t!r}")

    def hexval(i, t):
        """tokens[i] as a hex number, or TraceError naming the program."""
        if i >= len(tokens):
            raise bad("truncated effects", t)
        try:
            return int(tokens[i], 16)
        except ValueError:
            raise bad(f"non-hex value {tokens[i]!r}", t) from None

    i = 0
    while i < len(tokens):
        t = tokens[i]
        if t[0] == "x" and t[1:].isdigit():
            rd, rd_val = int(t[1:]), hexval(i + 1, t)
            i += 2
        elif t[0] == "c" and "_" in t:
            num, nm = t[1:].split("_", 1)
            if not num.isdigit():
                raise bad("malformed CSR token", t)
            csr.append((int(num), nm, hexval(i + 1, t)))
            i += 2
        elif t == "mem":
            addr = hexval(i + 1, t)
            if i + 2 < len(tokens) and tokens[i + 2].startswith("0x"):
                stores.append((addr, hexval(i + 2, t)))
                i += 3
            else:
                loads.append(addr)
                i += 2
        else:
            raise TraceError(f"{name}: line {lineno}: unrecognized effect {t!r}")
    return rd, rd_val, csr, loads, stores


def parse(log, name, entry, tohost):
    """Parse a raw spike commit log into the ordered reference trace.

    Starts at the ELF entry, ends at the store to tohost. Raises TraceError
    naming <name> on a malformed or incomplete log."""
    if not log.strip():
        raise TraceError(f"{name}: spike produced no commit log")
    records = []
    regs = {i: 0 for i in range(32)}  # spike resets the GPRs to 0
    csrs = {}
    started = False
    prev = None
    for lineno, line in enumerate(log.splitlines(), 1):
        if not line.strip():
            continue
        m = _LINE.match(line)
        if not m:
            raise TraceError(f"{name}: line {lineno}: malformed commit line: {line!r}")
        hart, priv, pc, enc, tail = m.groups()
        if hart != "0":
            raise TraceError(f"{name}: line {lineno}: commit from hart {hart}, expected hart 0")
        rec = {
            "pc": int(pc, 16), "enc": int(enc, 16),
            "len": (len(enc) - 2) // 2, "priv": int(priv),
        }
        rec["rd"], rec["rd_val"], rec["csr"], rec["loads"], rec["stores"] = \
            _effects(tail.split(), name, lineno)
        if rec["pc"] < BASE:  # spike's reset rom before the ELF entry
            if started:
                raise TraceError(
                    f"{name}: line {lineno}: pc {rec['pc']:#x} below {BASE:#x} after the entry")
            _apply(rec, regs, csrs)
            continue
        if not started:
            if rec["pc"] != entry:
                raise TraceError(
                    f"{name}: line {lineno}: first committed pc {rec['pc']:#x} "
                    f"is not the ELF entry {entry:#x}")
            started = True
        elif prev is not None:
            nxt = next_pcs(prev["enc"], prev["pc"], regs, csrs)
            if nxt is not None and rec["pc"] not in nxt:
                mtvec = csrs.get(MTVEC)
                base = None if mtvec is None else mtvec & ~3  # BASE field, any alignment
                if base is None or rec["pc"] != base:
                    raise TraceError(
                        f"{name}: line {lineno}: pc {rec['pc']:#x} follows {prev['pc']:#x}: "
                        "neither that instruction's control flow nor the mtvec handler")
                epcs = nxt - {rec["pc"]}
                records.append({"exception": True,
                                "epc": epcs.pop() if len(epcs) == 1 else None,
                                "handler": rec["pc"]})
            _apply(prev, regs, csrs)  # after next_pcs: a jalr target uses the old rs1
        records.append(rec)
        prev = rec
        for addr, val in rec["stores"]:
            if addr == tohost:
                if val != 1:
                    raise TraceError(
                        f"{name}: store to tohost {tohost:#x} wrote {val:#x}, expected 1")
                return records
    raise TraceError(f"{name}: no store to tohost {tohost:#x} in the commit log")


def _apply(rec, regs, csrs):
    if rec["rd"] not in (None, 0):
        regs[rec["rd"]] = rec["rd_val"]
    for num, _nm, val in rec["csr"]:
        csrs[num] = val


def trace_for(elf, tohost, entry=0x80000080, timeout=600):
    """Run spike on <elf> and return the parsed reference trace."""
    return parse(run_spike(elf, timeout), Path(elf).name, entry, tohost)


def _symbols(elf):
    """ELF symbol table via the pinned toolchain's nm (needs setup.sh)."""
    p = dict(l.split("=", 1) for l in (BUILD / "paths.env").read_text().split())
    out = subprocess.run([str(Path(p["GCC"]).parent / "riscv-none-elf-nm"), str(elf)],
                         check=True, capture_output=True, text=True).stdout
    syms = {}
    for m in re.finditer(r"^([0-9a-f]+) \w (\w+)$", out, re.M):
        syms[m.group(2)] = int(m.group(1), 16)
    return syms


def main(argv):
    args = argv[1:]
    json_out = None
    if args and args[0] == "--json":
        json_out, args = args[1], args[2:]
    if not args:
        print("usage: spike_trace.py [--json OUT] ELF...", file=sys.stderr)
        return 2
    all_traces = {}
    for elf in args:
        syms = _symbols(elf)
        t = trace_for(elf, syms["tohost"])
        exc = sum(1 for r in t if r.get("exception"))
        print(f"{Path(elf).name}: {len(t)} records ({exc} exceptions), "
              f"first pc {t[0]['pc']:#x}, stops at tohost store")
        all_traces[Path(elf).name] = t
    if json_out:
        Path(json_out).write_text(json.dumps(all_traces, indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
