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
