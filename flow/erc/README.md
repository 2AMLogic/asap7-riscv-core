# `klt erc` supply evidence (item 11, structural power delivery)

This directory owns the **supply-scoped** `klt erc` spec for this repo, first
exercised on the routed counter layout (#226) to measure what the pinned tool
can check before the routed-core run (#31). The smoke flow's own
ERC run (`flow/smoke/run.sh` step 5) stays antenna-scoped and unchanged; the
two runs are separate evidence, not replacements for each other.

## Files

- `supply.spec.json` — the supply spec: VDD and VSS as `nets[]` entries with
  `"kind": "supply"`, a stackup covering every PDN layer the counter's
  `par.json` reports, and two `ties[]` entries (choices below). Every released
  klt (0.9.0 and 0.9.2) accepts it; it stays byte-identical.
- `supply-common-substrate.spec.json` — the same spec plus a top-level
  `"common_native_substrate": true` declaration, for engines carrying the
  klayout-tools #7143 fix (see the 2026-11-23 section). Released klts reject
  the key, so it is a separate file, not an edit of the base spec.
- `records/<date>/erc-supply.json` — the committed report of a run, exactly
  as the klt that produced it wrote it (each record's `provenance.klt_version`
  names the tool; the flow's klt pin is the one ratified in `spec/core.md`
  (decision 0012), read by `flow/lib.sh`'s `spec_klt_pin`, and is not changed
  by this directory — a record's own `tool-versions.txt` states what ran for
  that record, not the pin). Append-only: a later run adds a new dated
  directory, never edits one.

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
- **Findings.** The net-connectivity checks for VDD and VSS produced zero
  `erc.unconnected_net` findings. The two tie checks produced zero
  `erc.missing_tie` findings. The report records `erc_finding_count: 0`
  and `erc_status: clean` for the checks it ran.
- **Ties actually checked, not skipped:** `erc_coverage.checked` contains
  `erc.missing_tie:["nwell"]` and `erc.missing_tie:["psub"]`,
  `missing_tie_checked: true`, `erc_coverage.skipped` is empty — neither tie is
  degenerate. `psub` is additionally named in `checked_by_well_assertion`
  (its well side is the complement assertion, as disclosed above).
- **Supply-short coverage.** The report lists `erc.supply_short` under
  `erc_coverage.inapplicable` with reason `substrate_continuity_not_modelled`.
  The `psub` tie uses `well_complement_of: "1/0"` to locate substrate taps.
  klt 0.9.0 does not trace electrical paths through that substrate. A short
  through the declared stackup can produce a finding, as in the gate-to-LIG
  experiment above. A VDD–VSS short through the substrate remains unchecked,
  so this run leaves item 11's supply-short clause unmet.
  [Upstream substrate-continuity issue](https://github.com/2AMLogic/klayout-tools/issues/5334).
- **Other coverage limits.** All 46 `erc.floating_gate` ids are in
  `erc_coverage.inapplicable` with reason `floating_gate_disclosed`
  (klayout-tools #4610; see above), and the antenna half is `not_checked`
  (klayout-tools #4090).

### What the core run must add (#31)

- Check the stackup against the core's own `par.json` strap and stripe layers
  and record the core run under `records/<date>/`. Item 11 needs evidence
  that the core run evaluated supply shorts through the substrate.
- Item 11's LVS half is separate: the item-4 LVS report's
  `power_connectivity.status` must be `match`. The pinned klt 0.9.0 cannot
  produce that on the gate-level Verilog FinFET route; the fix in
  klayout-tools#5757 merged 2026-11-17, after the v0.9.2 tag, so it reaches
  this repo only through a later klt release and a pin decision (#31 tracks
  it).

## The 2026-11-22 probe (klt 0.9.2)

The substrate-continuity ERC work behind the 0.9.0 shortfall above shipped
in a released klt: #5334 closed as completed with the engine in v0.9.2
(tag `046ba746`, PyPI 2026-11-14; release cut tracked by klayout-tools
#5606). This issue is the probe for exactly that capability, so the same
spec — byte-identical, same sha256 — was re-run on the same committed GDS
with the newest released klt. The two records differ only in klt; even the
deck content hash is unchanged, so every delta below is engine-side.

```
uvx --python 3.12 --from "klayout-tools==0.9.2" klt erc --deck asap7 --format json \
  flow/smoke/records/2026-11-15/layout/counter.gds flow/erc/supply.spec.json \
  > flow/erc/records/2026-11-22/erc-supply.json
```

Exit code 4, same verdict shape as the 0.9.0 run (the antenna half; see
below). One CLI change on 0.9.2: `--validate-spec` no longer combines with
`--deck` (it reads no layout), so the spec was validated bare — still valid,
same counts (9 stackup, 8 vias, 2 nets, 2 ties).

| what | value |
| --- | --- |
| klt | 0.9.2 (`klayout-tools==0.9.2`, git `046ba746…`, KLayout 0.30.13) |
| layout | `flow/smoke/records/2026-11-15/layout/counter.gds`, sha256 `bb422342…` (unchanged) |
| spec | `flow/erc/supply.spec.json`, sha256 `5c8033e0…` (unchanged) |
| deck | `asap7` (released, sha256 `5c58a50e…` — unchanged) |

### Read against tiers item 11

- **Unchanged from 0.9.0:** VDD and VSS each resolve to one labelled island
  (`matched_islands: 1`); zero findings (`erc_status: clean`,
  `erc_finding_count: 0`); both ties checked with an empty `skipped` and
  `psub` still named in `checked_by_well_assertion`; all 46 gates disclosed
  `floating_gate_disclosed`; and the antenna half still skips every level
  `missing_antenna_pdk` (no ASAP7 antenna-ratio table on 0.9.2 either), so
  the top-level `status` stays `not_checked` with exit 4.
- **The supply-short disclosure was upgraded, not lifted.** 0.9.0's blanket
  `substrate_continuity_not_modelled` is replaced by
  `substrate_isolation_undecidable` with a `missing` list naming the two
  affordances the engine would accept: drawn substrate tap geometry to join
  through, or a `ties[].isolation_boxes` assertion. Per the 0.9.2 engine
  (klayout-tools #5343), the substrate path is *evaluated* only where a deck
  declares `substrate_isolation` (gf180mcu, sky130, sg13g2 do; asap7 does
  not) or the spec asserts it.
- **Neither affordance is honestly usable on this layout.** The stream does
  draw substrate tap geometry — the 20 `TAPCELL_ASAP7_75t_R` masters carry
  the contacted n-well and p-substrate ties measured above — yet the engine
  still reports "no drawn substrate tap geometry to join through"; its
  parenthetical ("asap7 cells draw no substrate or well tie") describes the
  standard-cell family, not this stream. That exact friction — the message
  does not distinguish a tapped stream from an untapped one, and a shared
  native substrate with no isolated p-well boxes cannot be declared without
  inventing isolation geometry — is
  [klayout-tools #6948](https://github.com/2AMLogic/klayout-tools/issues/6948),
  which supersedes the closed #5334 as the live upstream for this path. It
  was open when this run was made and closed completed 2026-11-22T07:54Z,
  hours afterwards; its fix is in no released klt (no release after v0.9.2
  as of 2026-11-23), so it does not change the measurement here.
  Asserting `ties[].isolation_boxes` here would claim isolated substrate
  bodies this layout does not have, and `nets[].same_net_as` (the third
  0.9.2 affordance) would suppress a VDD–VSS pair that must stay distinct —
  both change the physical assertion to buy a pass, which this issue
  forbids.
- **Verdict.** Item 11's substrate-path supply-short clause remains unmet on
  the newest released klt, now with a measured, tool-stated cause (the
  `missing` list) and a linked tool issue (#6948, since closed and awaiting
  a release). A relevant side effect for
  #31: 0.9.2's `klt signoff` item 11 (#5346) grades a
  `substrate_isolation_undecidable` citation `unmet` with the run's own
  `missing` list echoed into
  `detail.power_delivery.substrate_isolation_missing` — a core-run citation
  cannot read `met` on this path until #6948 is resolved and the fix
  released and pinned here.

### What the core run must add (#31) — updated by this probe

- The blocker chain is now: klayout-tools #6948 (evaluate a declared common
  native substrate on asap7; closed completed 2026-11-22, in no release yet)
  → a klt release carrying it → a repo pin decision adopting that release.
  The release is upstream work; the pin
  decision is out of this issue's scope (this issue does not change the
  pin). Until all three land, this 0.9.2 record is the evidence ceiling for
  the probe.
- The LVS half is unchanged: klayout-tools#5757's `power_connectivity` fix
  is still outside any release — no PyPI version after 0.9.2 as of
  2026-11-22 (the fix merged 2026-11-17, after the 0.9.2 tag).

## The 2026-11-23 pre-release probe (klt main @ `85bb426402`)

The #6948 fix landed on klayout-tools main as PR #7143, "fix(erc): evaluate a
declared native substrate through drawn taps" (merge commit `85bb426402`,
2026-11-22T07:54Z, hours after the 0.9.2 record above). No klt release
carries it (PyPI still ends at 0.9.2 as of 2026-11-23), and its own test
table and the #6948 curator verification used only synthetic flat-top
fixtures — never a placed-and-routed standard-cell stream with the taps
drawn inside `TAPCELL` instances. Before #31 waits on a release-and-pin
cycle, this probe answers the prior question on the real counter stream:
does the fix actually lift the substrate-path supply-short clause here?

Two runs, same engine (a throwaway `uvx` environment built from the merge
commit; the host tool and the repo pin are untouched). The **control** keeps
the byte-identical base spec; the **declaration run** uses
`supply-common-substrate.spec.json`, which adds only a top-level
`"common_native_substrate": true`:

```
uvx --python 3.12 --from "klayout-tools @ git+https://github.com/2AMLogic/klayout-tools@85bb426402746e8f22a183db4ecba5b1e8504dba" klt erc --deck asap7 --format json \
  flow/smoke/records/2026-11-15/layout/counter.gds flow/erc/supply-common-substrate.spec.json \
  > flow/erc/records/2026-11-23/erc-supply.json
# control: same command with flow/erc/supply.spec.json \
  > flow/erc/records/2026-11-23/erc-supply-control.json
```

Both exit 4 — the antenna half again (`missing_antenna_pdk`, klayout-tools
#4090), the same verdict shape as every earlier record. One environment
drift to disclose: the git environment resolved KLayout 0.30.14, where the
released-klt runs used 0.30.13. Deck and layout hashes are unchanged and the
control's connectivity verdicts are identical to 0.9.2's, so the drift
carries no observed signal, but it is stated here rather than left silent.

| what | value |
| --- | --- |
| klt | `0.9.3.dev3067+g85bb42640274` (git `85bb426402…`, KLayout 0.30.14) |
| layout | `flow/smoke/records/2026-11-15/layout/counter.gds`, sha256 `bb422342…` (unchanged) |
| spec | declaration run: `supply-common-substrate.spec.json`, sha256 `866115fa…`; control: `supply.spec.json`, sha256 `5c8033e0…` (both as committed) |
| deck | `asap7` (released, sha256 `5c58a50e…` — unchanged) |

### Control: engine-only delta

The base-spec run reproduces the 0.9.2 connectivity verdicts exactly — VDD
and VSS one island each, zero findings, both ties checked, nothing skipped,
`erc.supply_short` still `substrate_isolation_undecidable` — but the
`missing` list is rewritten and now names the affordance the fix added:
`"declare ties[].isolation_boxes for isolated regions, or
common_native_substrate: true for a shared native substrate"`. So the
engine-side change alone changes nothing for this stream; only the
declaration does.

### Declaration run: the substrate path is now checked

With `common_native_substrate: true`, `erc.supply_short` and
`erc.supply_short.substrate` both move into `erc_coverage.checked`, and the
substrate check is listed in `checked_by_assertion` — a disclosed,
assertion-backed check, the same epistemic tier the tiers document already
accepts for `psub`'s `checked_by_well_assertion`. Zero findings
(`erc_status: clean`), VDD and VSS still one island each, ties still
checked, nothing skipped. Provenance records the declaration
(`common_native_substrate: true`) and the derived body structure: one
substrate body `vsubs` tied by `psub`, and the five drawn n-well strips tied
by `nwell` — the same five row strips the 2026-11-21 grounding measured by
hand.

**Why this declaration is honest where the 0.9.2 affordances were not.**
`isolation_boxes` would assert isolated substrate bodies this layout does
not have, and `same_net_as` would suppress a VDD–VSS pair that must stay
distinct — both change the physical assertion to buy a pass. The
native-substrate declaration asserts the opposite of isolation: one shared
substrate body under the whole top cell, which is the physical arrangement
of this bulk process (drawn wells cover the measured 16.1%; the substrate is
the complement). It asserts nothing about whether VDD and VSS are shorted —
it is exactly what lets the engine *test* that they are not. Upstream's own
falsification table shows a tapped common-substrate rail short is reported
(exit 3), and the stream-side control below confirms the taps are measured,
not assumed.

**Falsification control (not committed; same layout and engine otherwise).**
Flipping the `psub` tie's declared `net` from VSS to VDD in the variant spec
turns the run to exit 3 with one `erc.missing_tie` violation: "well/tub tap
is not connected to declared net 'VDD'" — the 20 drawn substrate taps are
measured as connected to their VSS rails, so the declaration-enabled check
follows the drawn tap-to-rail connection and does not pass by construction.
On the base spec the same flip was a no-op for the substrate question (the
check never ran there).

**Released klts reject the key.** `klt erc --validate-spec` and the run
itself on both 0.9.0 and 0.9.2 refuse `common_native_substrate` with the
structured error "unknown field … a key from a newer klt release" (exit 1).
That is why the declaration lives in a separate spec file and
`supply.spec.json` stays byte-identical: every record before this one, and
anyone re-running them on the pinned klt, keeps a spec that tool accepts.

### Read against tiers item 11

- On the engine carrying the #6948 fix, the counter now satisfies the
  supply-short clause's measurable form: both supplies one island each,
  zero `erc.unconnected_net`, `erc.supply_short` (metal and substrate) and
  `erc.missing_tie` findings, ties checked, and the substrate short check
  *evaluated* rather than skipped — with its assertion disclosed in the
  report itself. Upstream's item-11 grader (klayout-tools #5346) grades
  this shape `met` with `by_assertion: true`.
- This is **pre-release evidence**, not a pin-tool record: the engine is a
  git commit, outside every released klt. The 0.9.2 record remains the
  released evidence ceiling, and the probe's remaining wait is unchanged in
  kind — release, then pin decision — but it is now de-risked: the fix is
  verified against a real routed stream, instance-internal `TAPCELL` taps
  included, before either step.
- The antenna half is unchanged (`not_checked`, klayout-tools #4090) and
  out of this supply-scoped run's scope, as before.

### What the core run must add (#31) — updated by this probe

- The chain is unchanged but its first link is now verified on a real
  stream: klayout-tools #6948 (closed completed; fix on main @ `85bb426402`,
  unreleased) → a klt release carrying it → a repo pin decision adopting
  that release. When the pin decision lands, the core run should use the
  variant spec (`supply-common-substrate.spec.json` becomes the spec; the
  two files merge at that point) and check the stackup against the core's
  own `par.json` strap and stripe layers.
- The LVS half is unchanged: klayout-tools#5757's `power_connectivity` fix
  is still outside any release (no PyPI version after 0.9.2 as of
  2026-11-23).
