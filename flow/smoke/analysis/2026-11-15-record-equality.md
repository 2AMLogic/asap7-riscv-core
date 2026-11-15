# All-`ran` output-equality re-run: 2026-11-15 vs the 2026-11-05 reference

`flow/smoke/records/2026-11-15/` is a full six-step smoke-flow run with every
step at `run_state: "ran"`, produced as the outstanding acceptance artifact for
issue #91 (mkrecord.py interface narrowing in `flow/smoke/run.sh`, PR #134):
`smoke.klt_build` and `smoke.failed_attempts` are now *derived* inside
`mkrecord.py` rather than passed in, and this is the first run since that
refactor in which a completed synth feeds `par`/`sta`, so the whole-record
diff against a reference set exercises the derivation on the path that
matters, not only on a degraded `not_run` cascade. The run and this comparison
were tracked as issue #133.

**ASAP7 is a predictive PDK; nothing here is fabricated or measured.** Every
number below is a tool result against a predictive model and named, pinned
decks. No DRC verdict, LVS verdict or timing figure in either record set is a
result about the core, and nothing in this run changes any earlier record:
`flow/smoke/records/2026-11-05/` is read-only reference evidence, untouched.

## Run provenance

| What | Value |
|---|---|
| Flow code | `feature/issue-91` @ `d8087b0fa5e3bcba0b3f9125d5404c1f168b5b4c` — the final revision of PR #134 (open, CI-green at run time; `main` still carried the pre-refactor `run.sh`, so per the #133 Sequencing section the run uses the PR branch) |
| PDK checkout | The-OpenROAD-Project/asap7 @ `d24f8b857…`, `asap7sc7p5t_28` @ `f970bd3c3…`, `asap7_pdk_r1p7` @ `58d72c9d…` — the §1 pins of `spec/pdk-bringup.md`, all three verified with `check_pin` by `run.sh` |
| klt | pinned `klayout-tools==0.9.0` (`spec/core.md`), `klt_git_commit` `5dbbad05…` — identical in both record sets |
| `TMPDIR` | `/tmp` (4 characters) |
| `RECORD_DATE` | `2026-11-15` |
| Exit status | 0 |

