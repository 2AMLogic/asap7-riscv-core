# `klt erc` supply evidence (item 11, structural power delivery)

This directory owns the **supply-scoped** `klt erc` spec for this repo, first
exercised on the routed counter layout (#226) so the spec and its tool
dependencies are proven before the core needs them (#31). The smoke flow's own
ERC run (`flow/smoke/run.sh` step 5) stays antenna-scoped and unchanged; the
two runs are separate evidence, not replacements for each other.

## Files

- `supply.spec.json` — the supply spec: VDD and VSS as `nets[]` entries with
  `"kind": "supply"`, a stackup covering every PDN layer the counter's
  `par.json` reports, and two `ties[]` entries (choices below).
- `records/<date>/erc-supply.json` — the committed report of a run, exactly as
  the pinned klt produced it (append-only; a later run adds a new dated
  directory, never edits one).

## The spec

**Stackup and vias.** `par.json` (2026-11-15) reports followpin rails on M1/M2
(`power.connects` M1–M2, M2–M5, M5–M6), stripes on M2–M6 and straps on M1, M2,
M5, M6, so the stackup runs `m1`…`m6` with vias `v1`…`v5` between them. Layer
numbers are taken from the pinned PDK's own maps, not invented: metals and vias
from `asap7_fromAPR.layermap` (`asap7_pdk_r1p7` `cdslib/asap7_TechLib_10`,
sha256 `2ce51d6d…`, the same file `par.json`'s `layer_map` names), FEOL roles
(`well` 1/0, `Active` 11/0, `Nselect` 12/0, `Pselect` 13/0, `LIG` 16/0, `LISD`
17/0, `V0` 18/0) from `asap7_TechLib.layermap` in the same directory. Below M1
the model carries `lig`/`lisd` with the deck's own conduction rules (`LIG` and
`LISD` conduct where they overlap; `V0` joins either to M1), because that is
the path a tap takes from diffusion up to a rail. Label layers are the
`<metal>/251` pin-text layers the stream actually carries (measured counts in
the report's `provenance.label_layers`).

**Gate-to-LIG is deliberately not modelled, and the gates are disclosed.**
ASAP7 draws gates as full-height stripes cut by `GCut` (10/0) and lands `LIG`
directly on the gate. A `klt erc` spec on the pinned klt 0.9.0 cannot subtract
the cut, so a gate-to-LIG via makes the uncut stripes bridge the LIG bars on
both rails: measured on this layout, that collapses VDD and VSS into one net
(`erc.supply_short`) and all 46 gates into one net — the documented klayout-tools
#4610 limitation. The supply run therefore declares no gate-to-metal via and
discloses every resulting `erc.floating_gate` through the spec's
`floating_gate_allowed` key (klayout-tools #4820): the
gates move to `erc_coverage.inapplicable` with reason `floating_gate_disclosed`,
visible in the report, not silently passed. This is a disclosure of a model
limitation only — it is not a claim that gate connectivity is proven: the
docs direct that question to `klt lvs`, and the counter's own LVS record
(`flow/smoke/records/2026-11-15/lvs.json`) is `mismatch` on this same GDS
(bulk-tie assumption, per-cell supply fragmentation and topology findings,
classified in `flow/smoke/analysis/2026-11-05-lvs.md`), so gate connectivity
currently has no passing verdict anywhere.

**Ties.** The tapcell master (`TAPCELL_ASAP7_75t_R`, 20 tapcells + 20 endcaps
in `par.json`) draws a real double tie: an n-well half (well 1/0 ∩ Nselect
12/0, contacted Active → LISD → V0 → M1 rail) and a p-substrate half
(Pselect 13/0 outside the well, same contact chain). The two `ties[]` entries
follow the tiers document's order of preference — the strongest form that the
stream can express:

1. `nwell` — **drawn** `well_layer: "1/0"` with the tap narrowed by PDK marker
   (`tap_layer: "11/0"`, `tap_requires: ["12/0"]`): the n-well tap diffusion
   is exactly `Active ∩ Nselect` inside the well, so the narrowing removes
   every PMOS source/drain (they are Pselect) and the check is an ordinary,
   geometrically-derived pass — no caller assertion anywhere.
2. `psub` — `well_layer: null` with `well_complement_of: "1/0"`: ASAP7 draws
   no p-well/substrate layer (P_SUB exists only as pin text 3/251), so the
   substrate is the top-cell extent minus the drawn wells, derived from the
   stream rather than hand-asserted. The tap is narrowed the same way
   (`Active ∩ Pselect`), which removes every NMOS source/drain (they are
   Nselect). Because the *well side* of this tie rests on an assertion, the
   report lists it under `erc_coverage.checked_by_well_assertion` — a
   disclosed, strictly-weaker-on-the-well-side claim, per the tiers document.

Grounding measurements (pinned klt 0.9.0's own KLayout, on the committed GDS):
the drawn wells merge into 5 row strips and every one contains an n-well tap;
`Active ∩ Nselect ∩ well` yields 20 tap sites while excluding 80 PMOS
source/drain actives; `Active ∩ Pselect` outside the wells yields 20 tap sites
while excluding 88 NMOS source/drain actives; the wells cover 16.1% of the
top-cell extent, so the complement substrate is far from the degenerate
whole-die assertion. Falsification controls (not committed; same layout and
spec otherwise): removing `tap_requires` from `nwell` makes klt skip the tie
as `degenerate_tap_declaration` (`erc_status: clean_partial`), and pointing
`nwell` at VSS instead of VDD reports `erc.missing_tie` on all 5 well strips —
the check measures the drawn tap-to-rail connection, it does not pass by
construction.

## The 2026-11-21 run

Exact command (from the repo root, pinned klt through a throwaway `uvx`
environment; the host tool is never used):

```
uvx --python 3.12 --from "klayout-tools==0.9.0" klt erc --deck asap7 --format json \
  flow/smoke/records/2026-11-15/layout/counter.gds flow/erc/supply.spec.json \
  > flow/erc/records/2026-11-21/erc-supply.json
```

Exit code 4 (the report's top-level `status` is `not_checked`) is the antenna
half: no ASAP7 antenna-ratio table exists on any klt (klayout-tools #4090), so
every antenna level is skipped with `missing_antenna_pdk`. It is the same
verdict shape as the smoke flow's antenna-scoped record and carries no signal
about the supply half, whose verdict is `erc_status`.

Inputs and tool, as recorded in the report's own provenance:

| what | value |
| --- | --- |
| klt | 0.9.0 (`klayout-tools==0.9.0`, git `5dbbad05…`, KLayout 0.30.13) |
| layout | `flow/smoke/records/2026-11-15/layout/counter.gds`, sha256 `bb422342…` |
| spec | `flow/erc/supply.spec.json`, sha256 `5c8033e0…` |
| deck | `asap7` (released, sha256 `5c58a50e…`) |

### Read against tiers item 11

- **Islands:** VDD `matched_islands: 1`, VSS `matched_islands: 1` — each supply
  resolves to exactly one labelled electrical island (expected 1, declared
  count default).
- **Findings:** `erc_finding_count: 0`. Zero `erc.unconnected_net`, zero
  `erc.supply_short`, zero `erc.missing_tie`.
- **Ties actually checked, not skipped:** `erc_coverage.checked` contains
  `erc.missing_tie:["nwell"]` and `erc.missing_tie:["psub"]`,
  `missing_tie_checked: true`, `erc_coverage.skipped` is empty — neither tie is
  degenerate. `psub` is additionally named in `checked_by_well_assertion`
  (its well side is the complement assertion, as disclosed above).
- **Connectivity verdict:** `erc_status: clean` (graded on `erc_findings`
  alone, which is exactly the three rule families item 11 names).
- **Disclosed, not passed:** all 46 `erc.floating_gate` ids are in
  `erc_coverage.inapplicable` with reason `floating_gate_disclosed`
  (klayout-tools #4610; see above), and the antenna half is `not_checked`
  (klayout-tools #4090).

### What the core run must add (#31)

- Reuse this spec as-is; the core's `par.json` strap and stripe layers must be
  re-checked against the stackup (M1–M6 covered here), and the run recorded
  under `records/<date>/` beside this one.
- Item 11's LVS half is separate: the item-4 LVS report's
  `power_connectivity.status` must be `match`. The pinned klt 0.9.0 cannot
  produce that on the gate-level Verilog FinFET route; the fix in
  klayout-tools#5757 merged 2026-11-17, after the v0.9.2 tag, so it reaches
  this repo only through a later klt release and a pin decision (#31 tracks
  it). Until then the ERC supply evidence here is the half of item 11 that
  survives.
