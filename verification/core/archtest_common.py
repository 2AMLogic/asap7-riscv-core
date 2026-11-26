"""Shared setup for the two riscv-arch-test drivers, runner.py and fv.py.

Both convert the pinned CVE2 closure through flow/core/sv2v.sh, build the test
programs with build_tests.py and walk tests.json: the full suite from the
shared verification/build/tests, or under --negative-control the first
program only, built into the run directory. Needs verification/core/setup.sh
to have run.
"""

import json
import subprocess
import sys
from pathlib import Path
from tempfile import mkdtemp

HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent
BUILD = REPO / "verification" / "build"
TOP = "cve2_rv32imc_wrapper"
# The committed synthesized netlist the gate-level run simulates (#25). The
# cell-library Verilog groups it instantiates are not restated here: they are a
# function of this netlist, pinned one key per group in tool-versions.txt, and
# setup.sh publishes that set through paths.env as CELL_GROUPS.
NETLIST = REPO / "flow" / "core" / "records" / "2026-11-14" / "netlist.v"
# Zero-delay functional run: ignore the models' specify blocks (timing arcs and
# $setuphold checks); the vendor files themselves are used unmodified.
GATE_BUILD_ARGS = ["-g2012", "-gno-specify"]
# tb_core.v's RAM (its localparam WORDS): 32-bit words at 0x80000000.
MEM_WORDS = 1 << 19
# The objcopy binary starts at the first loaded section (link.ld: 0x80000080,
# tb_core's boot address), which is that RAM's word address 0x20.
LOAD_WORD = 0x80 // 4


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


def hex_image(raw: bytes, name: str) -> str:
    """An objcopy binary as the $readmemh text tb_core.v loads: little-endian
    32-bit words from LOAD_WORD, the last word zero-padded. An image that does
    not fit in the RAM above LOAD_WORD raises ValueError naming the program,
    before any word list is built. The check is a raise, not an assert, so it
    holds under python -O."""
    if LOAD_WORD + -(-len(raw) // 4) > MEM_WORDS:
        raise ValueError(f"{name} does not fit in memory")
    padded = raw + b"\0" * (-len(raw) % 4)
    words = [int.from_bytes(padded[i:i + 4], "little") for i in range(0, len(padded), 4)]
    return f"@{LOAD_WORD:x}\n" + "".join(f"{w:08x}\n" for w in words)


def gate_sources(p):
    """DUT sources for --gate: the vendor cell models, then the committed netlist.

    The group set comes from paths.env, which setup.sh derives from the
    asap7_cells_<GRP>_sha256 pins, so tool-versions.txt is its one source."""
    groups = p["CELL_GROUPS"].split(",")
    return [*(Path(p["CELLS"]) / f"asap7sc7p5t_{g}.v" for g in groups), NETLIST]


def prepare(out: Path, negative: bool, gate: bool = False):
    """Build the programs and the DUT source: (tests_dir, test names, DUT .v).

    With gate=True the DUT is the committed netlist (no sv2v conversion).
    With negative=True only the first program is built under out. Its
    one-entry tests.json must stay separate from the full suite's manifest."""
    out.mkdir(parents=True, exist_ok=True)
    p = paths()
    shared_tests = BUILD / "tests"
    tests_dir = out / "tests" if negative else shared_tests
    if negative and tests_dir.resolve() == shared_tests.resolve():
        # fv.sh accepts BUILD itself as the output directory.
        tests_dir = Path(mkdtemp(prefix="control-tests-", dir=out))
    limit = ["--first-only"] if negative else []
    subprocess.run([sys.executable, "-I", str(HERE / "build_tests.py"), str(tests_dir), *limit], check=True)
    names = json.loads((tests_dir / "tests.json").read_text())
    return tests_dir, names, (NETLIST if gate else convert(p, out))
