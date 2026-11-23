"""Lockstep driver: run the arch-test corpus and the deterministic longer
program on cve2_rv32imc_wrapper, comparing every RVFI retirement against the
pinned Spike reference while the simulation runs (issue #206, part of #204).

Usage (after verification/core/setup.sh, spike_setup.sh, and a verification
venv with requirements.txt - verification/lockstep.sh wraps all of it):

    python lockstep.py <run-dir>                  full corpus + longer program
    python lockstep.py <run-dir> --negative-control
                                                  longer program clean (must
                                                  pass), then the same program
                                                  with one bit of a known
                                                  write-back corrupted in the
                                                  observation path (must fail
                                                  on that exact retirement);
                                                  exit 0 only if both hold

What it does per program: runs the pinned Spike (spike_trace.trace_for) on the
ELF build_tests.py built, disassembles it with the pinned toolchain, converts
the CVE2 closure through flow/core/sv2v.sh with -DRVFI (the same entry point
as the attested netlist conversion; the extra define exposes the RVFI port
and the per-CSR verification-only observation), builds once with Icarus, then
runs one cocotb test per program (test_lockstep.py) feeding retirements to
lockstep_compare.Lockstep.

Writes <run-dir>/results.xml (JUnit, one testcase per program),
<run-dir>/record.json (programs, retirement counts, runtimes, tools, the
longer program's identity, negative-control outcome; host paths scrubbed to
<scratch>/<repo>) and exits non-zero on any failure.
"""

import hashlib
import json
import re
import subprocess
import sys
import time
import xml.etree.ElementTree as ET
from datetime import datetime, timezone
from pathlib import Path

from cocotb_tools.runner import get_runner

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))  # lockstep.sh runs this with -I, which drops the script dir

import spike_trace as st  # noqa: E402
from archtest_common import REPO, paths  # noqa: E402
from fv import scrub  # noqa: E402

BUILD = REPO / "verification" / "build"
TOP = "cve2_rv32imc_wrapper"
LONG_NAME = "lockstep-prog"


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def convert_rvfi(p, out: Path) -> Path:
    """Convert the closure with -DRVFI through flow/core/sv2v.sh convert."""
    dest = out / f"{TOP}_rvfi.v"
    subprocess.run(
        ["bash", str(REPO / "flow" / "core" / "sv2v.sh"), "convert", p["SV2V"], p["CVE2"],
         str(REPO / "rtl" / f"{TOP}.sv"), TOP, str(dest), "-DRVFI"],
        check=True)
    return dest


def build_long_program(p, out: Path) -> dict:
    """Assemble verification/core/lockstep_prog.S; return its meta (like
    build_tests.py's per-test json, plus the elf/hex paths)."""
    gcc_bin = Path(p["GCC"]).parent
    src = HERE / "lockstep_prog.S"
    elf = out / f"{LONG_NAME}.elf"
    subprocess.run(
        [p["GCC"], "-march=rv32imc_zicsr", "-mabi=ilp32", "-static", "-mcmodel=medany",
         "-fvisibility=hidden", "-nostdlib", "-nostartfiles", "-w",
         "-T", str(HERE / "link.ld"), str(src), "-o", str(elf)], check=True)
    binf = out / f"{LONG_NAME}.bin"
    subprocess.run([str(gcc_bin / "riscv-none-elf-objcopy"), "-O", "binary",
                    str(elf), str(binf)], check=True)
    raw = binf.read_bytes()
    raw += b"\0" * (-len(raw) % 4)
    words = [int.from_bytes(raw[i:i + 4], "little") for i in range(0, len(raw), 4)]
    (out / f"{LONG_NAME}.hex").write_text(
        "@20\n" + "".join(f"{w:08x}\n" for w in words))
    binf.unlink()
    syms = subprocess.run([str(gcc_bin / "riscv-none-elf-nm"), str(elf)], check=True,
                          capture_output=True, text=True).stdout
    sym = {m.group(2): int(m.group(1), 16)
           for m in re.finditer(r"^([0-9a-f]+) \w (\w+)$", syms, re.M)}
    return {"name": LONG_NAME, "elf": elf, "hex": out / f"{LONG_NAME}.hex",
            "tohost": sym["tohost"], "source": "verification/core/lockstep_prog.S",
            "source_sha256": sha256(src)}


