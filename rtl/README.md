# rtl

The core is the unmodified upstream CVE2 (`openhwgroup/cve2@d7f21568`), which is
**not vendored**: `flow/core/fetch.sh` downloads the file closure of `cve2_top`
listed in [`../reuse.lock.json`](../reuse.lock.json) and refuses any file whose
sha256 differs.

| File | Role |
|---|---|
| `cve2_rv32imc_wrapper.sv` | Configuration wrapper: `RV32E=0`, `RV32M=RV32MFast`, no debug module, no CV-X-IF. The only RTL authored here. |
| `inventory.json` | T1 item 1 attestation inventory for `klt signoff --attest 1`. |
| `cve2_clock_gate.sv` (fetched, not stored here) | Upstream clock-gating module, pulled in by the closure fetch: source of the one inferred latch — see the note below. |

Synthesis and the committed gate-level netlist: [`../flow/core/`](../flow/core/).
Decision record: [`../spec/decisions/0010-sv2v-and-core-closure.md`](../spec/decisions/0010-sv2v-and-core-closure.md).

## The one inferred latch: `cve2_clock_gate`

Synthesis of the core infers exactly one level-sensitive latch: the gate-enable
`clk_en` inside `cve2_clock_gate`, the upstream clock-gating module fetched from
the pinned upstream file `rtl/cve2_clock_gate.sv` (`reuse.lock.json`,
`"mode": "fetched"`). While `clk_i` is low the module latches
`OR2(en_i, scan_cg_en_i)` into `clk_en`, then ANDs that with `clk_i` to form the
gated clock — hence Yosys infers a negative-enable latch. In the committed
netlist of record it appears not as a cell instance but as `reg clk_en;`
(`flow/core/records/2026-11-03/netlist.v:107562`) and the netlist's only
`always` block, `always @* if (!clk_i) clk_en = _0_;`
(`flow/core/records/2026-11-03/netlist.v:107573-107574`); `synth.json` counts
it as one generic `$_DLATCH_N_` instance, the only `$`-prefixed entry in
`instance_counts_by_type`.

`cve2_rv32imc_wrapper.sv` — the only RTL authored in this repository —
instantiates `cve2_top` only and cannot affect this construct, and the pinned
upstream sources must not be edited, so the latch is mapped at synthesis time:
`flow/core/synth.sh` passes `latch_map.negative` to `klt synthesize`, mapping
the `$_DLATCH_N_` primitive onto `DLLx1_ASAP7_75t_R`, the pinned library's
negative-enable latch (transparent while `CLK` is low — same polarity, pins
`CLK`/`D`/`Q`; from `asap7sc7p5t_SEQ_RVT_TT_220101`, already in the resolved RVT
Liberty and in `verification/core/archtest_common.py`'s `CELL_GROUPS`).
Yosys's `latch_inferred` warning is emitted during `proc`, before that techmap
runs, so it still appears in a mapped run — expected, not a defect.
