# 0005 — DRC/LVS acceptance and waiver rule

**Status:** accepted 2026-10-17.

**Decision.** "Clean" is defined against a named deck hash and recorded options (full wording in
`spec/core.md`, "DRC / LVS acceptance"). The pinned DRC deck is the unreleased-tree deck
`sha256:08dba3ee047a3ec68b3cd761f982809c62a0d128b8d34ef4e76a28f61221aa6a` (263 categories) from
`git+https://github.com/2AMLogic/klayout-tools@7ee09483b748`. The released 0.7.0 deck (106
FEOL/MOL categories) cannot support a clean claim on metal. LVS uses `finfet_bulk` as an opt-in,
disclosed assumption. Waivers are files under `layout/waivers/` with rule, deck hash, location,
report text and reason.

**Why.** The deck is DRM-transcribed by klayout-tools, not the vendor Calibre runset, so
"clean" must name the deck it is clean against and list what is unchecked (tracked at
klayout-tools #3147, #2812, #3807, #3826). A waiver is never silent.

**Consequences.** When klayout-tools releases the full deck, a new record re-pins to the release.
