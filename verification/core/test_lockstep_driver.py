"""Offline self-test for the lockstep driver (lockstep.py).

    python3 -I verification/core/test_lockstep_driver.py

No simulator, no Spike, no toolchain and no network: the real main() runs in
both modes over two tiny fixture programs, with the Spike trace provider,
the disassembly, the program build, the DUT conversion, the corpus build and
cocotb's runner stood in by stubs that count every invocation. The runner
stub plays the bench (test_lockstep.py): it feeds each spec's reference to
the real comparator (lockstep_compare.Lockstep) with a matching DUT stream,
corrupts the write-back the spec names, and writes the stats and JUnit files
the driver reads, so the driver's verdict is reached through the comparator
the real lane uses.

It pins issue #302: one reference and one disassembly per program per
invocation, however many simulations compare against them; the negative
control still detecting the committed mismatch; and the full suite's report
taking the longer program's reference count from the trace its simulation
compared against.

Exit status: 0 every case passed; 1 a case failed.
"""

import contextlib
import copy
import io
import json
import subprocess
import sys
import tempfile
import types
from pathlib import Path
from unittest import mock
from xml.etree import ElementTree as ET

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from lockstep_compare import Lockstep  # noqa: E402

# lockstep.py imports cocotb's runner at module scope and names the cocotb
# version in its report; neither exists outside the venv, so both are stood
# in before the driver is imported.
tools = types.ModuleType("cocotb_tools")
tools.runner = types.ModuleType("cocotb_tools.runner")
tools.runner.get_runner = None
cocotb = types.ModuleType("cocotb")
cocotb.__version__ = "0.0 (self-test stub)"
sys.modules.update({"cocotb_tools": tools, "cocotb_tools.runner": tools.runner,
                    "cocotb": cocotb})

import lockstep  # noqa: E402

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


TOHOST = 0x8000_1000
ENTRY = 0x8000_0080
CORPUS = ["I-add-01"]
COMMITTED = (HERE.parent / "records" / "2026-11-20"
             / "lockstep-core-archtest-negative-control.json")


def insn(pc, enc, rd=None, rd_val=None, stores=()):
    """One reference record, in spike_trace.parse()'s shape."""
    return {"pc": pc, "enc": enc, "len": 4, "priv": 3, "rd": rd, "rd_val": rd_val,
            "csr": [], "loads": [], "stores": list(stores)}


def as_json(obj):
    """obj as the bench reads it back from the spec file (tuples -> lists)."""
    return json.loads(json.dumps(obj))


HALT = (TOHOST, 1)  # the retiring store that ends a run
TRACES = {
    "I-add-01.elf": [insn(ENTRY, 0x00652023, stores=[HALT])],  # sw t1,0(t0)
    "lockstep-prog.elf": [
        insn(ENTRY, 0x00500413, rd=8, rd_val=5),               # addi s0,zero,5: the control's target
        insn(ENTRY + 4, 0x04000513, rd=10, rd_val=64),         # addi a0,zero,64
        insn(ENTRY + 8, 0x00652023, stores=[HALT]),            # sw t1,0(t0)
    ],
}
DISASM = {ENTRY: "li\ts0,5", ENTRY + 4: "li\ta0,64", ENTRY + 8: "sw\tt1,0(t0)"}
LONG = f"{lockstep.LONG_NAME}.elf"


class TraceProvider:
    """Stands in for spike_trace.trace_for: every request is counted, and the
    fixture trace of the program asked for is returned as a fresh copy."""

    def __init__(self):
        self.requests = []

    def __call__(self, elf, tohost):
        self.requests.append((Path(elf).name, tohost))
        return copy.deepcopy(TRACES[Path(elf).name])


class Disassembly:
    """Stands in for lockstep.disasm(): every request is counted."""

    def __init__(self):
        self.requests = []

    def __call__(self, _p, elf):
        self.requests.append(Path(elf).name)
        return dict(DISASM)


