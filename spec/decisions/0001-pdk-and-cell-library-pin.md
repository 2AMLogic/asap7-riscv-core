# 0001 — PDK and cell-library pin

**Status:** accepted 2026-10-17. ASAP7 is predictive; nothing here implies fabrication.

**Decision.** Pin `The-OpenROAD-Project/asap7` @ `d24f8b857ff74cf5b21ab18a7e1b11a3954c449b`, with
submodules `asap7sc7p5t_28` @ `f970bd3c3292b79ae4d022a3ec80533534614066` and `asap7_pdk_r1p7` @
`58d72c9d291e186a77468586ab0c43d8a21eda6a`. Use the 7.5-track `R` (RVT) views.

**Why `_28` and not `_27`.** klayout-tools' ASAP7 LVS corpus and DRC deck are written against the
`asap7sc7p5t_28` cells (270 nm cell height, 1x drawing); `_27` is fetched but unused. Not checked
here: a cell-by-cell diff of `_27` against `_28`.

**Consequences.** Re-pinning is a new decision record. File hashes are in `spec/pdk-bringup.md`.
