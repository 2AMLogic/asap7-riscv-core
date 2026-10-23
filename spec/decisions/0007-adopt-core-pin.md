# 0007 — Adopt the sky130-riscv-soc core pin

**Status:** adopted 2026-10-23. Resolves [0006](0006-core-pin-deferred.md).

**Decision.** This repo adopts, verbatim, the core, configuration and upstream commit that
`2AMLogic/sky130-riscv-soc` ratified in `spec/decision-records/0001-core-choice.md` (last changed in
`sky130-riscv-soc` commit `1e6c447d571e95f2aa4f8e29ae1ef30ab03bdaa8`, 2026-10-17):

- Core: CVE2 (`cve2_top`), RV32IMC (`RV32E=0`, `RV32M=RV32MFast`), no debug module.
- Upstream: `openhwgroup/cve2@d7f21568028a1114be663599bd42145dccf28928`.
- The pin and the sha256 of each listed file are recorded in the root `reuse.lock.json` (`fetched`
  import, same files and values as the origin's entry; checked against a scratch clone at that commit).

The RV32EC fallback in `spec/core.md` is unchanged. No RTL is vendored, converted, forked or modified
by this record; the core is used unmodified.

**sv2v stays deferred.** The origin has not pinned sv2v yet (its `docs/environment.md` says so). The
conversion this repo uses will be the origin's, once pinned. **Owner:** this repo's spec author.
**Trigger:** `sky130-riscv-soc` pins sv2v; a follow-up record adopts that pin verbatim.

**Trigger met:** `sky130-riscv-soc#2` closed on 2026-10-17 with the pinned commit above.

**Rejected:** vendoring the RTL now (no sv2v pin to convert it with, and out of scope for a pin record).
