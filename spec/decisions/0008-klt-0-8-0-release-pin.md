# 0008 — Bump the released klt pin from 0.7.0 to 0.8.0

**Status:** adopted 2026-10-27. Amends the released-`klt` pin in `spec/core.md` ("PDK and tools (pinned)").

**Decision.** The pinned released `klt` is `klayout-tools==0.8.0` (PyPI), up from 0.7.0. The pin appears in
`spec/core.md`, `manifests/README.md` and `.github/workflows/signoff.yml`, and all three now agree.

**Why.** `klt signoff --attest` and `--inventory` first ship in 0.8.0 (`klayout-tools` `docs/cli/signoff.md`,
"Attesting items 1, 9 and 10"); 0.7.0 rejects them as unrecognized arguments. T1 item 10 (repo hygiene) is graded
only from a tool-produced `--attest 10` envelope, so the pin cannot stay at 0.7.0.

**Effect on recorded results.** Re-rendering `klt signoff` under 0.8.0 changes
`manifests/asap7-riscv-core.signoff.json` only in the `build` block, the `grading_ruleset_id`, and item 10
(`unmet` to `met`, citing `evidence/item10.json`); no other item's verdict changes. The record is regenerated in the
same change.

**Not changed.**
- The unreleased-tree pin `git+https://github.com/2AMLogic/klayout-tools@7ee09483b748` for the metal DRC deck and
  FinFET LVS (decision 0005) is a separate pin and stays.
- `flow/smoke/records/2026-10-23/` and `spec/pdk-bringup.md` are append-only evidence produced with 0.7.0 and the
  pinned dev build; they are not re-run, and their text keeps saying 0.7.0. The "released 0.7.0 deck" figures in
  `spec/core.md` describe those records and have not been re-measured against the 0.8.0 deck.

**Rejected:** staying on 0.7.0 with a hand-written item 10 envelope (the tiers doc says a hand-rolled envelope is not
the tool-produced form).
