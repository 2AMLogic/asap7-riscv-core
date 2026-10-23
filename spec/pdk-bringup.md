# ASAP7 bring-up record

ASAP7 is a **predictive** PDK. This block is **layout, DRC and timing only
and is never fabricated**; every result below is a tool result against a
predictive model. Recorded 2026-10-17 on a Linux worker. This file is
append-only evidence: later re-runs add a dated section, they do not rewrite
this one.

## 1. Pins

| Item | Pin |
|---|---|
| Upstream repo | `The-OpenROAD-Project/asap7` @ `d24f8b857ff74cf5b21ab18a7e1b11a3954c449b` (2025-03-12, "Improve wording for snps enablement") |
| Cell library (7.5-track) | submodule `asap7sc7p5t_28` @ `f970bd3c3292b79ae4d022a3ec80533534614066` (2024-07-18) |
| PDK (DRM, Calibre notes, models) | submodule `asap7_pdk_r1p7` @ `58d72c9d291e186a77468586ab0c43d8a21eda6a` (2024-07-18) |
| Also fetched, not selected | `asap7sc7p5t_27` @ `adb6d0d354e76e46a782ad06498f1977257d5742` (see decision 0001) |
| Released `klt` | `klayout-tools==0.7.0` from PyPI (`uvx --from klayout-tools==0.7.0 klt`), KLayout 0.30.12 inside its environment |
| Dev `klt` also exercised | `0.7.1.dev1743+g7ee09483b748` (unreleased; reproducible as `uvx --from "git+https://github.com/2AMLogic/klayout-tools@7ee09483b748" klt`, verified to resolve) |

Files used (sha256, from the pinned checkout):

| File | sha256 |
|---|---|
| `asap7sc7p5t_28/GDS/asap7sc7p5t_28_R_220121a.gds` | `f43d5b33df635cf9e66cbca66b6bdd05364f824d8040cd21528b9e12808b9263` |
| `asap7sc7p5t_28/LEF/asap7sc7p5t_28_R_1x_220121a.lef` | `43b68456f51949b5aeb7295b7ab8444e8c36d25c600e9bc6c3ee9d9aeb13ca0b` |
| `asap7sc7p5t_28/techlef_misc/asap7_tech_1x_201209.lef` | `830a032810b054d0dc24601c3f57c86073469e6c9cfb0314b2c82eb335b021d2` |
| `asap7sc7p5t_28/CDL/LVS/asap7sc7p5t_28_R.cdl` | `444a08c16f5a44b4ec6f64e5ad4112d0dd8ca5a3fe5da7a7644e63f538bf681e` |

Liberty (NLDM) files, as shipped (`asap7sc7p5t_28/LIB/NLDM/`, **7-zip only**):

