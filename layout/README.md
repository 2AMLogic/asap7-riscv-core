# layout

The committed layout artifact of this block (T1 item 2). ASAP7 is a
predictive PDK: this is layout only, never fabricated, and no timing is
claimed here — STA is a separate flow, and DRC/LVS against the pinned deck
are recorded separately.

- `cve2_top.gds` — routed GDS, top cell `cve2_rv32imc_wrapper` (the RV32IMC
  wrapper around the unmodified CVE2 core), placed and routed by
  `klt place-and-route` from the committed gate-level netlist
  (`flow/core/records/2026-11-20/netlist.v`, decision 0004 floorplan:
  60 % utilisation target, aspect 1.0, single block, no macro).
  sha256 `abaf794b569e5956e5f4340e1ffc5ae5e6395b087ef7cf91f83591d3cec407e1`.

## Reproduce

Reproducible from a clean checkout with:

- the pinned ASAP7 checkout of `spec/pdk-bringup.md` section 1 (~3 GB,
  `asap7_pdk_r1p7` and `asap7sc7p5t_28` submodules initialised),
- `openroad` on `$PATH` (required by `klt place-and-route`; build
  `26Q3-1510-g6cb3f2b704` — commit `6cb3f2b704` of
  `The-OpenROAD-Project/OpenROAD`, recorded in
  `flow/core/records/2026-11-22/tool-versions.txt` — produced the committed
  GDS),
- `uvx` and network egress (the pinned `klt` `0.9.0` and `py7zr` are resolved
  automatically; writing a new dated record also queries `yosys -V` on `$PATH`
  for `tool-versions.txt`):

```
flow/core/par.sh <asap7-checkout> --check    # regenerates, validates, and byte-compares against HEAD:layout/cve2_top.gds
flow/core/par.sh <asap7-checkout>            # validates and writes a new dated record + layout/cve2_top.gds
```

Two independent full runs (2026-11-22, pinned `klt` 0.9.0, OpenROAD
`26Q3-1510-g6cb3f2b704`, seed 1) produced byte-identical GDS streams at the
sha256 above. The run's response and its tool/input pins are committed beside
this file's generator: `flow/core/records/2026-11-22/par.json` (`status: ok`,
`stage_reached: route`, `power.pdn: true`,
`power.tapcell_master: TAPCELL_ASAP7_75t_R`) and
`flow/core/records/2026-11-22/tool-versions.txt`. Predicted areas from that
response: die 4763.62 µm², core 4465.56 µm², utilisation 63.49 %.

## DRC (T1 item 3): not clean — every marker waived or disclosed

`flow/core/drc.sh` runs `klt drc --engine klayout` on the committed GDS
(read from Git, byte-bound to the par record's pin) against the pinned deck
(decision 0012: `sha256:14f146f0…e0f12d13`, 267 categories). The first
record is `flow/core/records/2026-11-24/drc.json`: **`status: violations`,
20,540 markers in 11 rule ids**, every marker attributed by measurement in
[`flow/core/analysis/2026-11-24-drc.md`](../flow/core/analysis/2026-11-24-drc.md).

ASAP7 is a predictive PDK; every figure is a tool result against the pinned
deck, never a silicon claim. Reproduce with `flow/core/drc.sh` (needs `uvx`
and network egress; the run raises klt's default 300 s timeout because a
core-sized stream needs it).

- **15,486 PDN-stack and router-fill markers** (`V4.M4.EN.1` 14,384,
  `V4.M5.EN.2` 232, `M3.S.2` 870; every `V4.*` bbox exactly 216 nm × 24 nm)
  and **2,741 router via-pad tips** (`M1.S.2`–`M1.S.5`) are router/PDN
  emissions of the pinned build whose upstream fixes are merged but
  unreleased (klayout-tools #7084, #7397): waived under
  [`layout/waivers/`](waivers/) with their supersession condition — the
  re-route at the bumped pin that #246 and #277 track.
- **20 router-emitted M4 markers off the deck's track grid**
  (`M4.AUX.1/2`, `M4.W.3`) are waived the same way; the gap is filed
  upstream as klayout-tools #7817.
- **2,293 `SDT.ACTIVE.AUX.2` markers** are the pinned cell library's own
  shipped geometry (all inside `BUFx4`/`BUFx2`/`OAI22xp33` instances,
  0 outside): **disclosed, not waived**, by
  [decision 0021](../spec/decisions/0021-sdt-active-aux-2-shipped-cell-disclosure.md)
  per the klayout-tools #4530 ruling.

Deck coverage, quoted verbatim from the record's `coverage` block:
`layers_in_stream_without_rules: []`, `rules_skipped: []`,
`deck_scope: []`, `unchecked_rules: []`, plus 67 `unmodeled_rules` listed
in the record (the known decision-0005 unchecked classes — track/net/
corner/grid predicates, FEOL/MOL increments, PAD — are stated by the claim,
not hidden behind the counts). **T1 item 3 stays `unmet`** until a clean
report exists; the manifest cites this report so the verdict is graded
against committed evidence (`manifests/asap7-riscv-core.signoff.json`).
