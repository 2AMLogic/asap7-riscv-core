# Roadmap

Place-and-route of an unmodified RV32IMC CVE2 core on ASAP7 (a predictive PDK;
nothing here is fabricated), used to exercise `klt` on FinFET-era rules.

**Status as of 2026-11-14, `main` @ `f0cbc2f`.** Every result below is a tool
result against a predictive model; every timing figure is predicted. The label
queue is in [`WORK_PLAN.md`](WORK_PLAN.md), merge history in
[`WORK_LOG.md`](WORK_LOG.md), and the item-by-item tracker is issue #6.

## Where it stands

On the README's ladder: PDK brought up under `klt`, spec ratified, core passing
the architectural tests in simulation, core synthesized; not yet placed and
routed. Against the T1 checklist (`manifests/design-evidence-tiers.md`), the
committed verdict `manifests/asap7-riscv-core.signoff.json` reads **3 of 11
met, 1 not applicable**:

| Item | State | Evidence or owner |
|---|---|---|
| 1 Design sources | met | `evidence/item1.json`; netlist `flow/core/records/2026-11-03/netlist.v` (20,441 instances, PR #45) |
| 2 Layout | unmet | #28, blocked |
| 3 DRC clean | unmet | #29, behind #28 |
| 4 LVS clean | unmet | #30, behind #28 |
| 5 Corner verification | unmet | #32, behind #28 |
| 6 Statistical rows | not applicable | `spec/statistical-rows.json`, decision 0008 |
| 7 Post-layout verification | unmet | #34, behind #28 and #32 |
| 8 Characterization | unmet | #35, behind #29, #30, #32 |
| 9 Testbenches shipped | met | `evidence/item9.json`; 72 riscv-arch-test programs, 0 failed, at RTL (`verification/records/2026-11-05/`) and on the gate-level netlist (`verification/records/2026-11-06/`, PR #73) |
| 10 Repo hygiene | met | `evidence/item10.json` |
| 11 Power delivery | unmet | #31, behind #28 and #30 |

Also on `main`: the smoke flow on the placeholder counter runs every step on
the pinned `klayout-tools==0.9.0` (`flow/smoke/records/2026-11-05/`, PR #66).
`par` is `ok` with DEF and GDS; on that layout DRC reports 549 violations in
seven rule ids, LVS is `mismatch` (19 topology errors) and ERC is
`not_checked`. The DRC deck (267 categories) and the LVS deck are pinned by
content hash in `spec/core.md` (decisions
`0012-pin-klt-0-9-0-and-ratify-asap7-drc-deck` and 0013 — two records share the
number 0012, which #90 tracks).

Three facts in the committed core synthesis record shape what follows:

1. It was produced by `klt 0.8.0` (`flow/core/records/2026-11-03/tool-versions.txt`);
   `spec/core.md` has since moved the pin to `0.9.0` for DRC, LVS and the smoke
   flow only — `klt signoff` stays at `0.8.0` (decision 0008) and no pin is
   named for core synthesis, so re-running synthesis on `0.9.0` may itself need
   a decision record.
2. `synth.json` warns that `cell_library 'asap7sc7p5t_28_RVT'` has no verified
   mapping for `setundef -zero/hilomap`, and `netlist.v` contains 14 x-valued
   constant assigns. The pinned `klt place-and-route` refuses those, which is
   what blocks #28 (klayout-tools #5074). The released 0.9.0 package's tie-cell
   table has entries for `asap7sc7p5t_rvt` and `asap7sc7p5t_28_R`, and none for
   the key `flow/core/synth.sh` passes.
3. `synth.json` counts one `$_DLATCH_N_` instance: a generic latch not mapped
   to a library cell.

## Queue state and sequencing

The queue is not kept here by hand: [`WORK_PLAN.md`](WORK_PLAN.md) is
generated from the labels and issue #6 tracks the items item-by-item. The
remaining work runs in a fixed order: re-run core synthesis against the
pinned release, place and route the core, then the checks that need a placed
core (DRC, LVS, power delivery), then corner verification, post-layout
verification and characterization — closing on timing closure at the 1 GHz
predicted post-route target (500 MHz the fallback, 1.5 GHz the stretch).

## Later

- **Timing closure at the 1 GHz predicted target.** First: what does post-route
  SS-corner STA report on the ratified floorplan (decision 0004)? Moving to the
  500 MHz fallback needs a decision record.
- **ERC with an antenna table.** `erc.json` is `not_checked`, with
  `coverage.nothing_checked_reasons` `gate_reference_level` and
  `missing_antenna_pdk`. klayout-tools #4090, which reported this, closed
  2026-10-24 while the gap persists in the 2026-11-05 record, so the friction
  protocol owes a fresh klayout-tools issue. First: can a table be derived from
  the pinned PDK files?
- **Resolving ASAP7 through `klt pdk`.** `spec/core.md` points the flow at the
  checkout by path "until klayout-tools #3782 closes"; that issue is now
  closed. First: does the pinned release resolve ASAP7?

## Not planned

- Fabrication, a shuttle, or any measurement: ASAP7 is predictive.
- Changes to the core RTL; SRAM, caches or an SoC around the core.
- LVT or SLVT cells: only RVT has an SS corner (decision 0002).
- Local patches to the tech LEF or the CTS buffer to get a clean result
  (rejected in decision `0012-pin-klt-0-9-0-and-ratify-asap7-drc-deck`); tool
  gaps go to klayout-tools.
