# asap7-riscv-core — agent instructions

Open-source canary block: place-and-route of an Ibex/CVE2-class RISC-V core
on ASAP7, designed and verified by AI agents. **Digital.**

- **ASAP7 is a predictive PDK. This block is never fabricated.** It is
  layout, DRC and timing only. Never write anything that implies silicon, a
  shuttle, a tape-out or a measurement — every number here is a tool result
  against a predictive model, and is labelled "predicted" where it is a
  timing figure.
- **PDK**: ASAP7 (The-OpenROAD-Project/asap7), 7.5-track standard cells.
  Digital flow: cocotb + Icarus for simulation, Yosys for synthesis,
  OpenROAD for place-and-route and timing. Layout, DRC, and LVS through
  klayout-tools (`klt`).
- **Bringing the PDK up is the first job.** ASAP7 is not in the fleet's
  `open_pdks` store. Getting `klt` to resolve it — technology and layer
  files, the cell library, a DRC/LVS deck klt can run — is work this repo
  owns, pinned to an upstream commit and recorded in `spec/`. Every gap in
  that bring-up is a klayout-tools issue.
- **FinFET rules are the point, and the risk.** Fin-grid and gate-pitch
  quantization and tight metal rules are what no planar fleet PDK has
  exercised. Expect the deck and the checker to be weakest here. A DRC
  "clean" means clean against a named, pinned deck; a waiver is recorded with
  its reason, never silent.
- **Scope discipline.** The core comes unmodified from a pinned upstream
  commit, the same one `sky130-riscv-soc` selects; do not fork it or tune its
  RTL for this PDK. No SRAM, caches or SoC around it.
- **Friction protocol (the canary's job)**: every time klayout-tools is
  awkward, missing a capability, or wrong for what you need, file an issue at
  `2AMLogic/klayout-tools` describing the tool gap generically — that tracker
  is scoped to the tool, so keep design-specific detail out of it and describe
  the gap, not the design.
- **Verification is the product**: no claim without a testbench. Functional
  claims come from the architectural tests on the simulated netlist; layout
  claims from DRC/LVS reports against the pinned deck; timing claims from STA
  at stated corners. Recorded results are append-only evidence.
- Spec changes go through `spec/` with a decision record; agents do not relax
  the ratified spec to make results pass.
- **Attested paths: re-attest in the same PR.** Two attestation inventories
  gate pull requests through the `klt signoff` workflow, each enforced by its
  own "Re-check the item N attestation envelope" step: **item 10** (repo
  hygiene, `attest/item10.json` → `evidence/item10.json`) and **item 9**
  (testbenches shipped, `attest/item9.json` → `evidence/item9.json`). **Any**
  diff that touches a path an inventory attests must also commit a re-attested
  envelope for that item in the same PR, or the matching step reds the pull
  request. This applies to documentation-only passes: a one-word edit of an
  attested file is drift. Each inventory is the source of truth for which
  paths it attests — check it before editing a file it may pin.

  - **Item 10 (repo hygiene).** `attest/item10.json` attests four files:
    `README.md`, `LICENSE`, `.github/workflows/ci.yml` and
    `.github/workflows/signoff.yml`. Regenerate the envelope with the klt
    version CI pins, in a throwaway environment — never install a different
    klt onto the host:

    ```bash
    uvx --python 3.12 --from "klayout-tools==0.8.0" klt signoff \
        --attest 10 --inventory attest/item10.json -o evidence/item10.json
    ```

    Item 10 needs no retention step: a tool-produced envelope is regenerated
    in place because the superseded one reproduces from its own commit
    (`spec/decisions/0019-attestation-retention.md`, proposed pending
    operator ratification). Item 10's envelope harness checks are the cheaper
    of the two.

  - **Item 9 (testbenches shipped).** `attest/item9.json` attests the
    verification and smoke testbench paths (e.g. `flow/smoke/run.sh`,
    `verification/run.sh`); the inventory lists them, not this file.
    Re-attesting item 9 is a two-step change and both steps belong in the
    same PR (ratified in
    `spec/decisions/0014-item-9-check-gate-and-lib-sh-attestation.md`):
    retain the superseded envelope first — copy the committed
    `evidence/item9.json` to
    `evidence/records/item9-<date-the-committed-envelope-was-produced>.json`
    — then regenerate, committing both:

    ```bash
    uvx --python 3.12 --from "klayout-tools==0.8.0" klt signoff \
        --attest 9 --inventory attest/item9.json -o evidence/item9.json
    ```

    This re-attest runs `attest/item9.json`'s `local_only` cold start
    (`verification/run.sh --core`, timeout 1800 s), so it needs a host with
    `iverilog`, `verilator 5.050`, `python 3.12` and network egress — it
    cannot be done in a sweep worktree (cf. #107, #112).

  `--python 3.12` is load-bearing for both: `uvx` puts its own environment
  first on `PATH`, and each envelope's harness checks run `verification/run.sh`,
  which refuses any `python3` that does not match `verification/tool-versions.txt`
  (`python=3.12`). Without it the re-attest fails with both harness checks at
  exit 1 and writes nothing.

  Never hand-edit an envelope, and never drop a path from an inventory to
  dodge the gate — that weakens the attestation and needs a `spec/` decision
  record.
- **1 GHz predicted post-route at the slow corner is the target.** 500 MHz is
  the fallback and 1.5 GHz is a stretch.

<!-- BEGIN LOOM ORCHESTRATION -->
This repository uses [Loom](https://github.com/rjwalters/loom) for AI-powered development orchestration — see the Loom repository for the full guide (roles, labels, worktrees, configuration). When installed, Loom also writes a locally-substituted copy of that guide to `.loom/CLAUDE.md`.

Work is coordinated through `loom:` labels on issues and pull requests, and the same roles run either under `loom-daemon` or by hand in an attended session — daemon mode is optional. Create the labels once with `.loom/scripts/sync-labels.sh` (an install ships `.github/labels.yml` but does not create the labels on the forge). A pull request ready for review carries `loom:review-requested`; Judge reviews it and applies `loom:pr` (approved) or `loom:changes-requested`; Doctor fixes a `loom:changes-requested` pull request and returns it to `loom:review-requested`. Only a `loom:pr` pull request gets merged, and always via this repo's merge script (`.loom/scripts/merge-pr.sh`) — never a raw forge merge command such as `gh pr merge`. Full state machine: `.loom/docs/label-state-machine.md`.
<!-- END LOOM ORCHESTRATION -->

<!-- BEGIN REPO-SKILLS -->
This repository has [Repo Skills](https://github.com/rjwalters/repo) v0.26.1 installed —
general repository hygiene and environment commands invoked as `/repo:<command>`. Run
`/repo:help` for the command list, or see `.claude/skills/repo/SKILL.md` for the full
guide. Hygiene commands apply safe, reversible fixes by default and report each
change; run with `--ask` to review first, and `--prune` to allow irreversible
removals. Managed by `install.sh` — edit outside the markers only.
<!-- END REPO-SKILLS -->
