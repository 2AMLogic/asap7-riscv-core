"""Self-test for the Spike retirement-trace reader (verification/core/spike_trace.py).

Run after verification/core/setup.sh and verification/core/spike_setup.sh:

    python3 -I verification/core/test_spike_trace.py

Checks, from the issue's test plan:
- a small deterministic ELF (built here with the pinned GCC and the same
  link.ld/tohost convention as build_tests.py) exercises a compressed
  instruction, a discarded write to x0, a machine CSR write/read-back
  (mtvec in CVE2's representable shape: vectored, 256-byte-aligned base),
  a synchronous trap (ebreak) with handler entry, mcause/mepc read-back and
  the mret return, and the final store to tohost;
- one suite ELF's first PC and final store are checked against its symbols
  and disassembly, and the trace carries no exceptions;
- a fixed ELF's commit log is byte-identical across two runs;
- a truncated and a malformed log each fail, naming the program.

Exit status: 0 every case passed; 1 a case failed.
"""

import json
import re
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import spike_trace as st  # noqa: E402

BUILD = HERE.parent / "build"
OUT = BUILD / "spike-selftest"

PASS = FAIL = 0


def ok(msg):
    global PASS
    PASS += 1
    print(f"ok   - {msg}")


def no(msg):
    global FAIL
    FAIL += 1
    print(f"FAIL - {msg}")


def check(cond, msg):
    (ok if cond else no)(msg)
    return cond


# The deterministic program. The mtvec write is the shape both the reference
# and CVE2 reproduce exactly (MODE=vectored, 256-byte-aligned base - decision
# 0011); the ebreak is a synchronous exception, so the handler sits at the
# mtvec BASE (the vectored base+4*cause offset is for interrupts only).
TRAP_ASM = r"""
    .section .text.init, "ax", @progbits
    .globl rvtest_entry_point
rvtest_entry_point:
    c.addi a5, 5                 # compressed
    addi x0, a5, 3               # write to x0: architecturally discarded
    la t0, vector_base
    ori t0, t0, 1                # vectored mode, base stays 256-byte aligned
    csrw mtvec, t0
    csrr t1, mtvec               # read-back must equal the written value
    la s0, sig
    sw t1, 0(s0)
    ebreak                       # synchronous trap: mcause = 3
back_from_trap:
    la t0, tohost
    li t1, 1
    sw t1, 0(t0)                 # the halt store the trace stops at
1:  j 1b

    .section .text, "ax", @progbits
    .align 8
vector_base:
trap_handler:
    csrr t2, mcause
    csrr t3, mepc
    la t4, back_from_trap
    csrw mepc, t4
    mret

    .pushsection .tohost, "aw", @progbits
    .align 8; .global tohost; tohost: .dword 0;
    .align 8; .global fromhost; fromhost: .dword 0;
    .popsection
    .section .data
    .align 4
sig: .word 0
"""


def gcc_bin():
    if not (BUILD / "paths.env").is_file():
        print("FAIL - verification/build/paths.env missing: run verification/core/setup.sh first")
        return None
    p = dict(l.split("=", 1) for l in (BUILD / "paths.env").read_text().split())
    return Path(p["GCC"]).parent


def build_det(gb):
    OUT.mkdir(parents=True, exist_ok=True)
    src = OUT / "spike_selftest.S"
    src.write_text(TRAP_ASM)
    elf = OUT / "spike_selftest.elf"
    subprocess.run(
        [str(gb / "riscv-none-elf-gcc"), "-march=rv32imc_zicsr", "-mabi=ilp32",
         "-static", "-mcmodel=medany", "-fvisibility=hidden", "-nostdlib", "-nostartfiles",
         "-w", "-T", str(HERE / "link.ld"), str(src), "-o", str(elf)],
        check=True)
    return elf