| Archive | sha256 |
|---|---|
| `asap7sc7p5t_AO_RVT_SS_nldm_211120.lib.7z` | `e7c78a2cf97e13ae7aeb22d52e9cdb4fb3c3f1c7d4034a213db70b00d534fed2` |
| `asap7sc7p5t_AO_RVT_TT_nldm_211120.lib.7z` | `d8ec2c98f0709817cf9bf08ac6bd3363ba086789bdbeb9d1036b3e5b2ea56041` |
| `asap7sc7p5t_AO_RVT_FF_nldm_211120.lib.7z` | `2e95a4ca80138e69bf27288489b24472bc0d6431b4bf65c06a6d71925ec8a336` |
| `asap7sc7p5t_INVBUF_RVT_SS_nldm_220122.lib.7z` | `d9f6978ef3e3b52a27cd031bdb6e69b48d09ef5ac2552223108054cc05702554` |
| `asap7sc7p5t_INVBUF_RVT_TT_nldm_220122.lib.7z` | `3803bb90380bc39445db17d2f60a2c53bd4baf63ddffbc742ab7ae651dc649e0` |
| `asap7sc7p5t_INVBUF_RVT_FF_nldm_220122.lib.7z` | `1d9c4a891633f5d197659e39864a74e39f9bd30465589168491e38488fbea386` |
| `asap7sc7p5t_OA_RVT_SS_nldm_211120.lib.7z` | `8fa0d69ef253202523e86890a6226010a063fc6a71a2749268e7dcdbf48f5ff5` |
| `asap7sc7p5t_OA_RVT_TT_nldm_211120.lib.7z` | `6a5204f97ffc242e999bafedf5de95dc06a49624928f98dbb7b415c9e492e689` |
| `asap7sc7p5t_OA_RVT_FF_nldm_211120.lib.7z` | `038f15998a91798a6771ebf3422a8ce966a766ffa29a41f30956be95f88ff720` |
| `asap7sc7p5t_SEQ_RVT_SS_nldm_220123.lib.7z` | `75a5b64e33bab08a7e28258de10e3b866f2f27c6ef3e9c9165097690d47d0362` |
| `asap7sc7p5t_SEQ_RVT_TT_nldm_220123.lib.7z` | `e2895b3b0b32e4d0aa10e04c465b6297eec5a8eb3615058edc8595faeb094138` |
| `asap7sc7p5t_SEQ_RVT_FF_nldm_220123.lib.7z` | `35f963b0028921bc7a6224785eef41f5faeceadca762d6432369af3be7b06391` |
| `asap7sc7p5t_SIMPLE_RVT_SS_nldm_211120.lib.7z` | `1d94482c8f023eb27cae37b9c2b41b390750e7c201d79c85ffa326df5031d293` |
| `asap7sc7p5t_SIMPLE_RVT_TT_nldm_211120.lib.7z` | `78c5e55ec239efe080458532f9f55dff5457c3ce4144d8c9f2bac1a484b634c4` |
| `asap7sc7p5t_SIMPLE_RVT_FF_nldm_211120.lib.7z` | `4e76f346d9a2c19e13d0ab561a993f2244269232d9398d218fb1cf155502125e` |

Reproduce the checkout in an empty scratch directory (never inside this repo):

```
git clone https://github.com/The-OpenROAD-Project/asap7.git && cd asap7
git checkout d24f8b857ff74cf5b21ab18a7e1b11a3954c449b
git submodule update --init asap7_pdk_r1p7 asap7sc7p5t_28   # ~3 GB
```

## 2. What resolves under `klt`

