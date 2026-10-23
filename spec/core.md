# asap7-riscv-core — target specification

**Status: ratified 2026-10-17, subject to the deferrals marked below.**
Evidence for the PDK rows is in [`pdk-bringup.md`](pdk-bringup.md); each
decision has a record in [`decisions/`](decisions/).

**ASAP7 is a predictive PDK, not a foundry process. This block is layout, DRC
and timing only, and it is never fabricated.** There is no silicon, shuttle,
tape-out or measurement anywhere in this spec. Every timing figure is
**predicted** by STA against ASAP7's predictive models.

Each row is `ratified` or `deferred`. A deferral names its owner and the
trigger that ends it. A change to a ratified row goes through a new decision
record; results are never relaxed to pass.

## Target table (README rows)

| Parameter | Target | Fallback | Stretch | State |
|---|---|---|---|---|
| Core | RV32IMC, Ibex/CVE2-class, unmodified | RV32EC | — | ratified (0007) |
| Standard cells | ASAP7 7.5-track, `asap7sc7p5t_28` @ `f970bd3c`, RVT | — | — | ratified (0001) |
| Predicted clock, post-route STA, slow corner | 1 GHz (1.000 ns) | 500 MHz | 1.5 GHz | ratified (0003) |
| DRC | clean against the pinned deck (below) | clean with every waiver recorded | — | ratified (0005) |
| LVS | clean against the pinned cell CDL, with the recorded bulk policy | — | — | ratified (0005) |

### Core (adopted, decision 0007)

The core, its configuration and the upstream commit are the ones
`sky130-riscv-soc` ratified: CVE2 (`cve2_top`), RV32IMC (`RV32E=0`,
`RV32M=RV32MFast`), no debug module, at
`openhwgroup/cve2@d7f21568028a1114be663599bd42145dccf28928`. The pin and file
hashes are in [`../reuse.lock.json`](../reuse.lock.json). The origin decision
record is `spec/decision-records/0001-core-choice.md` at `sky130-riscv-soc`
commit `1e6c447d571e95f2aa4f8e29ae1ef30ab03bdaa8`. The RV32EC fallback stands.
No RTL is selected, forked or modified by this spec.

**sv2v:** if the pinned core is SystemVerilog needing conversion for Icarus
and Yosys, this repo uses the same pinned conversion as `sky130-riscv-soc`
rather than a second one. This part stays deferred: the origin has not pinned
sv2v yet. **Owner:** this repo's spec author. **Trigger:** `sky130-riscv-soc`
pins sv2v (decision 0007).

## PDK and tools (pinned)

- Upstream ASAP7 `d24f8b857ff74cf5b21ab18a7e1b11a3954c449b`; cell library
  `asap7sc7p5t_28` `f970bd3c3292b79ae4d022a3ec80533534614066`; PDK
  `asap7_pdk_r1p7` `58d72c9d291e186a77468586ab0c43d8a21eda6a`.
- `klt`: release `klayout-tools==0.7.0` is the pinned release; the metal DRC
  deck and FinFET LVS need the unreleased tree, pinned as
  `git+https://github.com/2AMLogic/klayout-tools@7ee09483b748` (decision 0005).
- `klt pdk` does not resolve ASAP7 yet; the repo's flow points at the pinned
  checkout by path until klayout-tools #3782 closes.

## STA corner set (Liberty files, quoted headers)

Library: `asap7sc7p5t_28/LIB/NLDM/`, groups AO, OA, INVBUF, SEQ, SIMPLE
(archives are `.7z`; extract before use). Voltages and temperatures are the
`nom_voltage` / `nom_temperature` values in each file.

| Corner | Role | Files (RVT) | V | °C |
|---|---|---|---|---|
| **SS — slow** | setup; **the 1 GHz target is evaluated here (predicted)** | `asap7sc7p5t_AO_RVT_SS_nldm_211120.lib`, `…OA_RVT_SS_nldm_211120.lib`, `…INVBUF_RVT_SS_nldm_220122.lib`, `…SEQ_RVT_SS_nldm_220123.lib`, `…SIMPLE_RVT_SS_nldm_211120.lib` | 0.63 | 100 |
| TT — typical | reference | same groups, `TT` | 0.7 | 25 |
| FF — fast | hold | same groups, `FF` | 0.77 | 0 |

**FF is provisional:** `asap7sc7p5t_SIMPLE_RVT_FF_nldm_211120.lib` carries a
0.7 V / 25 °C header, unlike the other FF files, so a mixed FF set is not a
consistent corner. Hold sign-off is deferred. **Owner:** STA issue author.
**Trigger:** the SIMPLE FF tables are shown to be characterised at 0.77 V /
0 °C (or a corrected file is pinned). SS and TT are ratified.

Timing results are labelled "predicted" and name the corner files.

## Threshold-voltage flavours (decision 0002)

Synthesis and optimisation may use **RVT only**. LVT and SLVT libraries ship
at TT only (0.7 V / 25 °C), so they cannot be timed at the SS sign-off corner.
SRAM-Vt cells are excluded (no SRAM in scope).

## Floorplan (decision 0004)

Starting values, adjustable by a later decision record with evidence from a
routed result: core utilisation **60 %**, aspect ratio **1.0** (square),
single block, no SRAM, no macro. These are starting points for placement, not
a claimed result.

## DRC / LVS acceptance (decision 0005)

- **"DRC clean" means:** `klt drc --engine klayout --deck-file <asap7.drc>`
  on the final GDS reports `status: clean` with zero violations, with
  `--expect-rule-categories` equal to the deck's declared count, and the
  report's `provenance.deck.content_hash` equal to the pinned hash:
  `sha256:08dba3ee047a3ec68b3cd761f982809c62a0d128b8d34ef4e76a28f61221aa6a`
  (263 categories). Clean against the released 0.7.0 deck
  (`sha256:a14ce43a…dbd0`, 106 FEOL/MOL categories) does **not** imply metal
  is checked and may not be reported as DRC clean.
- **Not checked yet** (from `pdk-bringup.md` §3): rules needing track, net,
  corner or grid predicates (#3147), FEOL/MOL increments (#2812), PAD.
  A clean report states these as unchecked; it does not claim full DRM
  coverage.
- **"LVS clean" means:** `klt lvs` status `match` (dev `klt` build; released
  0.7.0 refuses FinFET LVS), with the layout hash, reference hash and deck
  hash recorded, and `options.finfet_bulk` set to `{"nmos":"VSS","pmos":"VDD"}`
  (the cells draw no taps; the tie is an opt-in assumption disclosed in the
  report as `device.finfet_bulk_tied`).

### Waivers

A waiver is a file under `layout/waivers/` with: rule id, deck hash, location
(cell and coordinates), the violation text from the report, the reason, who
recorded it and when. It is committed in the same PR that records the report
it waives. A waived violation is still listed in the report summary; nothing
is suppressed in the deck. A report with unrecorded violations is not clean.
Waivers are never used to relax a ratified rule.

## Scope and exclusions

Used unmodified: the pinned core. Out of scope: SRAM, caches, SoC, any RTL
tuning for this PDK, and anything implying manufacture.
