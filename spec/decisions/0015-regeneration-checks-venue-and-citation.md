# 0015 — Flow-record regeneration checks are T1 `local_only` attestation checks; the PR citation form; the item-1 gate sequenced behind #105

**Status:** adopted 2026-11-15, effective on merge of the PR carrying this
record (the Champion ratification hold applies to exactly that step). Closes
issue #107. This record ratifies a mechanism that already exists and sequences
its mechanical completion; it edits no inventory, no envelope, no workflow and
no flow script, so it gates nothing by itself.

**Problem.** The two acceptance criteria every flow proposal names — (1)
`flow/core/synth.sh <asap7-checkout> --check` regenerating and byte-comparing
`flow/core/records/2026-11-03/netlist.v`, and (2) a fresh-`RECORD_DATE`
`flow/smoke/run.sh <asap7-checkout>` diffed against
`flow/smoke/records/2026-11-05/` — are cited by open proposals #91, #99, #101
and #106 and verified by nobody in a sweep worktree. Measured 2026-11-15
against `origin/main` @ `314c493`:

1. **The venue already exists and is already wired for criterion 1.**
   `rtl/inventory.json` (T1 item 1, "Design sources") expresses the
   regeneration as a formal freshness check —
   `derived[0].check = {"argv": ["flow/core/synth.sh", "--check"],
   "local_only": true}` over `flow/core/records/2026-11-03/netlist.v`,
   generator `flow/core/synth.sh (klt synthesize)` — and `evidence/item1.json`
   records its outcome (`exit_status: 0`, `passed: true`, `local_only: true`)
   with a `provenance` block pinning `klt_version: 0.8.0` and the inventory's
   content hash. That envelope *is* the "regeneration verified at `<sha>`,
   record set `<date>`" citation the issue asked to invent. Criterion 2 has no
   such expression anywhere: `attest/item9.json` lists `flow/smoke/run.sh` as
   a driver, and that inventory's own description states the cold start is not
   run by its attestation.

2. **Criterion 1's recorded result has rotted silently, and nothing can see
   it.** Re-running the committed envelope against the tree (command under
   "Verification") reports `status: drifted`, exit 3, with two of five
   attested bodies stale:

   ```
   report: evidence/item1.json
   status: drifted

   drift:
     attestation.checks.0.content_hash:   # flow/core/fetch.sh
         committed: 'sha256:086be3c7225e2a78…'
         fresh:     'sha256:1647d263eba72a6d…'
     attestation.checks.1.content_hash:   # flow/core/synth.sh
         committed: 'sha256:40982cb124de8789…'
         fresh:     'sha256:8cb1b03c961e77fc…'
   fresh_status: pass
   [SKIP] freshness flow/core/records/2026-11-03/netlist.v: flow/core/synth.sh --check (local_only, not run; committed outcome: pass)
   exit 3   # the command's exit status
   ```

   The envelope's recorded `exit_status: 0` describes a command that per #105
   cannot exit 0 on `main` at all (`--check` picks the newest record
   directory, which no longer holds a `netlist.v`, and exits 1 before
   comparing). Yet T1 item 1 still renders `met` with CI green:
   `.github/workflows/signoff.yml` gates only items 9 and 10 with `--check`
   steps, and the tier byte-compare is structurally blind to body drift
   because `manifests/asap7-riscv-core.json` binds item 1's citation to the
   *inventory* hash (`provenance.input.content_hash`, `sha256:c50ab1d5…`,
   still fresh) — never to the attested bodies. This is the #88 failure mode
   recurring one item over; decision 0014's "Not decided here" explicitly left
   "a `--check` gate for any other T1 item" open.

3. **The gate itself is cheap and needs no PDK.** `--check` skips the
   `local_only` command on its own — printing the `[SKIP] … (local_only, not
   run; committed outcome: pass)` line quoted above — exits in seconds, and
   writes nothing: the motivating run was made in a checkout whose `git status
   --porcelain` stayed empty before and after.

**Decision.**

1. **The venue is ratified as-is: both regeneration diffs are `local_only`
   command checks in a T1 attestation inventory, their outcomes recorded in a
   committed `evidence/itemN.json` envelope.** Criterion 1 already has its
   entry (`rtl/inventory.json` `derived[0]`, quoted above); no new venue, no
   standing batch lane and no new citation convention is invented. Criterion 2
   gains the same shape when its inventory entry is proposed — not by this
   record, because any envelope edit requires a host that can actually run the
   smoke flow.

2. **The citation form a PR must use.** A PR that cannot run a regeneration
   check (a sweep worktree, CI, any PDK-less host) cites the recorded outcome
   instead of asserting the criterion met. The citation names, concretely:

   - the envelope path — `evidence/item1.json` today;
   - the `provenance.klt_version` the envelope was produced with (`0.8.0`);
   - the inventory `content_hash` the envelope was produced against —
     `provenance.input.content_hash` (`sha256:c50ab1d5…` today), which is also
     what the tier manifest binds;
   - the `main` commit the recorded run was made at (stated in the citing
     prose; the envelope schema does not carry one).

   `--check`'s `[SKIP] … (local_only, not run; committed outcome: <x>)` line
   is what carries the committed outcome forward through a gate run without
   re-running the flow. A PR reviewing an ungated envelope cites the envelope;
   a PR reviewing a gated one runs the gate and cites its output.

