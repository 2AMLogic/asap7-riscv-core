# 0014 — A `--check` gate for T1 item 9; `verification/lib.sh` attested; item 9 re-attested

**Status:** adopted 2026-11-14. Supersedes the item-9 envelope produced under
`spec/decisions/0012-shared-archtest-module-and-item9-reattestation.md` (not that record's decision, only its
envelope), under the same append-only rule it implements for operator ruling r7-q12 (issue #65): results and
attestations are never deleted or rewritten; inputs and generators may change with a superseding record. Closes
issue #88.

**Problem.** `evidence/item9.json` asserted `status: pass`, "14/14 attestation checks passed", over per-file
`content_hash` rows that no longer described the tree. Five of eleven were stale on `main` at `f84e5c3`:
`flow/smoke/run.sh`, `verification/core/archtest_common.py`, `verification/core/runner.py`,
`verification/core/setup.sh`, `verification/run.sh`. The envelope's own `provenance.input.content_hash` for
`attest/item9.json` was still fresh, so the inventory was current and only the attested bodies had drifted.

Nothing could see it. `.github/workflows/signoff.yml` ran exactly two checks: a byte-compare of a fresh tier render
against `manifests/asap7-riscv-core.signoff.json`, and `--attest 10 … --check`. The tier record's item-9 citation
carries only the *inventory* hash and the check counts — never the per-testbench hashes — so the byte-compare is
structurally blind to this drift, and item 9 had no `--check` step of its own. Three merged PRs edited attested
files with CI green, including one a descendant of the commit that had just re-attested the envelope.

**Decision.**

1. **`.github/workflows/signoff.yml` gains a "Re-check the item 9 attestation envelope" step**, mirroring the
   item-10 step in form: `klt signoff --attest 9 --inventory attest/item9.json --check evidence/item9.json`, with
   exit 0 fresh, exit 3 drift, anything else a hard error distinguished from drift. `--check` skips the inventory's
   `local_only` cold start on its own and lists it `[SKIP]`, exactly as the item-10 step skips its `local_only`
   harness commands, so the gate needs no simulator and no new `klt` capability. From now on an edit to an attested
   testbench reds the pull request instead of silently staling the evidence.

2. **The step's comment states the retention requirement.** Re-attesting item 9 is a two-step change and both steps
   belong in the same commit: copy the committed `evidence/item9.json` to
   `evidence/records/item9-<the date that envelope was produced>.json` *first*, then regenerate. The existing
   item-10 comment omits the retention step; correcting that wording is issue #89's subject and is deliberately not
   touched here.

3. **`verification/lib.sh` joins `attest/item9.json`'s `testbenches`.** `verification/run.sh:25` and
   `verification/core/setup.sh:18` both source it and cannot run without it; `verification/fv.sh:16` sources it too.
   The inventory description says plainly that it is listed because the harness does not execute without it, not
   because it is itself a bench. The inventory edit lands in the same commit as the regeneration: measured in a
   throwaway worktree, adding the path without re-attesting renders item 9 `status: unmet, reason: stale_evidence`
   with a null citation and drops `t1_met_count`.

**Attestation.** The prior envelope (14/14 checks, input hash `sha256:9fa1f662…`, produced at commit `40a3319`,
2026-11-06T05:48:50Z) is retained byte-for-byte at `evidence/records/item9-2026-11-06.json` — named for the date it
was produced, matching the `evidence/records/item9-2026-11-05.json` convention. The new envelope is
`evidence/item9.json` (15/15 checks, input hash `sha256:6b1dbf95…`), cited by `manifests/asap7-riscv-core.json`.
`manifests/asap7-riscv-core.json`'s pinned citation hash for item 9 moved to the new inventory hash — the block
manifest binds each citation to its *input*, so an inventory edit without that update renders item 9 `unmet,
stale_evidence` even after a successful re-attest — and `manifests/asap7-riscv-core.signoff.json` was regenerated
from both; item 9 still renders `met`, with a non-null citation, `check_count` 15, and `t1_met_count` unchanged at
3 of 11. `evidence/item10.json` was re-attested in the same commit because
`.github/workflows/signoff.yml` is one of item 10's attested hygiene files. Nothing was deleted or rewritten.

**Regeneration.** Both envelopes are tool-produced and never hand-edited, pinned to the `klt` version the workflow
installs:

```
uvx --python 3.12 --from "klayout-tools==0.8.0" klt signoff --attest 9 --inventory attest/item9.json -o evidence/item9.json
uvx --python 3.12 --from "klayout-tools==0.8.0" klt signoff --attest 10 --inventory attest/item10.json -o evidence/item10.json
```

re-checked with `… --check …` (item 9 `status: match`, exit 0; item 10 likewise). `--skip-local-only` exists in no
released `klt` (absent in 0.8.0, 0.9.0 and 0.9.1; 0.9.2 is not on the index) and is refused with `--check` anyway,
so refreshing the item-9 envelope requires the cold start to actually run. The `klt` pin is not bumped here.

**Verification.** The live cold start that produced the envelope — `verification/run.sh --core`, driven by
`klt signoff --attest 9` on a host with `iverilog` 13.0, `verilator` 5.050, `python` 3.12.3 and network egress:
**72 of 72 riscv-arch-test I/M/C programs pass, 0 failures, 0 skipped, exit 0** (`verification/runs/…/results.xml`;
`C-cebreak-01` is excluded with its diagnosed reason in `verification/core/excluded.json` and decision 0011, so 72
is the full set). Negative control for the new gate: reverting `verification/core/runner.py` to its `40a3319`
content makes the step exit 3 and name `attestation.checks.<index>` for that row; restoring it returns `status:
match`, exit 0. RTL simulation of the converted CVE2 closure against a predictive PDK; ASAP7 is never fabricated
and nothing here is measured.

**Not decided here.** The item-10 `--check` step, its comment's re-attest recipe and the general append-only
reading (issue #89); the duplicate decision number `0012` (issue #90); a `klt` pin bump or a release carrying
`--skip-local-only`; a `--check` gate for any other T1 item; any change to the harness or the arch-test set.
