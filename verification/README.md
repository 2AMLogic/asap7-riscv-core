# verification

PDK-free simulation harness: cocotb + Icarus Verilog, with a Verilator lint
step. It contains no ASAP7 files.

Two benches, plus a lockstep lane:

- **Default mode** (`verification/run.sh`): `smoke/counter.sv`, a trivial
  placeholder counter that proves the flow. It makes no claim about the core.
- **Core mode** (`verification/run.sh --core`): the pinned riscv-arch-test
  RV32 I, M and C programs on `rtl/cve2_rv32imc_wrapper.sv` (the unmodified,
  sv2v-converted CVE2 closure), see [Core mode](#core-mode).
- **Lockstep mode** (`verification/lockstep.sh`): the same corpus plus a
  longer program with every RVFI retirement compared against the pinned
  Spike reference while the simulation runs, see
  [Lockstep mode](#lockstep-mode-rvfi-vs-spike-per-retirement).

## Cold-start invocation

From a fresh clone, with the host tools below installed:

```sh
verification/run.sh
```

It works from any working directory. It:

1. checks the installed `iverilog`, `verilator` and `python3` against
   `tool-versions.txt` and exits non-zero with a clear message on a mismatch
   (the Verilator checks are smoke-only — see [Core mode](#core-mode));
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

Runs the same flow with a deliberately wrong expected count
(`SMOKE_NEGATIVE_CONTROL=1`). One verdict rule, `negative_control_verdict` in
`lib.sh` (self-tested by `lib_test.sh`), decides the exit: the command exits 0
only when the runner's tests-failed exit is backed by JUnit evidence that the
intended comparison ran and detected the injected mismatch. A startup, build or
report-writing failure with no usable report, a failure that is not the
injected mismatch, or an unexpected pass each exit non-zero. The failed
testcase stays visible in `results.xml`.

## Core mode

```sh
verification/run.sh --core                    # exit 0 only if every program passes
verification/run.sh --core --negative-control # exit 0 only if the flipped word is detected
```

Prerequisites are mode-specific: `iverilog` and `python3` are checked at
startup for every mode, but Verilator is checked only on the smoke path —
the lint step it backs is smoke-only, and both core modes (RTL and
gate-level) simulate with Icarus alone. A host without Verilator runs
`--core` and `--core --gate`; only the default smoke mode refuses to start
without the pinned Verilator 5.050.

`core/setup.sh` first downloads the pinned inputs into `verification/build/`
(gitignored, every download sha256- or commit-checked): riscv-arch-test, the
Sail RISC-V golden model, the xPack RISC-V GCC, sv2v (the `spec/core.md` pin)
and the hash-locked CVE2 closure. Nothing is installed on the host; network is
needed on a cold start. Then `core/build_tests.py` compiles each program and runs
it on Sail to get the **expected signature** (the DUT never produces its own
reference), and `core/runner.py` (helpers shared with `core/fv.py` in `core/archtest_common.py`) converts the RTL, builds it with Icarus and runs
one cocotb test per program (`core/test_archtest.py`): reset, run until the program
stores to `tohost`, compare the signature region word for word.

The Spike reference lane (`core/spike_setup.sh`, `core/spike_trace.py`, self-test
`core/test_spike_trace.py`) generates a per-instruction retirement trace of the core
test ELFs from the pinned Spike. It is deliberately **not** part of `setup.sh` or
`run.sh`: it needs the `dtc` and Boost prerequisites that the rest of the harness
does not, and nothing attested depends on it. Run `spike_setup.sh` once, then
`python3 -I verification/core/spike_trace.py`. `spike_trace.py` accepts only the
mtvec shape CVE2 can represent when traces are compared (see its docstring).

## Lockstep mode (RVFI vs Spike, per retirement)

```sh
verification/lockstep.sh                    # exit 0 only if every program matches
verification/lockstep.sh --negative-control # exit 0 only if the corrupted write-back
                                            # fails the comparison at the exact
                                            # retirement, pc, destination and value
```

Runs the same 72-program corpus as core mode plus the deterministic longer
program `core/lockstep_prog.S` (921 retirements: 16- and 32-bit instructions,
multi-cycle mul/div idle cycles, x0 writes, repeated PCs in a 64-iteration
loop, sub-word loads/stores, mtvec/mscratch write + read-back, an `ebreak`
synchronous trap delivered to the handler with `mcause`/`mepc` read-back and
`mret`, and the retiring store to `tohost`), comparing **every RVFI
retirement against the pinned Spike reference while the simulation runs**
(issue #206, part of #204). The closure is converted through
`flow/core/sv2v.sh convert ... -DRVFI` — the same entry point as the attested
netlist, with one extra define — which exposes the core's RVFI retirement
port and CVE2's own verification-only CSR write observation
(`rvfi_<name>_csr_wmask/_wdata` in `cve2_cs_registers.sv`) without adding a
port to the wrapper or the testbench.

Per retirement the comparator (`core/lockstep_compare.py`, offline self-test
`core/test_lockstep_compare.py`) checks order continuity, PC, instruction
bits masked to the reference length, privilege mode, integer destination
index and write-back value, load presence and address; for stores the write
mask pinned by the decoded instruction (unshifted `0x1`/`0x3`/`0xf` for
`sb`/`sh`/`word` — `sw`, `c.sw`, `c.swsp`; `cve2_core.sv` decodes it from
`lsu_type` with no lane shift), the single address, and the low 8, 16 or 32
bits of the raw store value at that decoded width; and every reference CSR
write against the observed committed value
projected through CVE2's WARL (mtvec/mepc/mcause bit masking, mstatus
implemented fields, mret keeping MPP at M because CVE2 has no U-mode). A
reference record carrying more than one store effect for one decoded store
is reported as an unsupported record — naming the retirement PC and the
effect count, expected and observed masks on a mask divergence — rather
than being partially compared. A
synchronous exception is a retirement gap in the reference and an
`rvfi_trap` retirement on the DUT. The run passes when both sides consume
the retiring `tohost` store. A divergent or extra retirement reports the
ELF, ordinal, PC, disassembly and, for a value mismatch, the expected and
observed values. If the DUT stops retiring, the cycle limit still expires.
The timeout names the ELF and next retirement ordinal, marks the PC as
unavailable, and reports the elapsed cycles, retirements compared and
reference records left. Disassembly requires a retiring instruction.

The negative control flips one bit of retirement 1's write-back and reports
this mismatch.

```text
lockstep-prog: retirement 1 at pc 0x80000080 (li s0,5): rd_wdata: write-back value for x8 [expected 0x5 (5), dut 0x4 (4)] [destination x8]
```

The negative control runs the longer program clean (must pass, 921
retirements) and then with one bit of that write-back flipped **in the
observation path only** — the DUT is untouched — and requires the failure
above, so an unrelated failure cannot satisfy it.

This lane is deliberately a separate job, not part of `verification/run.sh`,
its item 9 attestation, or CI (#204 allows documenting it as one): it needs
the pinned Spike (a C++ build via `core/spike_setup.sh`, with dtc and Boost
prerequisites) on top of the core-mode inputs. Measured on the sweep host
(8 vCPU, spike prebuilt): full corpus 73 programs in ~100 s of simulation
(plus ~30 s sv2v conversion + Icarus build), negative control ~15 s;
`spike_setup.sh` is a one-time ~10 min build. Committed records:
`records/2026-11-20/lockstep-core-archtest.json` (73 programs, 0 failed)
and `records/2026-11-20/lockstep-core-archtest-negative-control.json`.

What it claims: RTL simulation of the `-DRVFI` conversion of the pinned
closure retires exactly the instruction stream the pinned Spike retires for
the same ELFs, event for event, on the programs actually run (the corpus
list above plus `lockstep_prog.S`). ASAP7 is a predictive PDK; nothing here
is fabricated or measured.


The negative control flips one expected word of the first program; the run
must fail on exactly that — the same `negative_control_verdict` rule as the
smoke control, so only a detected one-word signature mismatch exits 0.
Because the control runs that one program only, its build stops at the first
program in suite order (`I-add-01`): `build_tests.py --first-only` compiles
one ELF and runs Sail once, into `<run dir>/tests/`. If that path resolves to
the shared `verification/build/tests/` (for example, when `fv.sh` is given
`verification/build` as its output directory), the control uses a fresh
`control-tests-*` directory inside the run directory to preserve the full
suite's manifest. The gate-level and `fv.sh` controls share
this path (`core/archtest_common.py`; self-test:
`core/build_tests_test.sh`).

What it claims: RTL simulation of the converted source (not the gate-level
netlist; see "Gate-level mode" below) matches Sail on the programs actually run, which are those listed in
`results.xml` (72 as of this writing). The target-specific glue is
`core/model_test.h` and `core/link.ld` (program at `0x80000080` because CVE2
boots at `boot_addr_i`; RAM at `0x80000000`).

**Not run, with reasons, in `core/excluded.json`:**

- `C-cebreak-01`: the suite's trap prolog needs a fully writable `mtvec`; CVE2
  forces `mtvec` MODE=01 and a 256-byte-aligned base, so the prolog copies its
  trampoline one byte off and `c.ebreak` lands in a fetch loop. Diagnosed with a
  measurement in
  [decision 0011](../spec/decisions/0011-c-cebreak-01-mtvec-not-writable.md);
  not bench glue, and the exclusion stays.

`I-jalr-01` is no longer excluded: the pinned GCC's assembler rejects the
upstream `la x0,<label>`, so `build_tests.py` assembles that one program with
the pinned LLVM clang (`llvm_release` in `tool-versions.txt`) and links it with
the pinned GNU `ld`. The upstream source is unmodified.

Sail's default RV32 configuration is richer than RV32IMC; the programs only
exercise I/M/C instructions, but the golden model is not configured down to
RV32IMC.

`attest/item9.json` is the T1 item 9 inventory (`evidence/item9.json`). It lists
`flow/smoke/run.sh` only as the ASAP7 smoke-flow driver: it runs the placeholder
counter, backs no core claim, and its cold start (needs an ASAP7 checkout) is
not run by the attestation. Re-attest after editing any listed file:

```sh
uvx --python 3.12 --from "klayout-tools==0.8.0" klt signoff --attest 9 \
    --inventory attest/item9.json -o evidence/item9.json
```

## Gate-level mode (`--core --gate`)

```sh
verification/run.sh --core --gate                    # exit 0 only if every program passes
verification/run.sh --core --gate --negative-control # flipped word; exit 0 only if the flip is detected
```

Same programs, Sail signatures, `tb_core.v`, `test_archtest.py` and
`core/excluded.json` as core mode, but the DUT is the committed synthesized
netlist `flow/core/records/2026-11-14/netlist.v` plus the ASAP7 7.5-track RVT
functional cell Verilog (AO, OA, INVBUF, SIMPLE, SEQ groups) from
`asap7sc7p5t_28` at the commit pinned in `spec/pdk-bringup.md`
(`asap7_cells_*` in `tool-versions.txt`). `core/setup.sh` fetches the five files
into `verification/build/asap7-cells/` and aborts on a sha256 mismatch; the
vendor files are used unmodified. The runner writes `record.json` (program
count, failures, tool versions, netlist and model hashes) into the run dir.

Icarus is invoked with `-gno-specify`, so the models' timing arcs and
`$setuphold` checks are ignored (that is what makes it zero-delay). Icarus 13
still prints three `sorry: ifnone with an edge-sensitive path is not supported`
notices for `asap7sc7p5t_SEQ_RVT_TT_220101.v`, all inside `specify` blocks; the
models elaborate and simulate.

What it claims: the synthesized gate netlist, simulated with zero-delay
functional cell models, matches Sail on the programs actually run, before
place-and-route.

What it does **not** claim: anything about timing, SDF back-annotation,
setup/hold, the post-route netlist, or power. It is pre-layout, functional only,
and is not cited by `manifests/asap7-riscv-core.json`. It takes about 80 s per
program (about 1.5 h for the full set).

Committed records (separate from the RTL records):
`records/2026-11-06/gate-core-archtest.json` and
`records/2026-11-06/gate-core-archtest-negative-control.json`.

Result (2026-11-06): 72 programs run, 0 failed, `C-cebreak-01` excluded as in the
RTL record; every program matches Sail. The negative control fails as intended:
`I-add-01` reports 1 of 588 signature words differing (word 294,
dut=`33333336`, expected-after-flip=`33333337`), and the run exits as an
expected failure.

Committed records for the superseding netlist (decision 0017, the DUT re-pointed
to the tie-cell netlist `flow/core/records/2026-11-14/netlist.v`):
`records/2026-11-15/gate-core-archtest.json` and
`records/2026-11-15/gate-core-archtest-negative-control.json`.

Result (2026-11-15): 72 programs run, 0 failed against the 2026-11-14 netlist
(sha256 `e559a5923d6be0a79645ad32bb7c64e82b5c54c3bcf144bb769a7827e5ee22ad`,
recorded by the runner from the `NETLIST` path itself), `C-cebreak-01` excluded
as before; every program matches Sail, so the tie cells
(`TIEHIx1`/`TIELOx1`, from the `SIMPLE` group) change no observable behaviour.
The negative control again fails on `I-add-01` as intended and exits as an
expected failure. `records/2026-11-06/` stays untouched as the append-only
evidence for the 2026-11-03 netlist.

## klt functional-verification report (core, RTL)

```sh
verification/fv.sh [OUT_DIR]                     # exit 0 only if every program passes
verification/fv.sh --negative-control [OUT_DIR]  # flipped signature word; exit 0 only if the
                                                 # report evidences that one-word mismatch
```

Runs the same suite as core mode (same `setup.sh`, `build_tests.py`, sv2v conversion,
`tb_core.v` and `test_archtest.py`) through `klt functional-verification` from the pinned
`klayout-tools` release (`klayout_tools` in `tool-versions.txt`, fetched by `uvx`, with the
pinned cocotb). One klt request per program is written to `OUT_DIR/requests/`; the program
image and tohost address reach `tb_core.v` as `-D` macros because a klt request has no
plusargs. `OUT_DIR/report.json` collects the per-program klt responses, with
host paths replaced by `<scratch>`/`<repo>` tags; after the run a leak-guard
scan (`leak_guard` in `lib.sh`, self-tested by `lib_test.sh`) fails the script
if report.json still names a host path.

Committed run: `records/2026-11-05/klt-fv-core-archtest.json` (72 programs, 0 failed;
`C-cebreak-01` excluded per `core/excluded.json`) and
`records/2026-11-05/klt-fv-core-archtest-negative-control.json` (1 program, signature
mismatch reported). This is RTL evidence only and is **not** cited for T1 item 5 on its own:
item 5 stays `unmet` until the multi-corner `klt sta` half lands (#32).

## Pinned versions

| What | Pin | File |
|------|-----|------|
| Icarus Verilog | 13.0 | `tool-versions.txt` |
| Verilator (smoke lint only) | 5.050 | `tool-versions.txt` |
| Python | 3.12 | `tool-versions.txt` |
| cocotb | 2.0.1 | `requirements.txt` |
| klayout-tools (`fv.sh`) | 0.8.0 | `tool-versions.txt` |
| riscv-arch-test, Sail, RISC-V GCC (core mode) | see file | `tool-versions.txt` |

The harness only checks host tool versions; it never installs or upgrades
them. Python packages go into the local venv only.
