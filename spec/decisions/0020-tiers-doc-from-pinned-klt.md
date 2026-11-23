# 0020 — The tiers checklist comes from the pinned klt release

**Status:** adopted 2026-11-23. Implements the operator ruling of 2026-11-23 (attended
`/fleet:decide` session, round 20261121-r19, q103), recorded on issue #111. This record exists
because the ruling reverses a documented choice — the vendoring recorded in `manifests/README.md`
(and cited by `ROADMAP.md`) — which no earlier decision ratifies.

**Problem.** `manifests/design-evidence-tiers.md` was a hand-synced, byte-identical copy of the
design-evidence tiers doc the pinned `klayout-tools==0.8.0` install already ships as package data,
passed back to the grader through the tiers-doc override by four callers: CI's byte-compare run and its
regenerate hint (`.github/workflows/signoff.yml`), the README Reproduce row, and the
`manifests/README.md` recipe. Nothing checked the copy against the install, and CI graded with the
override on both sides of its own byte-compare, so a copy gone stale relative to the pinned grader
still compared clean — at a klt pin bump this block would keep grading itself against the old
ladder, with the record's `source_doc` field as the only trace.

**Decision.** The vendored copy and the tiers-doc override are removed. The pinned
klayout-tools release alone selects the design-evidence checklist: `klt signoff` reads the tiers
doc its own install ships, and the committed record's `source_doc` names that install's
docs-relative label (`docs/design-evidence-tiers.md`) while `source_doc_content_hash` binds the
verdict to the exact ladder bytes. The CI comparison of a fresh run against the committed record
stays; it is what catches a checklist change at a pin bump. This supersedes the vendoring entry
this PR removes from `manifests/README.md`; decision 0008's grader pin is unchanged and now
carries this meaning too.

**Evidence.** Before removal the copy and the pinned install's bundled copy were the same bytes
(68,400 bytes, sha256 `a26b9026…efdc7`, measured against `klayout-tools==0.8.0` in issue #111's
body at `origin/main` `f84e5c3`), and the no-override `source_doc` label is fixed relative to the
install's docs, independent of install prefix or working directory (Hermit measurement on issue
#111; re-confirmed by this PR's regeneration). The record regenerated with
`klayout-tools==0.8.0` after removal differs from the committed one in `source_doc` only: no item
verdict, `t1_met_count`, tier result or `source_doc_content_hash` changed.

**Not changed.** The `klayout-tools==0.8.0` signoff pin (decision 0008), the item-10 attestation
inventory `attest/item10.json`, the item-9 inventory, and the DRC/LVS `klt` pin in `spec/core.md`
(decision 0005). No tier item, grading rule or evidence citation changes, and dated recorded
evidence that names the old path (e.g. `flow/smoke/analysis/`) is left as history.
