# 0015 — The 2026-11-14 core netlist is the verification DUT; gate-level evidence regenerated; item 9 re-attested

**Status:** adopted 2026-11-15. Closes the verification half of issue #122; the
attestation half (item 1) is measured and **deferred with cause** — see
"Deferred: the item-1 tail" below. Follows `spec/decisions/0014-item-9-check-gate-and-lib-sh-attestation.md`'s
form and its append-only rule (operator ruling r7-q12, issue #65): results and
attestations are never deleted or rewritten; inputs and generators may change
with a superseding record. ASAP7 is a predictive PDK; nothing here is
fabricated or measured on silicon, and every figure is a tool result against a
predictive model.

**Problem.** PR #119 (merge `bcdbecd`, 2026-11-14) landed
`flow/core/records/2026-11-14/` — a core netlist that differs from the one every
consumer cited: it drives the 226 constant `assign` statements with tie cells
(2497 `TIEHIx1_ASAP7_75t_R` + 6847 `TIELOx1_ASAP7_75t_R`, from the two runs'
`instance_counts_by_type`; every other cell type unchanged), so the two netlists
are not interchangeable. `verification/core/archtest_common.py`'s `NETLIST`,
`verification/core/runner.py`'s docstring, `rtl/inventory.json` and
`verification/README.md` all still cited `2026-11-03`, whose only gate-level
functional evidence was `verification/records/2026-11-06/` (netlist
`sha256:754ee873…`). The newer netlist had a synthesis record but no testbench
result — a gap against this repo's "no claim without a testbench" rule the
moment anything treats it as the accepted netlist (#28, P&R, being the first
consumer). `evidence/item1.json` additionally pins `flow/core/synth.sh` at a
hash now three changes stale (`40982cb1…` at `02083a7`; the file is `acc40874…`
after #114, #119 and #105's `--check` target-selection fix) — drift measured as
pre-existing on `main` and still ungated (there is no `--attest 1 … --check`
step; decision 0014 explicitly leaves it undecided).

**Decision.**

1. **`flow/core/records/2026-11-14/netlist.v` (sha256 `e559a592…`) is the
   committed netlist the harness simulates.** `archtest_common.py`'s `NETLIST`
   and `runner.py`'s docstring cite it. No `CELL_GROUPS` or
   `verification/tool-versions.txt` change: both tie cells are defined by
   `asap7sc7p5t_SIMPLE_RVT_TT_201020.v` (modules at its lines 1195 and 1210),
   whose sha256 `849946d9…` is byte-equal to the
   `asap7_cells_SIMPLE_RVT_TT_201020_sha256` pin, and that group is already one
   of the five `CELL_GROUPS` fetched for the gate-level run. Verified live: the
   gate run below elaborates and simulates the tie-cell netlist with the five
   pinned groups, no missing-module error.

2. **The gate-level evidence is regenerated, live, in a new dated record.**
   `verification/run.sh --core --gate` on a pinned host (Icarus 13.0, Verilator
   5.050, Python 3.12.3) produced `verification/records/2026-11-15/gate-core-archtest.json`:
   **72 programs run, 0 failed**, every program matching the Sail signature,
   `C-cebreak-01` excluded with its decision-0011 reason, and `netlist.sha256`
   `e559a5923d6be0a79645ad32bb7c64e82b5c54c3bcf144bb769a7827e5ee22ad` — derived
   by `runner.py` from `NETLIST` itself, never hand-edited. The matching
   negative control (`--negative-control`, same host, same day) is
   `verification/records/2026-11-15/gate-core-archtest-negative-control.json`,
   passing only because the deliberately flipped expected word failed (`I-add-01`
   reports a signature mismatch and the run exits as an expected failure, exit 0).
   `verification/records/2026-11-06/` is untouched: it stays as append-only
   evidence for the old netlist.

3. **Item 9 is re-attested over the edited testbenches**, by the two-step
   change of decision 0014. The envelope this PR supersedes is `main`'s current
   one, produced at `d8087b0` (2026-11-15T10:42:25Z, #105's run.sh-drift
   re-attest); it is retained byte-for-byte **first**, at
   `evidence/records/item9-2026-11-15-d8087b0.json`. Decision 0014 names
   retentions by the production **date** of the envelope they keep; two
   envelopes produced the same day need disambiguation, so this retention
   carries the producing commit's short sha as a suffix — the plain
   `item9-2026-11-15.json` name is already taken by the `556b51a` retention
   that `main`'s history holds. The regeneration
   (`uvx --python 3.12 --from "klayout-tools==0.8.0" klt signoff --attest 9
   --inventory attest/item9.json -o evidence/item9.json`) re-ran the live RTL
   cold start (`verification/run.sh --core`) on the tree with the edited
   testbenches: **72 of 72 riscv-arch-test I/M/C programs, 0 failures, exit 0**
   — reconfirming the RTL harness on the same tree; `C-cebreak-01` remains
   excluded with its decision-0011 reason. The new envelope is `status: pass`,
   15/15 checks, and `klt signoff --attest 9 --inventory attest/item9.json
   --check evidence/item9.json` exits 0.

4. **The block manifest and tier record are unchanged.** The manifest binds
   each item citation to its *input* hash: item 9's input is
   `attest/item9.json`, which this decision does not edit, so the manifest's
   item-9 pin does not move; a fresh render of the tier record
   (`klt signoff --manifest … --format json`) is byte-identical to the
   committed `manifests/asap7-riscv-core.signoff.json` even with the new
   envelope, because the item-9 citation carries only the inventory hash and
   the check counts (still 15/15). `t1_met_count` stays 3 of 11. Measured, not
   assumed: the render was diffed against the committed record on the PR
   branch after the rebase over `main`'s own envelope changes (exit 3 — the
   committed tier state has unmet items — with byte-identical output).

**Deferred: the item-1 tail.** The issue's remaining acceptance criteria —
re-pointing `rtl/inventory.json` at the new netlist, regenerating
`evidence/item1.json`, moving the manifest's item-1 `content_hash` pin to the
new inventory hash, and re-rendering the tier record — are **one coupled
edit** (the manifest pins the inventory's hash, and the envelope's freshness
check `flow/core/synth.sh --check` re-runs the synthesis and byte-compares
against the committed record). The inventory was re-pointed and the
manifest pin updated in this PR's working tree first, exactly as the issue
orders them; the regeneration was then attempted **three times on
2026-11-15** (twice by this PR's first builder session — once via
`klt signoff --attest 1 -o`, once as a bare `flow/core/synth.sh --check` with
`ASAP7_DIR` at the spec pins and `KEEP_SCRATCH=1` — and once more from a
fresh builder session at 2026-11-15T19:49Z, against a scratch ASAP7
checkout whose `rev-parse` heads equal the `spec/pdk-bringup.md` §1 pins) and
all three died the same way: `yosys did not complete within 300.0s … process
killed`, at the first `abc -liberty` pass of a generated module. This is not
this design and not load: the fleet already tracks it as
2AMLogic/klayout-tools#5814 (onset ~2026-11-15 00:00 UTC, trigger located in
worker provisioning, zero-CPU yosys↔abc pipe deadlock, design-independent — a
trivial counter design reproduces it) and 2AMLogic/klayout-tools#5800 (same
wedge, 300 s cap not configurable), consolidated into the open
2AMLogic/klayout-tools#5798. The same design completed on 2026-11-03 and
2026-11-14, so it is host-dependent, not a content failure. Landing the
inventory re-point without a fresh envelope would render item 1
`unmet, stale_evidence` and drop `t1_met_count` to 2 of 11 — re-measured
first-hand on this PR branch today (re-point + manifest pin edit, fresh render
read, both reverted) — so the inventory re-point and the manifest pin are
**reverted here** and land together with the envelope when a host can run the
synthesis again. The superseded item-1 envelope (produced at `02083a7`,
2026-11-03T10:10:58Z) is **not** retained in this PR — nothing supersedes it
yet; the tail PR performs the two-step change of decision 0014 in one commit.
`evidence/item1.json` still attests the 2026-11-03 netlist exactly as `main`
does today; its `synth.sh` drift remains pre-existing and ungated, and no
envelope was rewritten to hide it.

**Not decided here.** An `--attest 1 … --check` CI gate (decision 0014's "Not
decided here" list still governs); the append-only reading of in-place
envelope regeneration (issue #89); `--check`'s record selection beyond #105's
content-based fix (issue #105); the stale `README.md:15` core-netlist prose
and the item-10 re-attest it forces (issue #102); `#117`'s drift-message
formatting; #28's P&R and its `_CTS_BUFFER_CELLS` override; any change to the
core RTL, the arch-test set, the decision-0011 exclusion, the klt pins or the
ASAP7 pins; and the klayout-tools wedge itself (owned upstream by #5798).
