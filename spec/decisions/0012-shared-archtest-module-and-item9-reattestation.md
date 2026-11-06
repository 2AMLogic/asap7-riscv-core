# 0012 — One shared module for the two arch-test drivers; T1 item 9 re-attested

**Status:** adopted 2026-11-06. Implements operator ruling r7-q12 (issue #65), extending the append-only rule: results
and attestations are never deleted or rewritten; inputs and generators may change with a superseding record.

**Decision.** `verification/core/archtest_common.py` holds the `paths()`, `convert()` and build-tests/test-list setup
that `runner.py` (`run.sh --core`) and `fv.py` (`fv.sh`) each carried. Both entry points stay and keep their documented
behaviour. The undocumented `ARCHTEST_ONLY`, `ARCHTEST_TRACE` and `ARCHTEST_TRACE_N` debug hooks are dropped.

**Attestation.** `attest/item9.json` now lists `archtest_common.py` and the changed `runner.py` / `test_archtest.py`
hashes. The prior envelope (13 checks, input hash `sha256:306dffb5…`, commit `97260b9`) is retained unchanged at
`evidence/records/item9-2026-11-05.json`; the new envelope is `evidence/item9.json` (14/14 checks, input hash
`sha256:9fa1f662…`), cited by `manifests/asap7-riscv-core.json`. The signoff record was regenerated from it.

**Citations.** `flow/core/sv2v.sh` and `flow/core/synth.sh` comments now name `archtest_common.py` as the conversion
caller. Decision 0011 cites `verification/run.sh --core`, which still exists, so it is unchanged.

**Regeneration.** The envelope is tool-produced, never hand-edited:
`uvx --python 3.12 --from klayout-tools==0.8.0 klt signoff --attest 9 --inventory attest/item9.json -o evidence/item9.json`,
re-checked with `… --check evidence/item9.json` (status `match`). No result or report file and no regenerable input
was removed, so no byte-for-byte regeneration of a deleted input applies.

**Verification.** `run.sh --core`: 72 programs pass; `run.sh --core --negative-control`: fails as expected;
`fv.sh`: 72 tests, 0 failed; `fv.sh --negative-control`: fails as expected. RTL simulation against a predictive PDK
flow; nothing here is fabricated or measured.