class StubRunner:
    """Stands in for cocotb's runner.

    test() plays test_lockstep.py for the spec it is given: a DUT stream
    matching the reference, the injected write-back bit flipped before the
    comparison, and the stats and JUnit files written the way the bench
    writes them.

    fault="clean" corrupts retirement 2 of every run, so the clean run fails
    on a retirement the control did not choose. fault="other" leaves the
    clean run intact but corrupts retirement 2 of the injected run instead
    of the one it names.
    """

    def __init__(self, fault=None):
        self.fault = fault
        self.runs = []  # the spec of every simulation, in order

    def build(self, **_kw):
        pass

    def test(self, *, extra_env, results_xml, **_kw):
        spec = json.loads(Path(extra_env["LOCKSTEP_JSON"]).read_text())
        self.runs.append(spec)
        disasm = {int(k, 16): v for k, v in spec["disasm"].items()}
        corrupt = tuple(int(x) for x in spec["inject"].split(":")) if spec["inject"] else None
        if self.fault == "clean" or (self.fault == "other" and corrupt):
            corrupt = (2, 0)
        cmp_ = Lockstep(spec["name"], spec["reference"], spec["tohost"])
        stats = {"retirements": 0, "cycles": 0, "mismatch": None}
        for cycle, r in enumerate(spec["reference"]):
            obs = {"order": cycle + 1, "pc": r["pc"], "insn": r["enc"], "trap": 0,
                   "priv": r["priv"], "rd_addr": r["rd"] or 0,
                   "rd_wdata": r["rd_val"] if r["rd"] not in (None, 0) else 0,
                   "mem_rmask": 0, "mem_wmask": 0, "mem_addr": 0, "mem_wdata": 0,
                   "cycle": cycle}
            if r["stores"]:
                obs.update(mem_wmask=0xF, mem_addr=r["stores"][0][0],
                           mem_wdata=r["stores"][0][1])
            if corrupt and cmp_.n + 1 == corrupt[0]:
                obs["rd_wdata"] ^= 1 << corrupt[1]
            m = cmp_.retirement(obs)
            stats["retirements"], stats["cycles"] = cmp_.n, cycle
            if m is not None:
                stats["mismatch"] = dict(m, text=m.format_text(disasm))
                break
        Path(extra_env["LOCKSTEP_STATS"]).write_text(json.dumps(stats))
        root = ET.Element("testsuites")
        tc = ET.SubElement(ET.SubElement(root, "testsuite"), "testcase", name=spec["name"])
        if stats["mismatch"] is not None:
            ET.SubElement(tc, "failure", message=stats["mismatch"]["text"])
        ET.ElementTree(root).write(results_xml)


def drive(negative, runner):
    """The real main() with every external stood in.

    Returns (exit status, record.json, trace requests, disassembly requests)."""
    traces, disasm = TraceProvider(), Disassembly()
    with tempfile.TemporaryDirectory(prefix="asap7-lockstep-driver.") as scratch, \
            contextlib.ExitStack() as stack:
        tmp = Path(scratch)
        run_dir = tmp / "run"
        long_meta = {"name": lockstep.LONG_NAME, "tohost": TOHOST,
                     "source": "verification/core/lockstep_prog.S",
                     "source_sha256": "0" * 64}

        def build_long_program(_p, out):
            for ext in ("elf", "hex"):
                (out / f"{lockstep.LONG_NAME}.{ext}").write_bytes(b"stub")
            return dict(long_meta)

        def run(cmd, **_kw):
            if cmd == ["iverilog", "-V"]:
                return subprocess.CompletedProcess(
                    cmd, 0, stdout="Icarus Verilog version 13.0 (stable) (v13_0)\n")
            if cmd[1:3] == ["-I", str(HERE / "build_tests.py")]:
                tests_dir = Path(cmd[3])
                (tests_dir / "tests.json").write_text(json.dumps(CORPUS))
                for n in CORPUS:
                    (tests_dir / f"{n}.json").write_text(json.dumps({"tohost": TOHOST}))
                return subprocess.CompletedProcess(cmd, 0)
            raise AssertionError(f"the driver ran an unexpected command: {cmd}")

        stack.enter_context(mock.patch.multiple(
            lockstep, BUILD=tmp / "build", build_long_program=build_long_program,
            convert_rvfi=lambda _p, out: out / "stub_rvfi.v",
            get_runner=lambda _sim: runner, disasm=disasm, paths=lambda: {},
            subprocess=types.SimpleNamespace(run=run)))
        stack.enter_context(mock.patch.object(lockstep.st, "trace_for", traces))
        with contextlib.redirect_stdout(io.StringIO()):
            rc = lockstep.main(run_dir, negative)
        record = json.loads((run_dir / "record.json").read_text())
    return rc, record, traces.requests, disasm.requests


