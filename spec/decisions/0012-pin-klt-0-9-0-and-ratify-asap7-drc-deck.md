# 0012 — Pin `klayout-tools==0.9.0` for DRC, LVS and the smoke flow; ratify the new ASAP7 DRC deck hash

**Status:** proposed 2026-11-05. A ratification PR: it takes the EE and market keys before the operator ratifies.
Follows operator ruling r6-q15 (2026-11-05, recorded in issue #17).

**Decision.**

- The `klt` pin in [`spec/core.md`](../core.md) becomes the release `klayout-tools==0.9.0`. It replaces the unreleased
  tree pin `git+https://github.com/2AMLogic/klayout-tools@7ee09483b748` (decision 0005) and the `0.8.0` release pin
  recorded for these steps (decision 0008). 0.9.0 contains the fixes for klayout-tools #4086, #4087 and #4088
  (`eb49f81d6`, `7ee905b43`, `d952001b1`), which the smoke flow needs to reach `par` `ok`.
- `klt signoff` stays at `klayout-tools==0.8.0` (decision 0008, `manifests/README.md`,
  `.github/workflows/signoff.yml`). Its committed verdicts (`evidence/`, `attest/`) were produced by 0.8.0 and are not
  re-run here.
- The DRC deck hash that "DRC clean" means is replaced (decision 0005):

  | | Pin of decision 0005 | Pin of this decision |
  |---|---|---|
  | Build | `0.7.1.dev1743+g7ee09483b748` | `0.9.0` (`v0.9.0`, `5dbbad05ff42`) |
  | `provenance.deck.content_hash` | `sha256:08dba3ee047a3ec68b3cd761f982809c62a0d128b8d34ef4e76a28f61221aa6a` | `sha256:14f146f02cd731de3e0b59452eadfdab9c2c947724a219a1002a31b5e0f12d13` |
  | `--expect-rule-categories` | 263 | 267 |

**What changed in the deck** (`diff` of the two `asap7.drc` files; `klt deck info --deck asap7` on 0.9.0 reports the
new hash as released):

1. Four predictive THICKOX rules are added: `THICKOX.ACTIVE.EN`, `THICKOX.S`, `THICKOX.GATE.L`, `THICKOX.ACTIVE.W`
   (263 + 4 = 267). The DRM has no thick-oxide layer; the deck assumes stream number 111/0 and says so in its comments,
   so these are predictive and not DRM rules. They check nothing on a layout with no shapes on 111/0.
2. Two opt-in grid-origin rules, `FIN.GRID.1` and `GATE.GRID.1`, run only when the caller passes `fin_y_origin_nm` /
   `gate_x_origin_nm` via `--deck-var`. They are not part of the 267 default categories, and this repo does not pass
   them.
3. PAD is reported as unchecked in `coverage.unchecked_rules` (the DRM has no PAD rule); it was silently unchecked
   before.
4. Two crash/skip fixes in the LIG separation rules: an empty second operand and a no-pair-within-distance case no
   longer abort KLayout. The net-aware separation is skipped only when the plain separation is empty, which already
   implies the net-aware result is empty (it is a subset), so the set of violations reported is unchanged.

**No existing rule is relaxed.** The diff removes no rule id and changes no numeric threshold of an existing rule.
The "not checked" list in `spec/core.md` (track/net/corner/grid predicates, FEOL/MOL increments, PAD) is unchanged
except that PAD is now stated by the tool.

**Not changed:** every other pin in `spec/core.md` and `spec/pdk-bringup.md` (ASAP7 upstream, cell library, PDK, core,
sv2v). `spec/pdk-bringup.md` and decision 0005 are append-only records and stay as written; this record supersedes
their klt pin and deck hash for acceptance.

**Evidence** (`flow/smoke/records/2026-11-05/`, run by `flow/smoke/run.sh` against the pinned ASAP7 checkout):
`par.json` is `ok` and `layout/` holds the counter's DEF, GDS and as-built netlist. `drc.json` carries the new hash
and 267 categories. The counter layout is not DRC clean (549 violations, all routing-layer track/grid auxiliary rules
and two others; see the record) and `lvs.json` is `mismatch`; this is a result about a placeholder DUT through a
young flow, not a claim about the core, and it is not a reason to relax the spec. `erc.json` stays `not_checked`
(no antenna table, klayout-tools #4090).

**Rejected:** keeping the old deck by pinning an older build (the old build predates the `request.library`, descriptor-view and `floorplan.tracks` fixes that `par` needs);
patching the tech LEF or the CTS buffer locally (hides the gaps this canary exists to expose).
