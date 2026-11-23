# Roadmap

Place-and-route of an unmodified RV32IMC CVE2 core on ASAP7 (a predictive PDK;
nothing here is fabricated), used to exercise `klt` on FinFET-era rules.

**Baseline as of 2026-11-14, `main` @ `f0cbc2f`, with later verification and
synthesis records cited below.** Every result below is a tool
result against a predictive model; every timing figure is predicted. The label
queue is in [`WORK_PLAN.md`](WORK_PLAN.md), merge history in
[`WORK_LOG.md`](WORK_LOG.md), and the item-by-item tracker is issue #6.

## Where it stands

On the README's ladder: PDK brought up under `klt`, spec ratified, core passing
the architectural tests in simulation, core synthesized; not yet placed and
routed. Against the T1 checklist (the tiers doc shipped by the pinned
`klayout-tools==0.8.0`, decision 0020), the committed verdict
`manifests/asap7-riscv-core.signoff.json` reads **3 of 11
met, 1 not applicable**:

| Item | State | Evidence or owner |
|---|---|---|
| 1 Design sources | met | `evidence/item1.json`; netlist `flow/core/records/2026-11-20/netlist.v` (29,785 instances; tie-cell and latch-mapped) |
| 2 Layout | unmet | #28, blocked |
| 3 DRC clean | unmet | #29, behind #28 |
| 4 LVS clean | unmet | #30, behind #28 |
| 5 Corner verification | unmet | #32, behind #28 |
| 6 Statistical rows | not applicable | `spec/statistical-rows.json`, decision 0008 |
| 7 Post-layout verification | unmet | #34, behind #28 and #32 |
| 8 Characterization | unmet | #35, behind #29, #30, #32 |
| 9 Testbenches shipped | met | `evidence/item9.json`; 72 riscv-arch-test programs, 0 failed, at RTL (`verification/records/2026-11-05/`) and on the 2026-11-14 netlist (`verification/records/2026-11-15/gate-core-archtest.json`, PR #157) |
| 10 Repo hygiene | met | `evidence/item10.json` |
| 11 Power delivery | unmet | #31, behind #28 and #30 |

Also on `main`: the smoke flow on the placeholder counter runs every step on
the pinned `klayout-tools==0.9.0` (`flow/smoke/records/2026-11-21/`). `par`
is `ok` with DEF and GDS, LVS is `match` (0 errors, the `flatten_layout`
recipe) and ERC is `not_checked`; DRC reports 44 violations in five rule ids,
every marker attributed in `flow/smoke/analysis/2026-11-21-drc.md` — 35
PDN-stack markers (klayout-tools #6909) and 3 router via-pad tips (1
`M1.S.4`, 2 `M1.S.5`; klayout-tools #7397 — see the recheck below) wait
upstream, and the 6 shipped-cell `BUFx4` markers
are #29's disclosure question. The DRC deck (267 categories) and the LVS deck
are pinned by content hash in `spec/core.md` (decisions
`0012-pin-klt-0-9-0-and-ratify-asap7-drc-deck` and 0013 — two records share the
number 0012, which #90 tracks).

The addendum's upstream citations were accurate at its date and moved after
it: #4508 and #7001 closed on 2026-11-22, both with fixes merged to
unreleased main (newest tag `v0.9.2` predates them; upstream #6930 tracks
the next tag). The 2026-11-23 recheck
(`flow/smoke/analysis/2026-11-23-upstream-disposition-recheck.md`)
measured both against this repo's pin: the merged pad-tip repair leaves
this counter's 3 router tips — 1 `M1.S.4`, 2 `M1.S.5` — unchanged (they
are pad–wire pairs outside the repair's pad–pad scope, so the open
successor is klayout-tools #7397, not the closed #4508), while the RVT
preset fix works at main — a verified later-version fix routed to the pin
bump #246 tracks. The 35 PDN-stack markers still wait on the open #6909.

Three facts in the committed core synthesis record (`2026-11-20`, whose
netlist is the accepted one item 1 binds to) shape what follows:

1. It was produced by `klt 0.9.0`
   (`flow/core/records/2026-11-20/tool-versions.txt`) — the same release
   `spec/core.md` pins for DRC, LVS and the smoke flow (decision 0012), so the
   cross-version caveat of the `2026-11-03` record (synthesized on 0.8.0) is
   settled. `klt signoff` stays at `0.8.0` (decision 0008).
2. `netlist.v` drives its constants with tie cells (2497 `TIEHIx1_ASAP7_75t_R`
   + 6847 `TIELOx1_ASAP7_75t_R`) and contains no x-valued constant assigns
   (the `2026-11-03` netlist had 14), so the constant-assign refusal that
   blocked #28 (klayout-tools #5074) no longer applies to it. The remaining
   `unsupported_cell_library` warning in `synth.json` concerns ABC `-constr`
   (driving cell/output load), load-driven sizing/buffering and ABC timing —
   skipped capabilities, not a mapping gap.
3. The one inferred latch (`cve2_clock_gate`) is mapped to a library cell:
   `synth.json` counts one `DLLx1_ASAP7_75t_R` instance and zero
   `$_DLATCH_N_`, via the `latch_map.negative` mapping `flow/core/synth.sh`
   passes. What still keeps #28 behind a per-library override is the CTS
   buffer-cell table: `klt` 0.9.0's `place_and_route._CTS_BUFFER_CELLS` has
   no ASAP7 entry.

## Queue state and sequencing

The queue is not kept here by hand: [`WORK_PLAN.md`](WORK_PLAN.md) is
generated from the labels and issue #6 tracks the items item-by-item. The
remaining work runs in a fixed order: place and route the core, then the
checks that need a placed core (DRC, LVS, power delivery), then corner
verification, post-layout verification and characterization — closing on
timing closure at the 1 GHz predicted post-route target (500 MHz the
fallback, 1.5 GHz the stretch).

## Later

- **Timing closure at the 1 GHz predicted target.** First: what does post-route
  SS-corner STA report on the ratified floorplan (decision 0004)? Moving to the
  500 MHz fallback needs a decision record.
- **ERC with an antenna table.** `erc.json` is `not_checked`, with
  `coverage.nothing_checked_reasons` `gate_reference_level` and
  `missing_antenna_pdk`. klayout-tools #4090, which reported this, closed
  2026-10-24 while the gap persists in the 2026-11-21 record, so the friction
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