def disasm(p, elf) -> dict:
    gcc_bin = Path(p["GCC"]).parent
    out = subprocess.run([str(gcc_bin / "riscv-none-elf-objdump"), "-d", str(elf)],
                         check=True, capture_output=True, text=True).stdout
    return {int(m.group(1), 16): m.group(2).strip()
            for m in re.finditer(r"^\s*([0-9a-f]+):\s+(?:[0-9a-f]+\s+)+(.*)$", out, re.M)}


def reference_for(elf, tohost):
    return st.trace_for(elf, tohost)


def run_one(runner, build_dir, meta, tests_dir, out: Path, inject=None):
    """One cocotb program run; returns (passed, stats, message, testcases)."""
    ref = reference_for(tests_dir / f"{meta['name']}.elf", meta["tohost"])
    spec = {"name": meta["name"], "tohost": meta["tohost"], "reference": ref,
            "disasm": {f"{pc:x}": text for pc, text in disasm(paths(), tests_dir / f"{meta['name']}.elf").items()},
            "inject": inject}
    j = out / f"{meta['name']}.lockstep.json"
    j.write_text(json.dumps(spec))
    stats_path = out / f"{meta['name']}.stats.json"
    stats_path.unlink(missing_ok=True)
    xml = out / f"{meta['name']}.xml"
    runner.test(hdl_toplevel="tb_core", test_module="test_lockstep", test_dir=HERE,
                build_dir=build_dir, results_xml=xml,
                plusargs=[f"+HEX={tests_dir / (meta['name'] + '.hex')}",
                          f"+TOHOST={meta['tohost']:x}"],
                extra_env={"LOCKSTEP_JSON": str(j), "LOCKSTEP_STATS": str(stats_path),
                           "PYTHONPATH": str(HERE)},
                test_filter=None)
    bad = None
    tcs = []
    for tc in ET.parse(xml).getroot().iter("testcase"):
        tc.set("name", meta["name"])
        tcs.append(tc)
        b = tc.find("failure")
        if b is None:
            b = tc.find("error")
        if b is not None:
            bad = b.get("message") or b.get("error_msg") or b.text or ""
    stats = json.loads(stats_path.read_text()) if stats_path.exists() \
        else {"retirements": 0, "cycles": 0, "mismatch": {"text": "no stats written"}}
    return bad is None, stats, bad, tcs


def negative_control(runner, build_dir, meta, tests_dir, out: Path) -> dict:
    """Clean pass required, then the injected run must fail on the exact
    retirement, pc, destination and value (issue #206 acceptance criterion)."""
    ref = reference_for(tests_dir / f"{meta['name']}.elf", meta["tohost"])
    ordinal = next(i + 1 for i, r in enumerate(ref)
                   if not r.get("exception") and r["rd"] not in (None, 0)
                   and (r["rd_val"] or 0) != 0)
    rec = ref[ordinal - 1]
    bit = 0
    expect_val, observed_val = rec["rd_val"], rec["rd_val"] ^ (1 << bit)

    ok, stats, _, _ = run_one(runner, build_dir, meta, tests_dir, out)
    if not ok:
        return {"outcome": "clean-run-failed", "ordinal": ordinal}
    ok, stats2, msg, _ = run_one(runner, build_dir, meta, tests_dir, out,
                                 inject=f"{ordinal}:{bit}")
    want = [f"retirement {ordinal}", f"{rec['pc']:#010x}", f"x{rec['rd']}",
            f"expected {expect_val:#x} ({expect_val})", f"dut {observed_val:#x} ({observed_val})"]
    return {"outcome": "detected" if (not ok and all(w in (msg or "") for w in want)) else "NOT-DETECTED",
            "ordinal": ordinal, "pc": rec["pc"], "rd": rec["rd"],
            "expected": expect_val, "observed": observed_val, "message": msg,
            "clean_retirements": stats.get("retirements")}


