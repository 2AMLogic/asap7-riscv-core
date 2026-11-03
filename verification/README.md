# verification

PDK-free simulation harness: cocotb + Icarus Verilog, with a Verilator lint
step. It contains no ASAP7 files.

Two benches:

- **Default mode** (`verification/run.sh`): `smoke/counter.sv`, a trivial
  placeholder counter that proves the flow. It makes no claim about the core.
- **Core mode** (`verification/run.sh --core`): the pinned riscv-arch-test
  RV32 I, M and C programs on `rtl/cve2_rv32imc_wrapper.sv` (the unmodified,
  sv2v-converted CVE2 closure), see [Core mode](#core-mode).

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

## Core mode

```sh
verification/run.sh --core                    # exit 0 only if every program passes
verification/run.sh --core --negative-control # exit 0 only if the broken check fails
```

`core/setup.sh` first downloads the pinned inputs into `verification/build/`
(gitignored, every download sha256- or commit-checked): riscv-arch-test, the
Sail RISC-V golden model, the xPack RISC-V GCC, sv2v (the `spec/core.md` pin)
and the hash-locked CVE2 closure. Nothing is installed on the host; network is
needed on a cold start. Then `core/build_tests.py` compiles each program and runs
it on Sail to get the **expected signature** (the DUT never produces its own
reference), and `core/runner.py` converts the RTL, builds it with Icarus and runs
one cocotb test per program (`core/test_archtest.py`): reset, run until the program
stores to `tohost`, compare the signature region word for word.

The negative control flips one expected word of the first program; the run must
fail on exactly that.

What it claims: RTL simulation of the converted source (not the gate-level
netlist) matches Sail on the programs actually run, which are those listed in
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

## Pinned versions

| What | Pin | File |
|------|-----|------|
| Icarus Verilog | 13.0 | `tool-versions.txt` |
| Verilator | 5.050 | `tool-versions.txt` |
| Python | 3.12 | `tool-versions.txt` |
| cocotb | 2.0.1 | `requirements.txt` |
| riscv-arch-test, Sail, RISC-V GCC (core mode) | see file | `tool-versions.txt` |

The harness only checks host tool versions; it never installs or upgrades
them. Python packages go into the local venv only.
