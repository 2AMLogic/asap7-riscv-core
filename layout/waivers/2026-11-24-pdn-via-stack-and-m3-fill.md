# Waiver: PDN M2–M5 via stack enclosure (`V4.M4.EN.1`, `V4.M5.EN.2`) and router M3 fill (`M3.S.2`)

- **Deck**: `asap7.drc` of the pinned `klayout-tools==0.9.0`,
  `sha256:14f146f02cd731de3e0b59452eadfdab9c2c947724a219a1002a31b5e0f12d13`
  (267 categories; decision 0012). The waiver binds to this deck hash.
- **Report**: `flow/core/records/2026-11-24/drc.json` (status `violations`,
  20,540 markers total), on `layout/cve2_top.gds` sha256
  `abaf794b569e5956e5f4340e1ffc5ae5e6395b087ef7cf91f83591d3cec407e1`,
  the blob the `flow/core/records/2026-11-22/par.json` record pins.
- **Locations**: cell `cve2_rv32imc_wrapper` (the deck checks flat; every
  marker carries the top cell), every marker enumerated by bbox in the
  report's `violations[]` array:
  - `V4.M4.EN.1` — 14,384 markers, every bbox exactly 216 nm × 24 nm
    (first: x 1392–1608 nm, y 1056–1080 nm);
  - `V4.M5.EN.2` — 232 markers, every bbox exactly 216 nm × 24 nm;
  - `M3.S.2` — 870 markers, every bbox exactly 18 nm × 34 nm
    (first: x 1485–1503 nm, y 7003–7037 nm).
- **Violation text (verbatim from the report)**:
  - `V4.M4.EN.1`: "Table 3.15.1: min enclosure of V4 by M4 on two opposite sides 11 nm"
  - `V4.M5.EN.2`: "Table 3.15.1: min enclosure of V4 by M5 on at least two opposite sides 11 nm"
  - `M3.S.2`: "Table 3.12.1: min tip-to-side M3 spacing (one edge <= 36 nm, other > 36 nm) 25 nm"
- **Cause (measured)**: the `V4.*` markers are the M4 landing segments of
  the PDN M2→M5/M5→M6 connect stack — rectangles exactly one M5 strap
  width (216 nm) by one minimum M4 wire height (24 nm), so a 24 nm wire
  cannot enclose a 216 nm cut row by 11 nm on two opposite sides; no
  `power.*` request field reaches this geometry (the explicit-strap recipe
  of PR #234 is already on the deck's grids). The `M3.S.2` markers are the
  router's own M3 fill-patch spacing. Both are documented upstream
  residuals of the pinned build: klayout-tools #6909 and its fixing PR
  **#7084** ("repair the ASAP7 pdngen M2-M5 power stack after the DEF-GDS
  merge (V4.M4.EN.1 / V4.M5.EN.2 / M3.S.2 to zero)", merged 2026-11-23,
  **unreleased** — the newest tag v0.9.2 predates it). The same family was
  measured at 35 + 7 + 0 markers on the counter
  (`flow/smoke/analysis/2026-11-21-drc.md`).
- **Reason for acceptance**: the geometry is emitted by the pinned tool's
  PDN construction and router fill, the fix is merged upstream, and no
  released klt can produce a clean core GDS from the committed netlist at
  the ratified pins. Nothing is suppressed in the deck and the violations
  stay listed in the report summary.
- **Supersession**: the first `flow/core/records/<date>/drc.json` produced
  from a re-routed GDS at the bumped pin (#246, #277) retires this waiver;
  the retiring PR deletes or marks this file superseded and quotes the new
  per-rule counts.
- **Recorded by**: Loom Builder (issue #29), 2026-11-24.
