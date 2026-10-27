# 0009 — T1 item 10 (repo hygiene) graded from a klt-generated attestation

**Status:** adopted 2026-10-27. Builds on decision 0008, which already pins the released `klt` at
`klayout-tools==0.8.0` in `spec/core.md`, `manifests/README.md` and `.github/workflows/signoff.yml`.

**Decision.** T1 item 10 is graded from `evidence/item10.json`, the envelope `klt signoff --attest 10` generates from
the inventory `attest/item10.json`, cited by `manifests/asap7-riscv-core.json`. The envelope is never hand-edited.

**Why.** `klt signoff --attest` and `--inventory` first ship in 0.8.0 (`klayout-tools` `docs/cli/signoff.md`,
"Attesting items 1, 9 and 10"). Item 10 is graded only from a tool-produced envelope; the tiers doc says a hand-rolled
envelope is not the tool-produced form.

**Effect on recorded results.** Against the record under decision 0008, `manifests/asap7-riscv-core.signoff.json`
changes only for item 10 (`unmet` to `met`, citing `evidence/item10.json`) and the counts that follow from it
(`t1_met_count`); item 6 stays `not_applicable` and no other item's verdict changes. The record is regenerated in the
same change.

**Not changed.**
- The unreleased-tree pin `git+https://github.com/2AMLogic/klayout-tools@7ee09483b748` for the metal DRC deck and
  FinFET LVS (decision 0005) is a separate pin and stays.
- `flow/smoke/records/2026-10-23/` and `spec/pdk-bringup.md` are append-only evidence produced with 0.7.0 and the
  pinned dev build; they are not re-run.

**Rejected:** a hand-written item 10 envelope.
