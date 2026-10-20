"""Build the placeholder DUT with Icarus and run the cocotb test.

Usage: python runner.py <run-dir>
Writes <run-dir>/results.xml (JUnit-style) and exits non-zero on any failure.
"""

import sys
import xml.etree.ElementTree as ET
from pathlib import Path

from cocotb_tools.runner import get_runner

HERE = Path(__file__).resolve().parent


def main(run_dir: Path) -> int:
    run_dir.mkdir(parents=True, exist_ok=True)
    build_dir = run_dir / "sim_build"
    runner = get_runner("icarus")
    runner.build(
        sources=[HERE / "counter.sv"],
        hdl_toplevel="counter",
        build_dir=build_dir,
        always=True,
    )
    results = runner.test(
        hdl_toplevel="counter",
        test_module="test_counter",
        test_dir=HERE,
        build_dir=build_dir,
        results_xml=run_dir / "results.xml",
    )
    root = ET.parse(results).getroot()
    tests = root.findall(".//testcase")
    bad = [t for t in tests if t.find("failure") is not None or t.find("error") is not None]
    print(f"cocotb: {len(tests)} test(s), {len(bad)} failed; results: {results}")
    return 1 if bad or not tests else 0


if __name__ == "__main__":
    sys.exit(main(Path(sys.argv[1]).resolve()))
