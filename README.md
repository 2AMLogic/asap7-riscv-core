# asap7-riscv-core

Place-and-route of an Ibex/CVE2-class RISC-V core on
[ASAP7](https://github.com/The-OpenROAD-Project/asap7), a **predictive**
7 nm FinFET PDK — designed by AI agents driving
[klayout-tools](https://github.com/2AMLogic/klayout-tools) and the
open-source cocotb + Icarus, Yosys and OpenROAD flow.

**ASAP7 is a predictive PDK, not a foundry process.** It models a 7 nm
FinFET node for research and teaching; no fab manufactures it. This block is
**layout, DRC and timing only, and it is never fabricated.** Every result in
this repo is a tool result against a predictive model — there is no silicon,
no shuttle and no measurement at the end of the ladder.

**Status: core routed on ASAP7, first DRC record committed (not clean — every marker waived or disclosed); LVS and STA pending** (see [`spec/core.md`](spec/core.md) and the append-only records under `flow/core/records/`). The core is placed and routed: [`layout/cve2_top.gds`](layout/README.md) (top cell `cve2_rv32imc_wrapper`, the RV32IMC wrapper around unmodified CVE2) was produced by `flow/core/par.sh` from the committed gate-level netlist (`flow/core/records/2026-11-20/netlist.v`) at the pinned `klt` 0.9.0, OpenROAD `26Q3-1510-g6cb3f2b704`, seed 1, with two independent runs byte-identical — T1 item 2 is met (`flow/core/records/2026-11-22/par.json`, `status: ok`, `power.pdn: true`). The first core DRC record — [`flow/core/records/2026-11-24/drc.json`](flow/core/records/2026-11-24/drc.json), written by `flow/core/drc.sh` against the pinned deck of [decision 0012](spec/decisions/0012-pin-klt-0-9-0-and-ratify-asap7-drc-deck.md) (`sha256:14f146f0…e0f12d13`, 267 categories) — reports `violations`: **20,540 markers in 11 rule ids, every one attributed by measurement in [`flow/core/analysis/2026-11-24-drc.md`](flow/core/analysis/2026-11-24-drc.md)**. 18,247 are router/PDN emissions of the pinned build, waived under [`layout/waivers/`](layout/waivers/) with named upstream causes: 15,486 PDN-stack and router-fill markers (`V4.M4.EN.1`/`V4.M5.EN.2`/`M3.S.2`) and 2,741 router via-pad tips (`M1.S.2`–`M1.S.5`) whose fixes are merged upstream but unreleased (klayout-tools #7084, #7397 — they ride the next klt release that the pin bump #246 tracks, upstream #6930), and 20 router-emitted M4 markers off the deck's track grid (`M4.AUX.1/2`, `M4.W.3`, klayout-tools #7817, filed from this pass). The remaining 2,293 are the pinned cell library's own shipped `SDT.ACTIVE.AUX.2` geometry (all inside `BUFx4`/`BUFx2`/`OAI22xp33` instances): **disclosed, not waived**, by [decision 0021](spec/decisions/0021-sdt-active-aux-2-shipped-cell-disclosure.md) per the klayout-tools #4530 ruling. **T1 item 3 stays `unmet`** until a clean report exists; #277 sequences the re-route at the bumped pin. The counter smoke flow (`flow/smoke/records/2026-11-21/`, `par.json` `ok`, `lvs.json` `match`) carries the same families at placeholder scale ([analysis](flow/smoke/analysis/2026-11-21-drc.md), [2026-11-23 upstream recheck](flow/smoke/analysis/2026-11-23-upstream-disposition-recheck.md)). The `riscv-arch-test` suite runs against the `2026-11-14` netlist zero-delay with 72 of 72 tests passing and one test excluded by [decision 0011](spec/decisions/0011-c-cebreak-01-mtvec-not-writable.md) (`verification/records/2026-11-15/`; `verification/records/2026-11-06/` is the retained record of the same suite against the superseded `2026-11-03` netlist). Decision 0012 remains **proposed**, not yet ratified (#174 tracks the status wording).

**Built agent-native.** Every specification, decision record, testbench, and
line of documentation here is produced by AI agents working from a ratified
spec and an append-only evidence trail — not human-authored work that agents
merely assisted with. Verification is the product: every claim traces to a
recorded result. Where the agents hit friction with the open-source tooling —
most often [klayout-tools](https://github.com/2AMLogic/klayout-tools) — that
friction is filed as a public issue against the tool itself, so the fix
benefits everyone using ASAP7, not just this repo.

## Why this block, on this PDK

Every other fleet PDK is a planar node at 130–180 nm. ASAP7 brings
FinFET-era layout rules — quantized device widths on a fin grid, a fixed
gate pitch, and much tighter metal rules — that klayout-tools has never had
to check. A RISC-V core is a well-understood, mid-sized digital block, so it
is a good probe: when something fails, the cause is almost certainly the PDK
setup, the rule deck or the tools, not the design.

The PDK is also not in the fleet's `open_pdks` store, so bringing it up
under `klt` — technology files, layer map, cell library, a rule deck klt can
run — is part of this repo's work, and most of its early friction.

## Scope

- **In scope**: bringing ASAP7 up under `klt`; synthesis, floorplan,
  placement, clock-tree synthesis and routing of the core; DRC and LVS of the
  result; multi-corner STA.
- **Not in scope**: designing the core (it is used unmodified from a pinned
  upstream commit), caches or SRAM, an SoC around it, and anything that
  implies manufacture.
- **Core RTL**: the same upstream core and configuration that
  `sky130-riscv-soc` selects, so the two repos stress the tools with the same
  design on very different PDKs.

## Target specification (ratified in [`spec/core.md`](spec/core.md); summary below)

All frequencies are predicted by STA against ASAP7's predictive models.

| Parameter | Target | Fallback | Stretch |
|---|---|---|---|
| Core | RV32IMC, Ibex/CVE2-class, unmodified | RV32EC | — |
| Standard cells | ASAP7 7.5-track library | — | — |
| Predicted clock (post-route STA, slow corner) | 1 GHz | 500 MHz | 1.5 GHz |
| DRC | clean against the ratified ASAP7 rule deck under `klt` | clean with every waiver recorded | — |
| LVS | clean | — | — |

Maturity ladder: ASAP7 brought up under `klt` → spec ratified → core RTL
passing the architectural tests in simulation → synthesized → placed and
routed → DRC/LVS-clean → post-route multi-corner STA closed at the target.
**That is the end of the ladder; there is no fabrication step.**
**The core is placed and routed.** The [P&R record](flow/core/records/2026-11-22/par.json)
binds the synthesized netlist to the committed core GDS. The next rung requires
clean DRC and LVS. The [first core DRC run](flow/core/analysis/2026-11-24-drc.md)
reported 20,540 markers, and a matching core LVS report is still outstanding.

## Repo layout

```
spec/          ratified spec + decision records, including the PDK bring-up
rtl/           core configuration wrapper (the core is pinned upstream)
verification/  cocotb testbenches + architectural-test runs
flow/          ASAP7 smoke flow and its dated result records
manifests/     block manifest and the klt signoff verdict of record
attest/        klt --attest inventories; evidence/ holds the generated envelopes
layout/        GDS + DRC/LVS reports + STA reports (klayout-tools driven)
```

## Reproduce

Every committed result maps to one command below. All of them are tool results
against a predictive model; none is a measurement.

Pins these rely on: host simulators and Python in
[`verification/tool-versions.txt`](verification/tool-versions.txt) (iverilog
13.0, Verilator 5.050, Python 3.12) and cocotb in
[`verification/requirements.txt`](verification/requirements.txt); the ASAP7
commits in [`spec/pdk-bringup.md`](spec/pdk-bringup.md) section 1; and
`klayout-tools==0.8.0` for the signoff steps (decisions
[0008](spec/decisions/0008-item-6-not-applicable-and-signoff-pin.md) and
[0009](spec/decisions/0009-item-10-repo-hygiene-attestation.md)).

| Result | Command | Needs |
|---|---|---|
| Harness lint + cocotb test (placeholder DUT, no claim about the core) | `verification/run.sh` | pinned iverilog, Verilator, Python |
| Harness negative control (passes only if the broken assertion fails) | `verification/run.sh --negative-control` | same |
| `flow/smoke/records/2026-11-21/*.json` (ASAP7 smoke flow of record, `par.json` `ok`, `lvs.json` `match`; its DRC residuals are attributed in `flow/smoke/analysis/2026-11-21-drc.md`, not clean) | `RECORD_DATE=<new date> flow/smoke/run.sh <asap7-checkout>` | ASAP7 checkout at the `spec/pdk-bringup.md` pins; network for `uvx`; refuses to write into the existing dated directory |
| `manifests/asap7-riscv-core.signoff.json` (tier verdict of record) | `uvx --from "klayout-tools==0.8.0" klt signoff --manifest manifests/asap7-riscv-core.json --format json > manifests/asap7-riscv-core.signoff.json` | network for `uvx` |
| `evidence/item10.json` (repo-hygiene attestation) | `uvx --python 3.12 --from "klayout-tools==0.8.0" klt signoff --attest 10 --inventory attest/item10.json -o evidence/item10.json` | pinned iverilog and Verilator (the harness checks run) |

`--python 3.12` matters for the `--attest` command: `uvx` puts its own Python
first on `PATH`, `klt` runs the harness checks with that `PATH`, and
`verification/run.sh` refuses any Python other than the pinned 3.12.

Re-check the attestation without the simulators (the harness checks are shown
as `[SKIP]`, file hashes still verified):

```sh
uvx --python 3.12 --from "klayout-tools==0.8.0" klt signoff --attest 10 \
    --inventory attest/item10.json --check evidence/item10.json
```

The attestation hashes `README.md`, `LICENSE` and the workflow files, so after
editing any of them re-run the `--attest 10 ... -o` command above, regenerate
the signoff record, and commit both. CI (`.github/workflows/ci.yml` for the
harness, `.github/workflows/signoff.yml` for the record and attestation) fails
on a stale one.

## License

Apache License 2.0 — see [LICENSE](LICENSE).
