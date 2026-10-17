# 0006 — Core pin deferred to sky130-riscv-soc

**Status:** deferred 2026-10-17.

**Decision.** This repo adopts the core, configuration, upstream commit and sv2v conversion that
`sky130-riscv-soc` ratifies. As of 2026-10-17, `2AMLogic/sky130-riscv-soc#2` is open and that repo's
`spec/` holds only a README, so there is nothing to adopt. RV32IMC target / RV32EC fallback stands.

**Owner:** this repo's spec author. **Trigger:** `sky130-riscv-soc#2` closes with a pinned commit;
a follow-up record adopts it verbatim.

**Rejected:** ratifying a core pin independently (the repo rule is to share the pin).
