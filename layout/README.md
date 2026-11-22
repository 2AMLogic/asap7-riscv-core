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

Reproducible from a clean checkout with the pinned ASAP7 checkout of
`spec/pdk-bringup.md` section 1 (~3 GB, submodules initialised), network
egress and `uvx` (the pinned `klt` is resolved automatically):

```
flow/core/par.sh <asap7-checkout>            # writes the dated record and this GDS
flow/core/par.sh <asap7-checkout> --check    # regenerates the GDS and byte-compares
```

Two independent full runs (2026-11-22, pinned `klt` 0.9.0, seed 1) produced
byte-identical GDS streams at the sha256 above. The run's response and its
tool/input pins are committed beside this file's generator:
`flow/core/records/2026-11-22/par.json` (`status: ok`, `power.pdn: true`,
`power.tapcell_master: TAPCELL_ASAP7_75t_R`) and
`flow/core/records/2026-11-22/tool-versions.txt`. Predicted areas from that
response: die 4763.62 µm², core 4465.56 µm², utilisation 63.49 %.
