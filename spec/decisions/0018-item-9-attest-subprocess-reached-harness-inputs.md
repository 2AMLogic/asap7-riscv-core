# 0018 — Item 9's inventory attests subprocess-reached harness inputs

**Status:** adopted 2026-11-17. Extends the boundary rule of
`spec/decisions/0016-item-9-attest-sourced-harness-inputs.md` from one reachability mechanism
(`source`/`import`) to two (subprocess invocation as well). Closes issue #178.

**Problem.** The closure walks behind #145 and #154 matched `source`/`import` patterns only, so a repo
file run as `python3 -I "$REPO/foo.py"` — or passed to an interpreter by an attested script — was
invisible to them. Six such files are reached from attested harness files; two were already attested,
four were not:

| repo file | invoked by (attested) | executed by item 9's `cold_start` (`verification/run.sh --core`)? |
|---|---|---|
| `verification/smoke/runner.py` | `verification/run.sh:92,98` | no — the `--core` branch `exit 0`s at `run.sh:84`, before the smoke branch at 88–99 |
| `verification/smoke/counter.sv` | `verification/run.sh:88` (`verilator --lint-only`) | no — same smoke branch |
| `flow/record_lib.py` | `flow/smoke/run.sh:112,115,147,162` | no — smoke-flow driver |
| `flow/merge_lib.py` | `flow/lib.sh:211` | no — smoke-flow driver |
| `flow/core/fetch.sh` | `verification/core/setup.sh:84` | **yes** — whenever `verification/build/cve2/upstream/rtl/cve2_top.sv` is absent, which is every true cold start |

(`verification/core/runner.py`, `verification/core/build_tests.py` and `verification/core/link.ld` are
reached the same way — `run.sh:76,82`, `archtest_common.py:57`, `build_tests.py:57` — and were already
attested, which is why the source/import walk never surfaced the mechanism: its unattested hits all
happened to be absent, not the mechanism itself.)

Until this record, `flow/core/fetch.sh` is the strongest counterexample: it sits on the core path
itself, and the cold start whose result the envelope records cannot run without it. The other four are
the smoke/flow-driver tier, reachable only through attested drivers whose cold starts back no core
claim — the same consistency argument decision 0016 used for `flow/lib.sh`.

**Decision.**

1. **Boundary rule, extended by mechanism:** every input the attested harness cannot execute without
   is listed in `testbenches`, *by any reachability mechanism* — sourced, consumed, or invoked as a
   subprocess. The five files above join the inventory, each named with the file and line that pulls
   it in. The four smoke/flow-driver files ride on the same consistency argument as `flow/lib.sh`
   (their invokers are content-hashed regardless of whether their cold starts back core claims);
   `flow/core/fetch.sh` is listed on the direct rule — the recorded cold start executes it.

2. **Exclusions, recorded so the silence is explicit:**

   - `$SCRATCH/mkrecord.py` is not a repo file: `flow/smoke/run.sh:74` generates it with a heredoc,
     so its content is already covered by `run.sh`'s own hash.
   - Design inputs the harness consumes as data are not harness code and stay out: the CVE2 closure
     and `reuse.lock.json` (every fetched file is sha256-checked against the lock),
     `rtl/cve2_rv32imc_wrapper.sv` (the DUT source) and the committed netlist
     `flow/core/records/2026-11-14/netlist.v`. The closure, the lock and the DUT source are indeed
     covered by item 1's envelope checks — `flow/core/fetch.sh`, `reuse.lock.json` and
     `rtl/cve2_rv32imc_wrapper.sv` each carry a `content_hash` check there (fetch.sh's hashed fetch
     is what makes the downloaded closure sha256-verified through the lock); the committed
     netlist is **not** covered — item 1's envelope still attests the superseded
     `flow/core/records/2026-11-03/netlist.v` (decision 0017
     §"Deferred: the item-1 tail": the `rtl/inventory.json` re-point at the 2026-11-14 netlist was
     measured, found to render item 1 `unmet, stale_evidence`, and reverted to land with a fresh
     envelope when a host can run the synthesis again). The netlist's exclusion here therefore rests
     on the boundary rule itself — a data design input the harness consumes, never subprocess-reached,
     so never in this inventory's scope — not on an item-1 overlap that does not exist for it.
     `attest/item9.json`'s `description` says "the committed netlist — which are content-hashed by
     item 1's envelope checks, not item 9's", which is true of the closure, the lock and the DUT
     source but overstates item 1's coverage for the committed netlist; that wording is
     inventory-gated text — editing it moves `sha256sum attest/item9.json`, forcing a fresh cold
     start — so the correction is **deferred with cause** (0017's own convention) to the next
     item-9 re-attest that already pays a cold start for another reason, not silently left as a
     discharge.
   - `spec/core.md` remains deliberately unlisted per decision 0016; that exclusion is unchanged here.

3. **Item 9 re-attested in the same commit as the inventory edit** (0014's measured rule: an inventory
   edit without regeneration renders item 9 `unmet, stale_evidence`; the cold start runs once, on a
   host with iverilog 13.0, verilator 5.050, python 3.12 and network egress — #107, #112). The
   superseded envelope (17-input 20-check pass, input hash `sha256:9fa21c9c…`, produced at commit
   `e7687a0`, 2026-11-17, the merged-tree re-attest over `sv2v.sh` `549ad8e5`) is retained
   byte-for-byte at **`evidence/records/item9-2026-11-17-e7687a0.json`**, named by decision 0017's
   date-plus-producing-commit convention. `manifests/asap7-riscv-core.json`'s item-9 citation hash
   moved to the new inventory hash, and `manifests/asap7-riscv-core.signoff.json` was regenerated from
   both; item 9 still renders `met`, with `check_count` 25 (22 content-hash checks, the cold start, and
   two pin checks) and `t1_met_count` unchanged.

**Regeneration.** Same pinned command as 0016; the `klt` pin is not bumped here:

```
uvx --python 3.12 --from "klayout-tools==0.8.0" klt signoff --attest 9 --inventory attest/item9.json -o evidence/item9.json
```

`--python 3.12` is load-bearing for the same reason 0014/0016 record: the cold start runs
`verification/run.sh`, which refuses any `python3` not matching `verification/tool-versions.txt`.
