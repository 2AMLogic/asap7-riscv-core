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

**Status: just opened, specification phase.** Nothing is designed yet.

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

## Target specification (DRAFT — engineering to ratify, see issue #1)

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
**That is the end of the ladder; there is no fabrication step.** **Current
position: pre-spec.**

## Repo layout

```
spec/          ratified spec + decision records, including the PDK bring-up
rtl/           core configuration wrapper (the core is pinned upstream)
verification/  cocotb testbenches + architectural-test runs
layout/        GDS + DRC/LVS reports + STA reports (klayout-tools driven)
```

## License

Apache License 2.0 — see [LICENSE](LICENSE).