3. **Sequencing, with the dependency named.** In order, and not re-ordered:

   (a) **#105** fixes `--check`'s target selection (the newest record
   directory no longer holds a `netlist.v`; the command exits 1
   unconditionally on `main` today).

   (b) **An operator refreshes `evidence/item1.json` on a PDK-capable host**,
   retaining the superseded envelope *first* per decision 0014's two-step
   retention rule: copy the committed `evidence/item1.json` to
   `evidence/records/item1-<the date that envelope was produced>.json`, then
   regenerate with the CI-pinned tool (`uvx --python 3.12 --from
   "klayout-tools==0.8.0" klt signoff --attest 1 --inventory
   rtl/inventory.json -o evidence/item1.json`). Refreshing — unlike gating —
   runs the inventory's `local_only` command for real (`--skip-local-only`
   exists in no released `klt` — absent in 0.8.0, 0.9.0 and 0.9.1 — and is
   refused with `--check` anyway), so it needs a host where
   `flow/core/synth.sh --check` can actually pass: after (a), and with the
   pinned checkout per the procedure below.

   (c) **A PR adds a "Re-check the item 1 attestation envelope" step to
   `.github/workflows/signoff.yml`**, mirroring the item-9 step's exit
   contract — 0 fresh, 3 drift, anything else a hard error distinguished from
   drift — **and re-attests `evidence/item10.json` in the same PR**, because
   `.github/workflows/signoff.yml` is one of item 10's attested hygiene files
   (`attest/item10.json` lists it). **(c) must not land before (b)**: gating a
   drifted envelope reds `signoff` on `main` on the first run, exactly the
   state #124 reports for item 9. This record deliberately does not touch
   `signoff.yml`; step (c) belongs to its own PR.

4. **The operator procedure for the runs behind (b)** — and for any
   criterion-2 inventory entry proposed later:

   - The checkout may be passed as `$ASAP7_DIR` instead of an argument
     (`flow/core/synth.sh:50`, `flow/core/ff_simple_check.sh:21`).
   - The two criteria do not impose the same provisioning. Criterion 1 needs
     only the upstream repo and `asap7sc7p5t_28` at their pins —
     `flow/core/synth.sh` makes two `check_pin` calls (`flow/core/synth.sh:62-63`).
     Criterion 2 additionally needs `asap7_pdk_r1p7` initialized —
     `flow/smoke/run.sh` makes three `check_pin` calls
     (`flow/smoke/run.sh:54-56`) and reads the submodule's layermap at
     `flow/smoke/run.sh:175`.
   - A `--filter=blob:none` partial clone with `asap7sc7p5t_28` initialized is
     ~150 MB, not multi-gigabyte (measured 2026-11-14 on a dispatch worker).
     Checkout paths are host residue and are deliberately not recorded here —
     a run states where its checkout lived instead.
   - Criterion 2 writes into a fresh record set: `new_record_dir` refuses an
     existing record set (documented `flow/lib.sh:27-28`; the function is
     defined at `flow/lib.sh:87` with the refusal at `flow/lib.sh:90`), so the
     run sets `RECORD_DATE` to a new date and diffs the six step records
     against `flow/smoke/records/2026-11-05/`.

**Attestation.** This record edits nothing attested: `attest/item10.json`
lists only `README.md`, `LICENSE`, `.github/workflows/ci.yml` and
`.github/workflows/signoff.yml`, and the PR carrying it touches `spec/` only,
so no re-attestation is required and no gate can move. No envelope, inventory,
manifest, flow record, pin or RTL is edited here. The item-1 drift quoted
under "Problem" stands until step (b), and item 1 will keep rendering `met`
with CI green until step (c) lands. On this record's own branch,
`--attest 9 … --check` exits 3 (the #124 drift, identical on `main` — quoted
so the PR shows this record did not regress it) and `--attest 10 … --check`
exits 0 (`status: match`).

**Verification.** Every measured claim above was re-derived on this record's
branch at `314c493` on 2026-11-15:

```
uvx --python 3.12 --from "klayout-tools==0.8.0" klt signoff \
    --attest 1 --inventory rtl/inventory.json --check evidence/item1.json   # exit 3, "Problem" output
uvx --python 3.12 --from "klayout-tools==0.8.0" klt signoff \
    --attest 9 --inventory attest/item9.json --check evidence/item9.json    # exit 3 (#124 drift)
uvx --python 3.12 --from "klayout-tools==0.8.0" klt signoff \
    --attest 10 --inventory attest/item10.json --check evidence/item10.json # exit 0, status: match
```

`git status --porcelain` was empty after each run (`--check` writes nothing);
the tool was the CI-pinned `klayout-tools==0.8.0` under `uvx --python 3.12` in
a throwaway environment; no host tool was installed or changed. The item-1
fresh hashes quoted under "Problem" are as observed at `314c493` — they are
expected to move again as `flow/` scripts are edited, which is the drift this
record's step (c) is what will finally make visible. Regeneration results
everywhere in this repo are tool outputs against a predictive PDK; ASAP7 is
never fabricated and nothing here is measured silicon.

**Not decided here.** The `signoff.yml` gate step and its item-10 re-attest
(step (c) — its own PR, after (a) and (b)); the #105 selection fix itself; a
criterion-2 inventory entry (needs a host that can run the smoke flow); the
PDK-free differential harness over the record-writing code paths — genuinely
useful and complementary, built against the #112 / merged-#114 pattern, filed
separately if wanted; provisioning ASAP7 checkouts on dispatch workers (a
worker-spec change, not this repo's, and this record deliberately hardcodes no
path); the #124 item-9 envelope refresh (same drift class, one item over —
sibling work, not absorbed here); a `klt` pin bump; the duplicate `0012`
decision number (issue #90).