def main(run_dir: Path, negative: bool) -> int:
    run_dir.mkdir(parents=True, exist_ok=True)
    p = paths()
    tests_dir = BUILD / "tests"
    tests_dir.mkdir(parents=True, exist_ok=True)
    long_meta = build_long_program(p, run_dir)
    # The longer program lives beside the built corpus for run_one()'s naming.
    for ext in ("elf", "hex"):
        (tests_dir / f"{LONG_NAME}.{ext}").write_bytes((run_dir / f"{LONG_NAME}.{ext}").read_bytes())

    converted = convert_rvfi(p, run_dir)
    build_dir = run_dir / "sim_build"
    runner = get_runner("icarus")
    runner.build(sources=[converted, HERE / "tb_core.v"], hdl_toplevel="tb_core",
                 build_dir=build_dir, always=True, build_args=["-g2012"])

    if negative:
        neg = negative_control(runner, build_dir, long_meta, tests_dir, run_dir)
        record = {"suite": "spike-lockstep-negative-control",
                  "date_utc": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
                  "program": long_meta["source"], "control": scrub(neg, [(str(run_dir), "<scratch>")])}
        (run_dir / "record.json").write_text(json.dumps(record, indent=2) + "\n")
        print(json.dumps(record["control"], indent=2)[:2000])
        return 0 if neg["outcome"] == "detected" else 1

    subprocess.run([sys.executable, "-I", str(HERE / "build_tests.py"), str(tests_dir)], check=True)
    names = json.loads((tests_dir / "tests.json").read_text())
    t0 = time.monotonic()
    merged = ET.Element("testsuites")
    suite = ET.SubElement(merged, "testsuite", name="spike-lockstep")
    failed, failures, per_test = 0, [], []
    for meta in [{**json.loads((tests_dir / f"{n}.json").read_text()), "name": n} for n in names] \
            + [long_meta]:
        t1 = time.monotonic()
        ok, stats, msg, tcs = run_one(runner, build_dir, meta, tests_dir, run_dir)
        dt = time.monotonic() - t1
        suite.extend(tcs)
        if not ok:
            failed += 1
            failures.append({"test": meta["name"], "message": (msg or "")[:300]})
            print(f"FAIL {meta['name']}: {(msg or '')[:200]}")
        per_test.append({"test": meta["name"], "retirements": stats.get("retirements"),
                         "cycles": stats.get("cycles"), "seconds": round(dt, 1),
                         "status": "pass" if ok else "FAIL"})
        print(f"{'PASS' if ok else 'FAIL'} {meta['name']}: "
              f"{stats.get('retirements')} retirements in {dt:.1f}s", flush=True)
    wall = time.monotonic() - t0
    ET.ElementTree(merged).write(run_dir / "results.xml")

    iv = subprocess.run(["iverilog", "-V"], capture_output=True, text=True).stdout.splitlines()[0]
    import cocotb
    long_ref = reference_for(tests_dir / f"{long_meta['name']}.elf", long_meta["tohost"])
    record = {
        "suite": "spike-lockstep",
        "mode": "RTL simulation of the sv2v-converted CVE2 closure with -DRVFI, "
                "every RVFI retirement compared against the pinned Spike "
                "reference in lockstep (first divergence reported)",
        "date_utc": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "tests_run": len(per_test), "tests_failed": failed, "failures": failures,
        "excluded": json.loads((HERE / "excluded.json").read_text()),
        "longer_program": {"source": long_meta["source"],
                           "source_sha256": long_meta["source_sha256"],
                           "retirements": len(long_ref),
                           "retired_in_sim": next(t["retirements"] for t in per_test
                                                  if t["test"] == long_meta["name"])},
        "runtime_seconds": round(wall, 1),
        "tools": {"iverilog": iv, "cocotb": cocotb.__version__,
                  "spike_commit": st.pin("spike_commit"),
                  "sv2v_defines": ["SYNTHESIS", "RVFI"]},
        "tests": per_test,
    }
    subs = [(str(run_dir), "<scratch>"), (str(REPO), "<repo>")]
    (run_dir / "record.json").write_text(json.dumps(scrub(record, subs), indent=2) + "\n")
    print(f"lockstep: {len(per_test)} test(s) run, {failed} failed, {wall:.0f}s wall; "
          f"results: {run_dir / 'results.xml'}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(Path(sys.argv[1]).resolve(), "--negative-control" in sys.argv[2:]))
