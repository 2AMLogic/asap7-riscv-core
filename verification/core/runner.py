"""Convert the pinned CVE2 closure, build it with Icarus, run every arch test.

Usage: python runner.py <run-dir> [--negative-control] [--gate]

Needs verification/core/setup.sh to have run. Writes <run-dir>/results.xml
(one <testcase> per arch-test program) and exits non-zero on any failure.
With --negative-control only the first test runs, with one expected signature
word deliberately flipped; the run is then expected to fail.

With --gate the DUT is the committed synthesized netlist
(flow/core/records/2026-11-03/netlist.v) plus the pinned ASAP7 RVT functional
cell Verilog, zero delay (specify blocks ignored), pre-layout. Same programs,
signatures and excluded.json. Also writes <run-dir>/record.json (program count,
failures, tool versions, netlist and model hashes).
"""

import hashlib
import json
import subprocess
import sys
import xml.etree.ElementTree as ET
from datetime import datetime, timezone
from pathlib import Path

from cocotb_tools.runner import get_runner

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))  # fv.sh runs this with -I, which drops the script dir

from archtest_common import (GATE_BUILD_ARGS, NETLIST, REPO, gate_sources, paths,  # noqa: E402
                             prepare)


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_record(run_dir, negative, names, failed, failures, srcs):
    pins = dict(l.split("=", 1) for l in (REPO / "verification" / "tool-versions.txt").read_text().splitlines()
                if "=" in l and not l.startswith("#"))
    iv = subprocess.run(["iverilog", "-V"], capture_output=True, text=True).stdout.splitlines()[0]
    import cocotb
    record = {
        "suite": "riscv-arch-test",
        "mode": "gate-level, zero-delay functional, pre-layout (no SDF, no timing)",
        "negative_control": negative,
        "date_utc": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "tests_run": len(names),
        "tests_failed": failed,
        "failures": failures,
        "excluded": json.loads((HERE / "excluded.json").read_text()),
        "tools": {"iverilog": iv, "iverilog_build_args": GATE_BUILD_ARGS,
                  "cocotb": cocotb.__version__, "riscv_arch_test_commit": pins["riscv_arch_test_commit"],
                  "sail_riscv_release": pins["sail_riscv_release"]},
        "netlist": {"path": str(NETLIST.relative_to(REPO)), "sha256": sha256(NETLIST)},
        "cell_models": {"asap7sc7p5t_28_commit": pins["asap7_cells_commit"],
                        "files": {s.name: sha256(s) for s in srcs if s != NETLIST}},
        "tests": names,
    }
    (run_dir / "record.json").write_text(json.dumps(record, indent=2) + "\n")


def main(run_dir: Path, negative: bool, gate: bool = False) -> int:
    tests_dir, names, converted = prepare(run_dir, negative, gate)
    build_dir = run_dir / "sim_build"
    runner = get_runner("icarus")
    srcs = gate_sources(paths()) if gate else [converted]
    runner.build(sources=[*srcs, HERE / "tb_core.v"], hdl_toplevel="tb_core",
                 build_dir=build_dir, always=True,
                 build_args=GATE_BUILD_ARGS if gate else ["-g2012"])

    merged = ET.Element("testsuites")
    suite = ET.SubElement(merged, "testsuite", name="riscv-arch-test")
    failed = 0
    failures = []
    for n in names:
        meta = json.loads((tests_dir / f"{n}.json").read_text())
        xml = run_dir / f"{n}.xml"
        runner.test(
            hdl_toplevel="tb_core", test_module="test_archtest", test_dir=HERE,
            build_dir=build_dir, results_xml=xml,
            plusargs=[f"+HEX={tests_dir / (n + '.hex')}", f"+TOHOST={meta['tohost']:x}"],
            extra_env={"ARCHTEST_JSON": str(tests_dir / f"{n}.json"),
                       "CORE_NEGATIVE_CONTROL": "1" if negative else "0",
                       "PYTHONPATH": str(HERE)},
            test_filter=None)
        for tc in ET.parse(xml).getroot().iter("testcase"):
            tc.set("name", n)
            suite.append(tc)
            bad = tc.find("failure")
            if bad is None:
                bad = tc.find("error")
            if bad is not None:
                failed += 1
                failures.append({"test": n, "message": (bad.get("message") or bad.text or "")[:300]})
                print(f"FAIL {n}")
    ET.ElementTree(merged).write(run_dir / "results.xml")
    total = len(names)
    if gate:
        write_record(run_dir, negative, names, failed, failures, srcs)
    print(f"arch-test{' (gate)' if gate else ''}: {total} test(s) run, {failed} failed; results: {run_dir / 'results.xml'}")
    return 1 if failed or not total else 0


if __name__ == "__main__":
    flags = sys.argv[2:]
    sys.exit(main(Path(sys.argv[1]).resolve(), "--negative-control" in flags, "--gate" in flags))
