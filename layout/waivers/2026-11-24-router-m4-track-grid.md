# Waiver: router-emitted M4 off the deck's track grid (`M4.AUX.1`, `M4.AUX.2`, `M4.W.3`)

- **Deck**: `asap7.drc` of the pinned `klayout-tools==0.9.0`,
  `sha256:14f146f02cd731de3e0b59452eadfdab9c2c947724a219a1002a31b5e0f12d13`
  (267 categories; decision 0012). The waiver binds to this deck hash.
- **Report**: `flow/core/records/2026-11-24/drc.json` (status `violations`,
  20,540 markers total), on `layout/cve2_top.gds` sha256
  `abaf794b569e5956e5f4340e1ffc5ae5e6395b087ef7cf91f83591d3cec407e1`,
  the blob the `flow/core/records/2026-11-22/par.json` record pins.
- **Locations**: cell `cve2_rv32imc_wrapper` (flat check), every marker
  enumerated by bbox in the report's `violations[]` array:
  - `M4.AUX.1` — 4 degenerate point markers, two x columns
    (x = 12,719 nm and 12,803 nm) on y = 53,988 nm and 54,012 nm;
  - `M4.AUX.2` — 8 degenerate point markers, the same two x columns on
    y = 53,988 / 54,036 nm, plus x = 36,229 / 36,313 nm on y = 57,768 and
    57,816 nm;
  - `M4.W.3` — 8 markers, all on one router M4 escape column 84 nm wide
    by 0.89 µm tall (x 36,229–36,313 nm, y 57,312–58,200 nm), merged with
    via landing pads and notched 5 nm on its right edge.
- **Violation text (verbatim from the report)**:
  - `M4.AUX.1`: "Table 3.14.2: M4 horizontal edges must be on a 24 nm grid (offset 0)"
  - `M4.AUX.2`: "Table 3.14.2: minimum-width M4 must lie on a routing track (2N x 24 nm, offset 0)"
  - `M4.W.3`: "Table 3.14.1: vertical M4 width may not be an even integer multiple of 24 nm"
- **Cause (measured)**: the 12 `M4.AUX.*` points are vertices of
  router-emitted minimum-width (24 nm) M4 routing rectangles whose
  horizontal edges sit at y ≡ 12 (mod 24) — half the grid pitch off every
  track centre the request declares (`floorplan.tracks[]` M4 offset
  0.012 µm, pitch 0.048 µm puts on-grid wire edges at ≡ 0 mod 24); the
  8 `M4.W.3` markers are the width rule's edge pairing on the one 84 nm
  (3.5 × 24 nm) escape column above. Every other M4 in the flow is
  on-grid — these 20 are the only off-grid router emissions in the
  record — no request field reaches them, and the router's own DRC
  reports zero on the same GDS. Not previously tracked upstream: filed
  generically as klayout-tools **#7817** (friction protocol).
- **Reason for acceptance**: router-emitted geometry at the pinned build
  with no request-side control; the gap is filed upstream and rides the
  same pin-bump window (#246) as the other router-emission families.
  Nothing is suppressed in the deck and the violations stay listed in the
  report summary.
- **Supersession**: the first `flow/core/records/<date>/drc.json` produced
  from a re-routed GDS at the bumped pin (#246, #277) retires this waiver;
  markers of these rules surviving at that pin re-open #7817 with the new
  counts rather than extending this waiver.
- **Recorded by**: Loom Builder (issue #29), 2026-11-24.
