"""Convert the pinned CVE2 closure, build it with Icarus, run every arch test.

Usage: python runner.py <run-dir> [--negative-control]

Needs verification/core/setup.sh to have run. Writes <run-dir>/results.xml
(one <testcase> per arch-test program) and exits non-zero on any failure.
With --negative-control only the first test runs, with one expected signature
word deliberately flipped; the run is then expected to fail.
"""

import json
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

from cocotb_tools.runner import get_runner

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))  # fv.sh runs this with -I, which drops the script dir

from archtest_common import prepare  # noqa: E402


def main(run_dir: Path, negative: bool) -> int:
    tests_dir, names, converted = prepare(run_dir, negative)
    build_dir = run_dir / "sim_build"
    runner = get_runner("icarus")
    runner.build(sources=[converted, HERE / "tb_core.v"], hdl_toplevel="tb_core",
                 build_dir=build_dir, always=True,
                 build_args=["-g2012"])

    merged = ET.Element("testsuites")
    suite = ET.SubElement(merged, "testsuite", name="riscv-arch-test")
    failed = 0
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
            if tc.find("failure") is not None or tc.find("error") is not None:
                failed += 1
                print(f"FAIL {n}")
    ET.ElementTree(merged).write(run_dir / "results.xml")
    total = len(names)
    print(f"arch-test: {total} test(s) run, {failed} failed; results: {run_dir / 'results.xml'}")
    return 1 if failed or not total else 0


if __name__ == "__main__":
    sys.exit(main(Path(sys.argv[1]).resolve(), "--negative-control" in sys.argv[2:]))