print("# 1. the negative control: one reference, both simulations, the committed mismatch")
runner = StubRunner()
rc, record, traces, disasms = drive(True, runner)
control = record["control"]
committed = json.loads(COMMITTED.read_text())["control"]
check(rc == 0 and control["outcome"] == "detected",
      f"the control is detected and lockstep.py exits 0 (got exit {rc}, {control['outcome']})")
FIELDS = ("outcome", "ordinal", "pc", "rd", "expected", "observed", "message")
check({k: control[k] for k in FIELDS} == {k: committed[k] for k in FIELDS},
      "it reports the ordinal, pc, destination and expected/observed values of the committed "
      f"record {COMMITTED.parent.name}/{COMMITTED.name}")
check(traces == [(LONG, TOHOST)],
      f"Spike is asked for the reference once ({len(traces)} requests: {traces})")
check(disasms == [LONG],
      f"the program is disassembled once ({len(disasms)} requests: {disasms})")
check([s["inject"] for s in runner.runs] == [None, "1:0"],
      f"both simulations ran, clean then injected ({len(runner.runs)} runs: "
      f"{[s['inject'] for s in runner.runs]})")
check([s["reference"] for s in runner.runs] == [as_json(TRACES[LONG])] * 2,
      "both simulations compared against the one requested reference")
check(control["clean_retirements"] == len(TRACES[LONG]),
      "the clean run's retirement count is reported")

print()
print("# 2. the control still refuses a failed clean run and an unrelated failure")
runner = StubRunner(fault="clean")
rc, record, traces, _disasms = drive(True, runner)
check(rc == 1 and record["control"]["outcome"] == "clean-run-failed",
      f"a failed clean run is clean-run-failed, exit {rc}")
check(len(runner.runs) == 1,
      f"no injected simulation follows it ({len(runner.runs)} runs)")
check(len(traces) == 1, f"and one reference was requested for it ({len(traces)} requests)")
runner = StubRunner(fault="other")
rc, record, traces, _disasms = drive(True, runner)
check(rc == 1 and record["control"]["outcome"] == "NOT-DETECTED",
      f"an injected run failing on another retirement is NOT-DETECTED, exit {rc}")
check([s["inject"] for s in runner.runs] == [None, "1:0"] and len(traces) == 1,
      "after both simulations ran against the one reference")

print()
print("# 3. the full suite: one reference per program, the report's count from the compared trace")
runner = StubRunner()
rc, record, traces, disasms = drive(False, runner)
programs = [f"{n}.elf" for n in CORPUS] + [LONG]
check(rc == 0 and record["tests_run"] == len(programs) and record["tests_failed"] == 0,
      f"every program matches and lockstep.py exits 0 (exit {rc}, {record['tests_run']} run, "
      f"{record['tests_failed']} failed)")
check(traces == [(n, TOHOST) for n in programs],
      f"each program's reference is requested once, and the report requests none "
      f"({len(traces)} requests: {[n for n, _t in traces]})")
check(disasms == programs,
      f"each program is disassembled once ({len(disasms)} requests: {disasms})")
check([s["name"] for s in runner.runs] == [n[:-4] for n in programs]
      and not any(s["inject"] for s in runner.runs),
      f"one clean simulation per program ({[s['name'] for s in runner.runs]})")
longer = record["longer_program"]
in_sim = next(t["retirements"] for t in record["tests"] if t["test"] == lockstep.LONG_NAME)
check(longer["retirements"] == len(TRACES[LONG]) == longer["retired_in_sim"] == in_sim,
      "the report's reference count is the length of the trace the simulation compared "
      f"against, and the DUT retired as many (reference {longer['retirements']}, "
      f"in sim {longer['retired_in_sim']})")

print()
print(f"test_lockstep_driver: {PASS} passed, {FAIL} failed")
sys.exit(1 if FAIL else 0)
