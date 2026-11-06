"""Shared setup for the two riscv-arch-test drivers, runner.py and fv.py.

Both convert the pinned CVE2 closure through flow/core/sv2v.sh, build the test
programs with build_tests.py and walk tests.json (the first test only under
--negative-control). Needs verification/core/setup.sh to have run.
"""

import json
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent
BUILD = REPO / "verification" / "build"
TOP = "cve2_rv32imc_wrapper"


def paths():
    return dict(l.split("=", 1) for l in (BUILD / "paths.env").read_text().split())


def convert(p, out: Path) -> Path:
    """Convert via flow/core/sv2v.sh, the same entry point flow/core/synth.sh sources."""
    dest = out / f"{TOP}.v"
    subprocess.run(
        ["bash", str(REPO / "flow" / "core" / "sv2v.sh"), "convert", p["SV2V"], p["CVE2"],
         str(REPO / "rtl" / f"{TOP}.sv"), TOP, str(dest)],
        check=True)
    return dest


def prepare(out: Path, negative: bool):
    """Build the programs and convert the RTL: (tests_dir, test names, converted .v)."""
    out.mkdir(parents=True, exist_ok=True)
    p = paths()
    tests_dir = BUILD / "tests"
    subprocess.run([sys.executable, "-I", str(HERE / "build_tests.py"), str(tests_dir)], check=True)
    names = json.loads((tests_dir / "tests.json").read_text())
    if negative:
        names = names[:1]
    return tests_dir, names, convert(p, out)