| Item | Resolves under klt 0.7.0? | Evidence |
|---|---|---|
| PDK root via `klt pdk find --pdk asap7` | **No** | exit with "no supported-layout PDK install providing variant 'asap7' was found"; ASAP7 is not an open_pdks-layout tree. Tracked: klayout-tools #3782. |
| Technology / layer map | Partial | The DRC deck hard-codes the layer/datatype numbers of the pinned `asap7.lyp` (deck header). No `klt pdk` surface returns them. A PAD-layer inconsistency is tracked at #3807. |
| Cell GDS | Yes, as a file | `GDS/asap7sc7p5t_28_R_220121a.gds`: 212 top-level cells, dbu 0.00025 um. `klt drc` on the whole file fails (multi-top-cell, #3788), so cells were split one-per-file for the runs below. |
| Cell LEF / tech LEF | Files only | tech LEF declares M1–M9, V0–V9 and Pad (pitches are in the LEF; not transcribed here). Not consumed by klt. |
| Liberty | **No** | ships only as `.7z` (#3782); extracted with a throwaway `py7zr` environment for header inspection only. |
| Routing stack | Files only | tech LEF above; no klt surface. |
| DRC deck | Partly | see §3 |
| LVS path | Partly | see §4 |

Commands and results (klt 0.7.0 unless stated):

```
klt pdk find --pdk asap7
  -> error: no supported-layout PDK install providing variant 'asap7'
klt deck info --deck asap7
  -> content_hash sha256:30a8d86cc36f99ffc54b0c86ab69a737acd91ba0fd21f6de3c842f9fba9d2aaf
     device_classes: nfet, pfet ; release 0.7.0 (v0.7.0, 0e2362bda7309829398a35d54efaa989d5806065)
klt deck rules --deck asap7      -> error: unknown deck 'asap7' (available: gf180mcu, sg13cmos5l, sg13g2, sky130)   (#3783)
klt drc --deck asap7 <gds>       -> same "unknown deck" error                                                        (#3783)
```

## 3. DRC deck

`klt drc --deck asap7` is unusable in the released package (#3783, #3789), so
the packaged deck file was run with `--engine klayout --deck-file`.

| | klt 0.7.0 (released) | dev 0.7.1.dev1743+g7ee09483b748 |
|---|---|---|
| Deck file | `klayout_tools/decks/asap7.drc` | same path |
| Deck sha256 (`provenance.deck.content_hash`) | `a14ce43afe9f6e14091836a30476e01fa56990b1d1f31525b4a88da66610dbd0` | `08dba3ee047a3ec68b3cd761f982809c62a0d128b8d34ef4e76a28f61221aa6a` |
| Rule categories declared | 106 (FEOL + MOL: FIN, GATE, GCUT, ACTIVE, LISD, LIG, SDT, V0, wells, Vt layers) | 263 (adds M1–M9 / V1–V9 rules and further rules; the full id list is in the deck's `asap7_rules.py`) |
| `provenance.deck.released` | false | false |

**This repo's pinned deck is the dev-build deck (`08dba3ee…aa6a`, 263
categories), because it is the only one that covers the metal stack.** The
released 0.7.0 deck (`a14ce43a…dbd0`, 106 categories) is the fallback; a
BEOL "clean" cannot be claimed against it. See decision 0005 and
klayout-tools #3826 (no released klt carries the full ASAP7 flow).

Source of every rule (from the deck header): the ASAP7 PDK Design Rule
Manual, "PDK Release 1p7" (`asap7_drm_201207a.pdf`, shipped in the pinned
`asap7_pdk_r1p7/docs/`), transcribed by klayout-tools — **not** the vendor
Calibre runset (`asap7_pdk_r1p7/calibre/ruledirs/drc/` holds only a README
in this checkout). Rule ids are the DRM's own names.

Layout runs, dev deck (`klt drc --engine klayout --deck-file … --expect-rule-categories 263`):

| Cell (asap7sc7p5t_28 R) | Status | Violations |
|---|---|---|
| INVx1_ASAP7_75t_R | clean | 0 |
| NAND2xp5_ASAP7_75t_R | clean | 0 |
| DFFHQNx1_ASAP7_75t_R | clean | 0 |

Released deck on the same INVx1 cell: `--expect-rule-categories 106` → clean,
0 violations; `--expect-rule-categories 263` fails ("deck's report declared
106").

Rules that cannot be checked yet, and where each is tracked:

| Gap | Tracked at |
|---|---|
| `klt drc --deck asap7` / `klt deck rules --deck asap7` reject the deck by name | klayout-tools #3783 |
| No CLI way to locate the packaged `.drc` for `--deck-file` | #3789 |
| Multi-top-cell stream (as the cell library ships) not supported; `--top` unsupported with `--engine klayout` | #3788 |
| Expected rule-category count documented as both 263 and 232 | #3790 |
| PAD layer number inconsistent across pinned files; PAD has no rules | #3807 |
| BEOL rules needing track / net / corner / grid predicates | #3147 |
| FEOL/MOL mechanism-specific increments | #2812 |
| Deck authoring umbrella; fin/gate-grid helpers | #2760, #2762 |
| Released package ships a 106-category deck and refuses FinFET LVS | #3826 (filed from this work) |

Rules named in the vendor Calibre runset but not enumerated against this
deck: **not compared** — the checkout carries no runset, so a rule-by-rule
diff against "upstream" is not possible and is not claimed.

## 4. LVS path

| | klt 0.7.0 | dev build |
|---|---|---|
| `klt extract --deck asap7` on INVx1 | extracted, nmos_rvt + pmos_rvt, `NFIN=3` | identical netlist (sha256 `6d169646…d87a5a`) |
| `klt lvs` with `layout.deck: asap7` | refused (FinFET LVS "tracked in issue #2813") | runs |
| INVx1 / NAND2xp5 / DFFHQNx1 vs `asap7sc7p5t_28_R.cdl` subckt, default options | n/a | `mismatch` (14 for INVx1: cell draws no substrate/well taps, so NMOS bulk is the synthesized `vsubs` net; documented in klt's lvs.md) |
| same, `options.finfet_bulk = {"nmos":"VSS","pmos":"VDD"}` | n/a | **`match`** for all three (warnings: 2× `device.finfet_bulk_tied`, 1× `net.supply_fragmented`) |

Library GDS views: one GDS per Vt flavour (`R`, `L`, `SL`, `SRAM`) and
one CDL per flavour under `CDL/LVS/`. They extract (above). The cell-library
CDL is the reference for cell-level LVS only; block-level LVS needs a
post-route netlist and is a later issue.

Known limits, from klt's own documentation of its ASAP7 corpus (not
re-measured here): 11 folded-stack and 6 series-order cells do not compare
`match`. Any of those cells appearing in the block needs a recorded waiver
(see `spec/core.md`, "Waivers").

## 5. Liberty corner headers (quoted from the extracted files)

| File | `nom_voltage` | `nom_temperature` |
|---|---|---|
| `asap7sc7p5t_{AO,OA,INVBUF,SEQ}_RVT_SS_nldm_*.lib` | 0.63 | 100 |
| `asap7sc7p5t_{AO,OA,INVBUF,SEQ}_RVT_TT_nldm_*.lib` | 0.7 | 25 |
| `asap7sc7p5t_{AO,OA,INVBUF,SEQ}_RVT_FF_nldm_*.lib` | 0.77 | 0 |
| `asap7sc7p5t_SIMPLE_RVT_SS_nldm_211120.lib` | 0.63 | 100 |
| `asap7sc7p5t_SIMPLE_RVT_TT_nldm_211120.lib` | 0.7 | 25 |
| `asap7sc7p5t_SIMPLE_RVT_FF_nldm_211120.lib` | **0.7** | **25** |
| `*_{LVT,SLVT}_TT_*.lib` (all groups) | 0.7 | 25 |

**Anomaly:** the SIMPLE RVT FF file's header says 0.7 V / 25 °C (operating
condition `PVT_0P7V_25C`), not the 0.77 V / 0 °C of every other FF file,
and its body differs from the SIMPLE TT file. Whether its tables are
characterised at FF conditions is not established here; until it is, the FF
corner is **not** a ratified sign-off corner (see decision 0002). This is an
upstream data question, not a klt gap.

## 6. Reproducing

```
uvx --from klayout-tools==0.7.0 klt deck info --deck asap7
uvx --from klayout-tools==0.7.0 klt extract --deck asap7 <INVx1.gds> --top INVx1_ASAP7_75t_R -o inv.cir
```

The one-cell-per-file GDS split used a 10-line script with the `klayout` PyPI
package (`copy_tree` of each cell into a fresh layout). It is not committed:
it is a workaround for #3788 and should disappear when that closes.

## 7. Smoke re-run, 2026-10-23

Appended; sections 1-6 above are unchanged. `flow/smoke/run.sh` runs the
placeholder `counter` DUT through the ASAP7 flow; records are in
`flow/smoke/records/2026-10-23/` (tool and input versions in
`tool-versions.txt`). Every figure is a tool result against a predictive model
and **not a design claim**: the counter is not the core.

Builds compared: the pin from `spec/core.md`, `0.7.1.dev1743+g7ee09483b748`,
and the current dev build `0.7.1.dev2517+g6bb7cf233677`, which is **not the
pin** (`uvx --from git+https://github.com/2AMLogic/klayout-tools@6bb7cf233677 klt`).
Differences are evidence for a later pin-bump decision record; the pin and the
ratified hash are unchanged here.

### 7.1 The section 2 table, re-run

| Item | Pinned build | Current dev build |
|---|---|---|
| `klt pdk find --pdk asap7` on a plain upstream checkout | No (same error as section 2) | No: needs a `klt-pdk.json` descriptor, which the run script writes in a scratch overlay (the checkout is not modified) |
| Same, with the descriptor | No: descriptor not read | Yes (Liberty only; see 7.3) |
| `klt deck info --deck asap7` (extraction deck) | `sha256:30a8d86c…` released 0.7.0 | same hash; also reports the DRC deck `sha256:827ad7eb…`, **not the pinned** `08dba3ee…` |
| `klt deck rules --deck asap7` / `klt drc --deck asap7` | "unknown deck 'asap7'" | refused with "no curated DRC rule table ... use `--engine klayout --deck-file`" |
| Multi-top-cell cell GDS | `--top` unsupported with `--engine klayout`; `klt clip --cell` makes a one-cell stream instead | `--top` works |
| Liberty | `.7z` only; extracted with a throwaway `py7zr` env | same; five group files per corner, merged in scratch |

### 7.2 Step results

| Step | Result | Build | Record |
|---|---|---|---|
| synth | `ok`: 31 instances, 4.87 um2 against the merged RVT SS Liberty | current (the pin cannot resolve the PDK) | `synth.json` |
| par | **`not_run`**. Pinned: PDK does not resolve. Current: `no clock-tree buffer cell known for standard-cell library`, `no power pin-pattern table known`, `[ERROR RSZ-0089] Could not find a resistance value` without `request.power`. With `power` removed and `target_stage: floorplan` it reaches floorplan only, after a scratch tech-LEF edit (M2 `OFFSET -0.27` to `0.0`). No DEF or GDS exists. | none | `par.json`; klayout-tools #4086, #4087, #4088 |
| drc | `clean`, 0 violations, `--expect-rule-categories 263` satisfied, `provenance.deck.content_hash` = `sha256:08dba3ee…aa6a`, equal to the pin in `spec/core.md` | pinned | `drc.json` |
| lvs | `match` with `options.finfet_bulk = {"nmos":"VSS","pmos":"VDD"}`; three warnings (2x `device.finfet_bulk_tied`, `net.supply_fragmented`); layout, reference and deck hashes recorded | pinned | `lvs.json` |
| erc | `not_checked`: the spec-file connectivity checks pass (0 findings) but there is no ASAP7 antenna table, so every antenna level is skipped | pinned | `erc.json`; klayout-tools #4090 |
| sta | `ok` at SS (0.63 V / 100 C) and TT (0.7 V / 25 C), RVT, **predicted**, 1.000 ns clock, ideal clock, **netlist estimate, not post-route**: worst setup path slack -0.211 ns (SS) and -0.143 ns (TT) | current | `sta.json`; klayout-tools #4089 |

Limits stated, not hidden:

- **drc, lvs and erc ran on a stand-in**, library cell `INVx1_ASAP7_75t_R`
  clipped from the pinned cell GDS, because place-and-route produced no
  layout. They show that the pinned deck and the pinned LVS/ERC path run; they
  say nothing about the counter. The rules listed unchecked in section 3 and in
  `spec/core.md` remain unchecked.
- **STA numbers are not the 1 GHz target result.** The target is predicted
  post-route at the slow corner; this is a pre-placement netlist estimate. The
  aggregate `worst_slack_ns`, `worst_hold_slack_ns` and `fmax_mhz` fields in
  `sta.json` are 1000x off because the Liberty `time_unit` is 1 ps (#4089); the
  worst-path slack is the figure above. FF is not run (decision 0002).
- The tech-LEF edit and the Liberty merge are scratch-only workarounds,
  recorded by hash in `tool-versions.txt`; neither is committed.

### 7.3 Gaps filed in klayout-tools

| Issue | Gap |
|---|---|
| #4086 | place-and-route: no CTS buffer, power pin-pattern or wire-RC table for a library outside the built-in set, and no request override |
| #4087 | `klt-pdk.json` maps Liberty only (one file per corner); LEF and tech LEF still need open_pdks naming |
| #4088 | bare `make_tracks` aborts (IFP-0039) on a tech-LEF layer with a negative `OFFSET` |
| #4089 | `klt sta`: a Liberty with `time_unit` 1 ps scales the aggregate slack fields and `fmax_mhz` 1000x |
| #4090 | `klt erc`: no ASAP7 antenna-ratio table |

Not re-filed: the pinned build's failures that the current build fixes
(descriptor resolution, `--top` with `--engine klayout`) are recorded in 7.1 as
pin-versus-current differences, per the pin-bump route above.
