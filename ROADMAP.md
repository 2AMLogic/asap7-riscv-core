# Roadmap

Place-and-route of an unmodified RV32IMC CVE2 core on ASAP7 (a predictive PDK;
nothing here is fabricated), used to exercise `klt` on FinFET-era rules.

**Status as of 2026-11-13, `main` @ `bf23a58`.** Every result below is a tool
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
| 2 Layout | unmet | #28, blocked (see below) |
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
content hash in `spec/core.md` (decisions 0012 and 0013).

Three facts in the committed core synthesis record shape what follows:

1. It was produced by `klt 0.8.0` (`flow/core/records/2026-11-03/tool-versions.txt`);
   `spec/core.md` has since moved the flow pin to `0.9.0`.
2. `synth.json` warns that `cell_library 'asap7sc7p5t_28_RVT'` has no verified
   mapping for `setundef -zero/hilomap`, and `netlist.v` contains 14 x-valued
   constant assigns. The pinned `klt place-and-route` refuses those, which is
   what blocks #28 (klayout-tools #5074). The released 0.9.0 package's tie-cell
   table has entries for `asap7sc7p5t_rvt` and `asap7sc7p5t_28_R`, and none for
   the key `flow/core/synth.sh` passes.
3. `synth.json` counts one `$_DLATCH_N_` instance: a generic latch not mapped
   to a library cell.

## Now

Each can start today and is one pull request.

1. **Re-run core synthesis on the pinned release with a `cell_library` key it
   recognises.** Done when a new dated directory under `flow/core/records/`
   holds a `synth.json` from `klayout-tools==0.9.0` without the
   `setundef -zero/hilomap` warning and a netlist with no x-valued constant
   assigns, or the record showing why the pinned release cannot reach that.
   No issue yet (draft 1). Unblocks #28.
2. **Account for the unmapped `$_DLATCH_N_`.** Done when a committed note
   names the source construct and either the netlist maps it to an ASAP7
   library cell without editing the pinned core, or a generic klayout-tools
   issue is linked. No issue yet (draft 2).
3. **Classify the 549 DRC violations on the counter layout.** Done when a
   committed table gives each of the seven rule ids in
   `flow/smoke/records/2026-11-05/drc.json` a count, an example location and a
   cause (flow setting, deck or tool), with a klayout-tools issue linked per
   tool or deck cause. No issue yet (draft 3). Clears the way for #29.
4. **Classify the LVS mismatch on the counter layout.** Done when a committed
   note explains the 19 topology errors in `lvs.json` of the same record by
   cause, with upstream issues linked likewise. No issue yet (draft 4). Clears
   the way for #30.
5. **Make the item-10 attestation gate say what to do** (#83, ready). Done
   when `CLAUDE.md` names the four attested paths and the re-attest command,
   and the `klt signoff` workflow step prints both on drift.
6. **Shell clean-ups, already claimed:** #84 (one sourced helper library for
   `verification/`, PR #86 in review) and #85 (drop the unused 0.8.0
   comparison-build fallback from `flow/smoke/run.sh`).

## Next

- **Re-run the gate-level arch-test on the new netlist** and re-attest items 1
  and 9, after Now 1. Done when `verification/run.sh --core --gate` records 72
  run, 0 failed on it and `rtl/inventory.json` binds it.
- **#28, item 2: committed P&R flow and routed core GDS.** Needs a netlist the
  pinned `klt place-and-route` accepts: Now 1, or a release fixing
  klayout-tools #5074. Acceptance is on the issue (reproducible GDS hash,
  `power.pdn: true`, a named tap cell master, item 2 `met`).
- **#29 (DRC), #30 (LVS), #31 (power delivery)** on the routed core, after #28.
- **#32, item 5: multi-corner `klt sta` and `klt functional-verification`**
  after #28; it also needs the FF hold corner settled (see below).
- **#34 (SDF-annotated post-layout run)** after #28 and #32; **#35
  (characterization report)** after #29, #30 and #32.

## Later

- **Timing closure at the 1 GHz predicted target.** First: what does post-route
  SS-corner STA report on the ratified floorplan (decision 0004)? Moving to the
  500 MHz fallback needs a decision record.
- **ERC with an antenna table.** `erc.json` is `not_checked` (klayout-tools
  #4090). First: can a table be derived from the pinned PDK files?
- **Resolving ASAP7 through `klt pdk`.** `spec/core.md` points the flow at the
  checkout by path "until klayout-tools #3782 closes"; that issue is now
  closed. First: does the pinned release resolve ASAP7?

## Blocked and waiting

- **#28 is parked on klayout-tools #5074** (open). That issue in turn asks the
  reporter for a diagnostic `klt synthesize` re-run, so the wait runs both
  ways; Now 1 is this repo's side. Six of the seven unmet items sit behind #28.
- **FF hold corner (decision 0002, provisional).** The comparison record
  `flow/core/records/2026-11-05/ff-simple-check.json` (PR #61) notes an
  upstream commit after the pin correcting three SIMPLE RVT FF Liberty files.
  Ratifying FF or re-pinning the library is a spec decision, not yet recorded.
- **Decisions 0012 and 0013 still read "proposed"**, though `spec/core.md`
  already carries their pins.
- **PR #82** (README status refresh) is in review; the README on `main` still
  says the core is not synthesized.

**Dispatchable today:** #83, plus #84 and #85 already claimed; the four drafts
once filed. The layout path (#28 to #35) waits on Now 1 or the upstream fix.

## Not planned

- Fabrication, a shuttle, or any measurement: ASAP7 is predictive.
- Changes to the core RTL; SRAM, caches or an SoC around the core.
- LVT or SLVT cells: only RVT has an SS corner (decision 0002).
- Local patches to the tech LEF or the CTS buffer to get a clean result
  (rejected in decision 0012); tool gaps go to klayout-tools.