def symbols(elf, gb):
    out = subprocess.run([str(gb / "riscv-none-elf-nm"), str(elf)],
                         check=True, capture_output=True, text=True).stdout
    return {m.group(2): int(m.group(1), 16)
            for m in re.finditer(r"^([0-9a-f]+) \w (\w+)$", out, re.M)}


def test_deterministic(elf, sym):
    t = st.trace_for(elf, sym["tohost"])
    entry = sym["rvtest_entry_point"]
    vector_base = sym["vector_base"]
    check(t[0]["pc"] == entry and t[0]["len"] == 2 and t[0]["rd"] == 15 and t[0]["rd_val"] == 5,
          "the ELF entry retires the compressed c.addi as a 2-byte record with rd/value")
    check(t[0]["priv"] == 3, "the program runs in machine mode (priv 3)")
    check(t[1]["pc"] == entry + 2 and t[1]["rd"] is None,
          "a write to x0 leaves no register-write record (architecturally discarded)")
    csrw_idx = next(i for i, r in enumerate(t)
                    if not r.get("exception") and any(c[0] == 0x305 for c in r["csr"]))
    csrr = t[csrw_idx + 1]
    check(t[csrw_idx]["csr"] == [(0x305, "mtvec", vector_base | 1)],
          f"csrw mtvec logs the CSR write ({vector_base | 1:#x}: vectored, 256-byte-aligned base)")
    check(csrr["pc"] == t[csrw_idx]["pc"] + 4 and csrr["rd"] == 6
          and csrr["rd_val"] == vector_base | 1,
          "csrr mtvec read-back equals the written value on the reference")
    sig_store = next(r for r in t if any(a == sym["sig"] for a, _v in r["stores"]))
    ebreak_pc = sig_store["pc"] + sig_store["len"]
    exc = [r for r in t if r.get("exception")]
    check(len(exc) == 1 and exc[0]["epc"] == ebreak_pc and exc[0]["handler"] == vector_base,
          f"ebreak at {ebreak_pc:#x} is a retirement gap entering the handler at the mtvec base "
          f"{vector_base:#x} (next PC after the trap)")
    h = t[t.index(exc[0]) + 1]
    check(h["pc"] == vector_base and h["rd"] == 7 and h["rd_val"] == 3,
          "the handler's first instruction reads mcause = 3 (breakpoint)")
    check(t[t.index(exc[0]) + 2]["rd"] == 28
          and t[t.index(exc[0]) + 2]["rd_val"] == ebreak_pc,
          f"the handler reads mepc = the trapping pc {ebreak_pc:#x}")
    mepcw = next(i for i, r in enumerate(t)
                 if not r.get("exception") and any(c[0] == 0x341 for c in r["csr"]))
    check(t[mepcw + 1]["pc"] == t[mepcw]["pc"] + 4
          and t[mepcw + 2]["pc"] == sym["back_from_trap"],
          "the handler logs its csrw mepc and the mret retires to it (back_from_trap)")
    check(t[-1]["stores"] == [(sym["tohost"], 1)]
          and t[-1]["pc"] == sym["back_from_trap"] + 0xa,
          "the trace stops at the store of 1 to tohost")
    return t


def test_suite(gb):
    names = json.loads((BUILD / "tests" / "tests.json").read_text())
    name = names[0]
    j = json.loads((BUILD / "tests" / f"{name}.json").read_text())
    elf = BUILD / "tests" / f"{name}.elf"
    sym = symbols(elf, gb)
    t = st.trace_for(elf, j["tohost"])
    check(t[0]["pc"] == 0x80000080 == sym["rvtest_entry_point"],
          f"{name}: first pc is the ELF entry (symbol-checked)")
    check(not any(r.get("exception") for r in t),
          f"{name}: the suite program takes no traps")
    check(t[-1]["stores"] == [(j["tohost"], 1)],
          f"{name}: last record is the store of 1 to tohost (json-supplied address)")
    dis = subprocess.run([str(gb / "riscv-none-elf-objdump"), "-d", str(elf)],
                         check=True, capture_output=True, text=True).stdout
    halt = sym["cve2_act_halt"]
    line = re.search(rf"^ *{t[-1]['pc']:08x}:\s*\S+\s+(\S+)", dis, re.M)
    next_syms = sorted(a for s, a in sym.items() if a > t[-1]["pc"])
    check(line is not None and line.group(1) == "sw" and next_syms and next_syms[0] == halt,
          f"{name}: the final store's pc disassembles as the sw just before cve2_act_halt")
    return elf


