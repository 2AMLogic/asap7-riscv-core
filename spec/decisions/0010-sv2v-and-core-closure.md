# 0010 — sv2v adoption, CVE2 file-closure lock, and the T1 item 1 synthesis route

**Status:** adopted 2026-11-03. Resolves the sv2v deferral in [0007](0007-adopt-core-pin.md); builds on 0008 (klt pinned
at `klayout-tools==0.8.0`).

**Decision.**

1. **sv2v is adopted at `sv2v v0.0.13`**, the pin `2AMLogic/sky130-riscv-soc` now carries (`scripts/setup-env.sh`
   `PIN_SV2V`, release asset `sv2v-Linux.zip` sha256 `552799a1d76cd177b9b4cc63a3e77823a3d2a6eb4ec006569288abeff28e1ff8`).
   That is 0007's trigger; it is the same pin, not a second one. `spec/core.md` records it, and `flow/core/synth.sh`
   downloads the release asset into `flow/build/`, checks that sha256 and the reported version, and refuses otherwise.
   Nothing is installed on the host.
2. **SV route.** The pinned `klt` 0.8.0 reads `.sv` sources only through Yosys' native front end, which rejects the
   unpacked-array ports in `cve2_alu.sv`; no `sv_frontend` route exists in that release. The flow therefore converts
   the fetched closure with sv2v (the origin's `convert-cve2.sh` command, plus the wrapper) and hands the resulting
   single Verilog file to `klt synthesize`. No klt change is needed or waited on.
3. **The lock covers the whole closure.** The old `reuse.lock.json` hashed four files and could not cover the core.
   The `openhwgroup/cve2` entry is extended to the 32-file closure of `cve2_top` (all `rtl/*.sv`, the `prim_assert*`
   macro headers, `prim_ram_1p_pkg.sv`, `dv_fcov_macros.svh`, `LICENSE`, `syn/README.md`). The commit is unchanged
   and the four previous hashes are unchanged. The added entries equal the origin's lock; `fetch.sh` independently
   re-downloads every file at the pinned commit and fails on any sha256 mismatch. This extends, and does not change,
   the verbatim adoption in 0007. Upstream files are used unmodified; there is no fork.
4. **Configuration** is `rtl/cve2_rv32imc_wrapper.sv` (`RV32E=0`, `RV32M=RV32MFast`, no debug, no CV-X-IF).

**Evidence that `cve2_top` converts and synthesizes.** `flow/core/records/2026-11-03/`: sv2v converts the closure and
Icarus elaborates it; `klt synthesize` against the merged RVT-only SS `asap7sc7p5t_28` Liberty returns `status: ok`
(20441 instances, 2286.04 um^2 predicted-model area; `timing` is null, synthesis claims no timing). Re-running
`flow/core/synth.sh <asap7> --check` reproduces `netlist.v` byte for byte; the script strips its scratch path from
Yosys-internal net names so the output does not depend on where it ran. A corrupted lock hash makes `fetch.sh` exit 1.

**Item 1.** `rtl/inventory.json` is attested by `klt signoff --attest 1` into `evidence/item1.json` and cited by the
manifest; the envelope is never hand-edited. The netlist freshness check needs the pinned ASAP7 checkout, so it is
`local_only` (`--check` carries the committed outcome). The flow is open to a future record under a new date; the
inventory then names the new netlist and is re-attested.

**Tell the origin.** `sky130-riscv-soc` already carries the same 32-file closure, so nothing diverges; no action there.

**Rejected:** a second sv2v pin; installing tools on the host; relying on a klt `sv_frontend` route that the pinned
release lacks.
