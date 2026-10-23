# verification

PDK-free simulation harness: cocotb + Icarus Verilog, with a Verilator lint
step. It contains no ASAP7 files, no core RTL, and makes no claim about any
design.

**Status: placeholder.** The only DUT is `smoke/counter.sv`, a trivial counter
that exists to prove the flow. `smoke/` is deleted or replaced when the core is
pinned (see #3); nothing here says anything about the core.

## Cold-start invocation

From a fresh clone, with the host tools below installed:

```sh
verification/run.sh
```

It works from any working directory. It:

1. checks the installed `iverilog`, `verilator` and `python3` against
   `tool-versions.txt` and exits non-zero with a clear message on a mismatch;
2. creates `verification/.venv` and installs `requirements.txt` (exact pins);
3. runs `verilator --lint-only -Wall` over `smoke/counter.sv`;
4. builds with Icarus and runs the cocotb test (`smoke/runner.py`);
5. writes JUnit-style XML to `verification/runs/<UTC timestamp>-<pid>/results.xml`.

It exits 0 only if lint and every test pass. `.venv/` and `runs/` are
gitignored.

## Negative control

```sh
verification/run.sh --negative-control
```

Runs the same flow with a deliberately failing assertion
(`SMOKE_NEGATIVE_CONTROL=1`) and exits 0 only if the test *fails*; it exits
non-zero if the broken assertion unexpectedly passes.

## Pinned versions

| What | Pin | File |
|------|-----|------|
| Icarus Verilog | 13.0 | `tool-versions.txt` |
| Verilator | 5.050 | `tool-versions.txt` |
| Python | 3.12 | `tool-versions.txt` |
| cocotb | 2.0.1 | `requirements.txt` |

The harness only checks host tool versions; it never installs or upgrades
them. Python packages go into the local venv only.