def test_negative(elf, tohost):
    raw = st.run_spike(elf)
    lines = [l for l in raw.splitlines() if l.startswith("core")]
    store_line = next(i for i, l in enumerate(lines) if f" mem {tohost:#x} 0x00000001" in l)
    truncated = "\n".join(lines[:store_line]) + "\n"
    for label, bad in (("truncated", truncated),
                       ("malformed", truncated + "core   0: nonsense\n")):
        try:
            st.parse(bad, Path(elf).name, 0x80000080, tohost)
        except st.TraceError as e:
            check(Path(elf).name in str(e),
                  f"a {label} trace fails naming the program: {str(e)[:60]}")
        else:
            no(f"a {label} trace must fail, but parse() returned")
    check(len(lines) > store_line + 1,
          "the raw log continues past the tohost store and the reader cuts it")


def test_malformed_effects():
    """Every malformed effect shape raises TraceError naming the program (pure
    parse(), no Spike), and a vectored mtvec base need not be 256-byte aligned."""
    good = "core   0: 3 0x80000080 (0x00000013)"
    for tail in ("x5", "x5 zzzz", "c_mtvec 0x1", "c773_mtvec", "c773_mtvec zz",
                 "mem", "mem zzz", "mem 0x80003000 0xzz", "v3_vreg 0x1"):
        try:
            st.parse(f"{good} {tail}\n", "prog.elf", 0x80000080, 0x80001000)
        except st.TraceError as e:
            check("prog.elf" in str(e), f"malformed effects {tail!r} -> TraceError naming the program")
        except Exception as e:  # IndexError / ValueError escaping is the defect
            no(f"malformed effects {tail!r} escaped as {type(e).__name__}")
        else:
            no(f"malformed effects {tail!r} must fail, but parse() returned")
    log = ("core   0: 3 0x80000080 (0x00100073) c773_mtvec 0x80002041\n"
           "core   0: 3 0x80000084 (0x00000013)\n"
           "core   0: 3 0x80002040 (0x00000013)\n"
           "core   0: 3 0x80002044 (0x00000013) mem 0x80001000 0x00000001\n")
    try:
        t = st.parse(log, "prog.elf", 0x80000080, 0x80001000)
        check(t[2].get("exception") and t[2]["handler"] == 0x80002040,
              "an unaligned vectored mtvec base traps to BASE (& ~3), as Spike does")
    except st.TraceError as e:
        no(f"unaligned vectored mtvec base rejected: {e}")


def test_repeatable(elf):
    a = st.run_spike(elf)
    b = st.run_spike(elf)
    check(a == b, "the commit log for a fixed ELF is byte-identical across two runs")


def main():
    gb = gcc_bin()
    if gb is None:
        return 1
    try:
        st.spike_paths()
    except st.TraceError as e:
        print(f"FAIL - {e}")
        return 1
    det = build_det(gb)
    sym = symbols(det, gb)
    test_deterministic(det, sym)
    suite_elf = test_suite(gb)
    suite_json = json.loads((BUILD / "tests" / "tests.json").read_text())[0]
    tohost = json.loads((BUILD / "tests" / f"{suite_json}.json").read_text())["tohost"]
    test_negative(suite_elf, tohost)
    test_malformed_effects()
    test_repeatable(det)
    print(f"test_spike_trace: {PASS} passed, {FAIL} failed")
    return 1 if FAIL else 0


if __name__ == "__main__":
    sys.exit(main())
