# 0008 — T1 item 6 recorded "not applicable"; signoff grader pin 0.8.0

**Status:** accepted 2026-10-27.

**Decision.**

- T1 item 6 is discharged by a recorded "not applicable": the ratified spec has no accuracy, offset,
  matching or yield row. [`spec/statistical-rows.json`](../statistical-rows.json) accounts for all
  five target-table rows (core, standard-cells, predicted-clock, drc, lvs) with the reason each is not
  statistical. Both it and [`spec/core.rows.json`](../core.rows.json) are cited in
  `manifests/asap7-riscv-core.json` by content hash. Adding a statistical row to `spec/core.md`
  voids the statement.
- `spec/core.rows.json` is a machine-readable listing of the `spec/core.md` target table
  (`sha256:c070a2993904ea475a11ed47ee14d10e12cb91372f7e9f007a0a332863d4c81d` at adoption). The grader reads JSON, so the markdown spec cannot be cited directly.
  `spec/core.md` is unchanged and stays authoritative; the listing adds and relaxes no row.
- The `klt signoff` pin moves from `klayout-tools==0.7.0` to `klayout-tools==0.8.0`
  (`manifests/README.md`, `.github/workflows/signoff.yml`). 0.7.0 has no `not_applicable` outcome;
  0.8.0 grades it (klayout-tools#2865).

**DRC/LVS pin unaffected.** The decision 0005 pin (`git+...klayout-tools@7ee09483b748`) is for
`klt drc` and `klt lvs` only and is not changed. Whether that commit carries #2865 was not checked
and does not matter: `klt signoff` is run from 0.8.0. The `0.7.0` mentions in `spec/core.md` and
`spec/pdk-bringup.md` describe the released `klt` used for DRC/LVS bring-up and are left as recorded.

**Evidence.** With 0.8.0 the regenerated record shows item 6 `not_applicable` (not `met`;
`t1_met_count` stays 0, `t1_not_applicable_count` 1). Negative control: appending one byte to the
statement turns item 6 into `unmet` / `stale_evidence`.

**Rejected:** putting the statement inside `spec/core.md` (editing the spec would change both bound
files and blur the audit trail).
