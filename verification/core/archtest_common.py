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
# The committed synthesized netlist the gate-level run simulates (#25), and the
# cell-library Verilog groups it instantiates (pins in tool-versions.txt).
NETLIST = REPO / "flow" / "core" / "records" / "2026-11-03" / "netlist.v"
CELL_GROUPS = ["AO_RVT_TT_201020", "INVBUF_RVT_TT_201020", "OA_RVT_TT_201020",
               "SIMPLE_RVT_TT_201020", "SEQ_RVT_TT_220101"]
# Zero-delay functional run: ignore the models' specify blocks (timing arcs and
# $setuphold checks); the vendor files themselves are used unmodified.
GATE_BUILD_ARGS = ["-g2012", "-gno-specify"]


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


def gate_sources(p):
    """DUT sources for --gate: the vendor cell models, then the committed netlist."""
    return [*(Path(p["CELLS"]) / f"asap7sc7p5t_{g}.v" for g in CELL_GROUPS), NETLIST]


def prepare(out: Path, negative: bool, gate: bool = False):
    """Build the programs and the DUT source: (tests_dir, test names, DUT .v).

    With gate=True the DUT is the committed netlist (no sv2v conversion)."""
    out.mkdir(parents=True, exist_ok=True)
    p = paths()
    tests_dir = BUILD / "tests"
    subprocess.run([sys.executable, "-I", str(HERE / "build_tests.py"), str(tests_dir)], check=True)
    names = json.loads((tests_dir / "tests.json").read_text())
    if negative:
        names = names[:1]
    return tests_dir, names, (NETLIST if gate else convert(p, out))
