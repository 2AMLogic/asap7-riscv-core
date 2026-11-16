# 0016 — Item 9's inventory attests every input the attested harness cannot run without

**Status:** adopted 2026-11-15. Extends the inventory and envelope produced under
`spec/decisions/0014-item-9-check-gate-and-lib-sh-attestation.md` (not that record's decisions — the
same rule it wrote for one file, now applied to the rest of the closure). Closes
issue #145.

**Problem.** `attest/item9.json`'s own `description` states the principle that decides what belongs in
`testbenches` — `verification/lib.sh` is listed because "the harness does not execute without it, not
because it is itself a bench" — but the principle was applied to only one of the harness's inputs. The
attested shell files source four more shell files, and the attested library and runner consume two data
files, none of which were attested:

- `verification/core/setup.sh:20` sources `fetch_checked.sh` (the sha256-checked downloader behind
  every tool pull), and `flow/core/sv2v.sh:19` sources it too;
- `verification/core/setup.sh:78` sources `flow/core/sv2v.sh` (the converter that produces the CVE2
  closure the attested core run simulates);
- `verification/lib.sh:24` reads `verification/tool-versions.txt` and `verification/lib.sh:31` dies
  without it — the same file that carries every download `sha256` the harness enforces, none of which
  item 9's `pins` block duplicates;
- `verification/run.sh:56,58` hash and `pip install` from `verification/requirements.txt` — the whole
  harness Python environment;
- `flow/smoke/run.sh:31` sources `flow/lib.sh`.

The consequence is mechanical: the item-9 `--check` gate hashes only paths in the inventory, so an edit
to any of these files changed what the attested harness executes while the envelope reproduced and the
gate stayed green. Issue #145 was filed from exactly that blind spot: PR #142 rewrote
`flow/core/sv2v.sh` (37+/7-) with no item-9 drift recorded. There is no Python analogue — every
attested `.py` import resolves to a file already attested (`archtest_common`) or to stdlib/cocotb.

**Decision.**

1. **Boundary rule, stated as a rule:** every input the attested harness cannot execute without is
   listed in `testbenches`, whether or not it is itself a bench. The rule now names all five inputs
   above with the file and line that pulls each in. `flow/lib.sh` rides on the consistency argument —
   `flow/smoke/run.sh` is content-hashed regardless of whether its cold start backs a core claim, so
   the library it sources is hashed too.

2. **`spec/core.md` is deliberately not listed.** `flow/core/sv2v.sh` and `flow/smoke/run.sh` read
   pins from it, so it is strictly an unattested input the harness reads — but it is the ratified
   spec, change-controlled under `spec/decisions/`, and attesting it would red the item-9 gate on
   every spec edit. That is a different and much larger policy change, not taken here. The exclusion
   and its reason are recorded in the inventory `description` so the silence is explicit.

3. **Item 9 re-attested in the same commit as the inventory edit** (0014's measured rule: an inventory
   edit without regeneration renders item 9 `unmet, stale_evidence`). The prior envelope (12-input
   15-check pass, input hash `sha256:6b1dbf95…`, produced at commit `d8087b0`, 2026-11-15) is retained
   byte-for-byte at **`evidence/records/item9-2026-11-15-2.json`**. The convention's plain-date name
   `item9-2026-11-15.json` was already taken earlier the same day — `d8087b0` retained the `556b51a`
   envelope there — so the `-2` suffix disambiguates; the envelope itself carries no timestamp field,
   so the name is the only place the collision could surface. `manifests/asap7-riscv-core.json`'s
   item-9 citation hash moved to the new inventory hash and
   `manifests/asap7-riscv-core.signoff.json` was regenerated from both; item 9 still renders `met`,
   with a non-null citation, `check_count` 20, and `t1_met_count` unchanged at 3 of 11.

**Regeneration.** The envelope is tool-produced and never hand-edited, pinned to the `klt` version the
workflow installs:

```
uvx --python 3.12 --from "klayout-tools==0.8.0" klt signoff --attest 9 --inventory attest/item9.json -o evidence/item9.json
```

`--python 3.12` is load-bearing: the cold start runs `verification/run.sh`, which refuses any `python3`
not matching `verification/tool-versions.txt`. The `klt` pin is not bumped here.

**Verification.** The live cold start that produced the envelope — `verification/run.sh --core`, driven
by `klt signoff --attest 9` on a host with iverilog 13.0, verilator 5.050, python 3.12.3 and network
egress: **72 of 72 riscv-arch-test I/M/C programs pass, 0 failures, 0 skipped, exit 0**
(`verification/runs/20261115T201341Z-3288127/results.xml`; `C-cebreak-01` is excluded with its
diagnosed reason in `verification/core/excluded.json` and decision 0011, so 72 is the full set). The
new envelope is `evidence/item9.json` (17 attested paths, 20/20 checks, input hash
`sha256:4b13b862…`). Negative control for the new coverage, run twice: with the new envelope
committed, editing one byte of a newly-attested file — a comment in `fetch_checked.sh`, then a
byte of `verification/tool-versions.txt` (a non-`.sh` data input) — makes
`klt signoff --attest 9 --inventory attest/item9.json --check evidence/item9.json` exit **3** and name
that row; reverting each restores `status: match`, exit 0. This is the check that proves the gap
closed, not merely that the envelope regenerated. RTL simulation of the converted CVE2 closure against
a predictive PDK; ASAP7 is never fabricated and nothing here is measured.

**Not decided here.** Attesting `spec/core.md` (deliberately excluded, §2); item 10's inventory
(measured: no gap of this class — its four hygiene paths are two documents and two workflows, none
sourced by anything); a `klt` capability that derives the sourced-dependency closure automatically
(plausibly the long-term fix, and a reasonable klayout-tools friction issue, but a tool change, not
this repo's); the duplicate `0012` decision number (issue #90); the item-10 `--check` comment's
missing retention step (issue #89); `CLAUDE.md`'s missing item-9 re-attest warning (issue #141).