Why `TMPDIR` matters: the dispatched agent step that produced the four earlier
`not_run` cascades inherited a 49-character `TMPDIR`, and the yosys→ABC
handoff hangs deterministically once the `$TMPDIR/yosys-abc-XXXXXX/input.blif`
path exceeds 64 characters (`2AMLogic/2am#7289`; klayout-tools friction
#5773/#5798/#5818/#5830). Exporting a short `TMPDIR` before `run.sh` reaches
klt is enough — klt 0.9.0's `_run_yosys` passes no `env=`, so yosys inherits
the caller's environment. No toolchain change, shim or pin bump was used.

## Pre-flight probe (the #133 gate)

With the run's `TMPDIR` exported, the 2-gate probe from 2am#7289 completes
instead of being `timeout`-killed:

| `TMPDIR` | length | probe | result |
|---|---|---|---|
| `/tmp` | 4 | `timeout 45 yosys -p 'read_verilog t.v; hierarchy -top t; proc; opt; techmap; opt; abc -g simple; stat'` on a 2-gate module | **exit 0, 0.12 s** |

The probe used the same yosys build the reference set names: `Yosys
0.67+post (git sha1 b8e7da6f40ae8f552c116bf6c359b07c6533e159)`.

## Result: the whole-record diff is byte-equal everywhere except provenance identity and one environment field

Both sets carry all six steps at `run_state: "ran"` with identical statuses
(`synth` ok, `par` ok, `drc` violations, `lvs` mismatch, `erc` not_checked,
`sta` ok). A recursive leaf-level diff of each record pair against
`flow/smoke/records/2026-11-05/` finds only the leaves listed below — every
other leaf in every record, including all result payloads (all 549 DRC
violations, all 76 LVS mismatches, the ERC verdict structure, the STA corner
results), is byte-identical.

**The headline criterion holds in its strongest form: the `smoke` section of
every record is byte-for-byte identical to the reference**, including the
derived `klt_build` triple (`role: "pinned"`, `version: "klt 0.9.0"`,
`ref: "klayout-tools==0.9.0"`); `failed_attempts` is absent from all six
records in both sets, as it must be when nothing failed. The routed layout
artifacts are hash-identical across the two runs:

| Artifact | sha256 |
|---|---|
| `layout/counter.gds` | `bb422342cf32e441cda83964b4b42210575f809988a84cf5838cde6794b5d75e` (both runs; equals each set's drc/lvs/erc `provenance.input.content_hash`) |
| `layout/counter.def` | `874a3ed6de12fa4336779fdcc9e309b9f9d378a7d2d00acaba5e6e20977e85fe` (both runs) |
| `layout/counter_asbuilt.v` | `a974cb961c3476e9143eee794a78c7e9aa2fc48211e4c1a4bcc31dfed6989128` (both runs) |

### Every differing field, with its reason

| Record | Field(s) | New | Reference | Category |
|---|---|---|---|---|
| synth | `run_id` | `run-ffe3ca64…` | `run-65311937…` | run identity |
| par | `engine_logs[0..3].invocation_id` | per-run uuids | per-run uuids | run identity |
| par | `engine_logs[0..3].script_sha256` | 4 shas | 4 shas | run identity: the sha covers the generated engine script, which embeds unredacted per-run scratch paths and invocation ids; every redacted field of each log (`directory`, `script_path`, `stdout_path`, `stderr_path`, `metadata_path`, `metrics_path`, `script_name`, `outcome`, `returncode`, `retention_errors`) is equal |
| sta | `corners[0..1].engine_log.invocation_id` and `.script_sha256` | per-run | per-run | run identity (as above) |
| drc, erc | `file.path` | `flow/smoke/records/2026-11-15/layout/counter.gds` | `…/2026-11-05/layout/counter.gds` | record-set identity: the path is inside the record set itself |
| lvs | `layout.path` | `…/2026-11-15/…` | `…/2026-11-05/…` | record-set identity (as above) |
| lvs | `reference` | `<repo>/flow/smoke/records/2026-11-15/layout/counter_asbuilt.v` | `<repo>/…/2026-11-05/…` | record-set identity (as above) |
| all six | `provenance.klayout_version` | `0.30.13` | `0.30.12` | **environment drift — the one finding; see below** |
| drc, lvs | `provenance.klayout_version_mismatch` | `true` | `false` | the same finding: klt flags that the engine no longer matches what the release expects |
| lvs | `environment.engine_version` | `0.30.13` | `0.30.12` | the same finding |

### The one finding: the KLayout engine floats under a fixed klt pin

`klayout-tools==0.9.0` pins the wrapper, not its KLayout dependency. Re-
resolving the identical pin today installs KLayout 0.30.13 where the
reference run got 0.30.12; `klt_version`, `klt_reinstall_spec` and
`klt_git_commit` are identical in both sets, so this is purely transitive
drift. Consequences observed here:

- `provenance.klayout_version` differs in all six records, and
  `klayout_version_mismatch` flips to `true` in drc and lvs — provenance
  records the drift honestly, which is the right behaviour, but it means
  whole-record byte-comparability across time cannot be expected under a
  released pin even when every input is pinned.
- Despite the engine change, every check result is unchanged here (the
  violation and mismatch lists are byte-identical, and the routed
  `counter.gds` is hash-identical), which is evidence that the drift did not
  alter this run's verdicts — one data point, not a guarantee.

Reported as a finding on PR #134 per the #133 acceptance criteria (a
difference not explained by run identity, timestamps or path scrubbing). The
underlying tool gap is already filed upstream as
`2AMLogic/klayout-tools#5601` ("A released klayout-tools pin does not
constrain the klayout engine…"); the GDS byte-stability angle is tracked as
#5682, and this run's hash-identical GDS across the engine change is a
supporting observation for it, filed here rather than re-filed upstream.

## tool-versions.txt

`tool-versions.txt` names the same yosys build as the reference set (the
#133 requirement) and differs from the reference by exactly one line: the
reference carries `klt_current: klt 0.8.0  (klayout-tools==0.8.0)
[comparison build, not the pin]`, a line `run.sh` no longer emits — the
0.8.0 comparison-build fallback was dropped by `eb062db` (`refactor(smoke):
drop the 0.8.0 comparison-build fallback from the smoke flow`) between the
2026-11-05 run and the #91 refactor, so its absence here is script
evolution, not run variation. Every other line, including all PDK input
hashes and the `counter.sv` hash, is identical.

## Reproduction

```bash
# from a checkout at d8087b0fa5e3bcba0b3f9125d5404c1f168b5b4c, with the
# spec/pdk-bringup.md §1 asap7 checkout at its pins (submodules initialised):
export TMPDIR=/tmp                       # 4 chars: keeps $TMPDIR/yosys-abc-XXXXXX/input.blif ≤ 64
RECORD_DATE=<new-label> flow/smoke/run.sh <asap7-checkout>
diff <(python3 -m json.tool flow/smoke/records/<new-label>/erc.json) \
     <(python3 -m json.tool flow/smoke/records/2026-11-05/erc.json)
```

`run.sh` refuses an existing `RECORD_DATE` (records are append-only) and
verifies the PDK pins, the pinned deck hashes and the absence of host paths
on every run.
