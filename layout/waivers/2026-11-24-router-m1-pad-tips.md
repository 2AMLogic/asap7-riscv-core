# Waiver: router via-pad tip spacings on M1 (`M1.S.2`, `M1.S.3`, `M1.S.4`, `M1.S.5`)

- **Deck**: `asap7.drc` of the pinned `klayout-tools==0.9.0`,
  `sha256:14f146f02cd731de3e0b59452eadfdab9c2c947724a219a1002a31b5e0f12d13`
  (267 categories; decision 0012). The waiver binds to this deck hash.
- **Report**: `flow/core/records/2026-11-24/drc.json` (status `violations`,
  20,540 markers total), on `layout/cve2_top.gds` sha256
  `abaf794b569e5956e5f4340e1ffc5ae5e6395b087ef7cf91f83591d3cec407e1`,
  the blob the `flow/core/records/2026-11-22/par.json` record pins.
- **Locations**: cell `cve2_rv32imc_wrapper` (flat check), every marker
  enumerated by bbox in the report's `violations[]` array:
  - `M1.S.2` — 583 tip-to-side markers (first: x 1439–1440 nm, y 57,285–57,303 nm);
  - `M1.S.3` — 77 tip-to-tip markers;
  - `M1.S.4` — 1,708 tip-to-tip markers (first: x 1448–1467 nm, y 45,763–45,774 nm);
  - `M1.S.5` — 373 tip-to-tip markers.
- **Violation text (verbatim from the report)**:
  - `M1.S.2`: "Table 3.12.1: min tip-to-side M1 spacing (one edge <= 36 nm, other > 36 nm) 25 nm"
  - `M1.S.3`: "Table 3.12.1: min tip-to-tip M1 spacing (both edges 24..36 nm) 27 nm"
  - `M1.S.4`: "Table 3.12.1: min tip-to-tip M1 spacing (both edges < 24 nm) 31 nm"
  - `M1.S.5`: "Table 3.12.1: min tip-to-tip M1 spacing (one edge 24..36 nm, other < 24 nm) 31 nm"
- **Cause (measured)**: tip-to-tip and tip-to-side markers on top-level
  router M1 at the protruding pad tips of router-inserted via stacks —
  the family the counter showed at 3 markers (1 `M1.S.4`, 2 `M1.S.5`,
  `flow/smoke/analysis/2026-11-21-drc.md`), scaled by the core's 24,342
  routed nets. The router's own DRC reports zero on the same GDS
  (`route_drc_violation_count: 0`). Upstream: #4508's repair PR #7142
  covers pad–**pad** pairs only (merged, unreleased); the pad–**wire**
  pairs were filed as klayout-tools **#7397**, closed completed
  2026-11-23 with its fix likewise merged to unreleased main (the
  [2026-11-23 recheck](../../flow/smoke/analysis/2026-11-23-upstream-disposition-recheck.md)
  measured the distinction on the counter).
- **Reason for acceptance**: router-emitted geometry, the fix is merged
  upstream, and no released klt can produce a clean core GDS at the
  ratified pins. Nothing is suppressed in the deck and the violations
  stay listed in the report summary.
- **Supersession**: the first `flow/core/records/<date>/drc.json` produced
  from a re-routed GDS at the bumped pin (#246, #277) retires this waiver;
  any pad–wire marker that survives the #7397 fix at that pin is a new
  finding to re-file upstream, not to re-waive on this record's authority.
- **Recorded by**: Loom Builder (issue #29), 2026-11-24.
