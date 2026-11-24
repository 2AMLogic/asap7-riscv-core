# 0021 — `SDT.ACTIVE.AUX.2` inside the pinned library's deviation cells is a disclosed exception for T1 item 3

**Status:** proposed 2026-11-24. It takes the EE and market keys before the
operator ratifies. Follows the operator ruling in klayout-tools #4530
(violations inside unmodified foundry cells may be a disclosed exception for
T1 item 3), the deviation record `asap7_rules.SHIPPED_CELL_DEVIATION_RECORDS`
(klayout-tools #4496), and the first core DRC record
`flow/core/records/2026-11-24/drc.json` (issue #29, attribution in
`flow/core/analysis/2026-11-24-drc.md`). No earlier record is edited and no
pin changes.

**Decision.**

1. **The `SDT.ACTIVE.AUX.2` markers of the 2026-11-24 core DRC record —
   2,293, all inside instances of `BUFx4_ASAP7_75t_R` (946),
   `BUFx2_ASAP7_75t_R` (692) and `OAI22xp33_ASAP7_75t_R` (655), base and
   mirrored `$VAR1` variants, verified by a containment walk with 0 markers
   outside — are a disclosed exception, not a waiver.** They are recorded
   here, stated in the record's analysis note, and carried in the report's
   violation count; no waiver file under `layout/waivers/` covers them and
   nothing is suppressed in the deck.
2. **The three conditions of the #4530 ruling are met on this layout:**
   the deviation reproduces on the bare cell (measured on `BUFx4` in
   `flow/smoke/analysis/2026-11-05-drc.md` § "SDT.ACTIVE.AUX.2": SDT drawn
   81 nm tall over a 54 nm ACTIVE, so the SDT top edge has no ACTIVE
   horizontal edge to lie on; the 2026-11-21 record re-measured it on the
   counter's CTS instances at the same cell-internal coordinates); it is
   pinned to named cells (the three masters above, on klt's
   shipped-cell deviation list with exactly this rationale); and it is
   stated — by this record.
3. **T1 item 3 stays `unmet` while these markers are present.** This
   disclosure does not convert a `violations` report into a clean one, and
   the item's grader (`klt signoff`) is untouched: `status: "clean"` with
   zero violations remains the acceptance (spec/core.md "DRC / LVS
   acceptance"). The disclosure exists so the exception is legible, not to
   lower the bar.
4. **The flow-side alternative is named, not taken here.** A CTS buffer or
   logic mapping that avoids the ten deviation-list masters would remove
   the family at the source; that is a `flow/core/par.sh` request change
   (a re-route and a new item 2 record), owned by the pin-bump follow-up
   #277 rather than by this record.

**Why a decision record and not a waiver.** Decision 0005's waiver form
accepts a violation of a ratified rule at a location for a reason; this
family is not a violation of the design's own geometry — it is the pinned
cell library's shipped geometry measured by the pinned deck, present in
every placement of those masters on every block that uses the library
unmodified. The #4530 ruling's vocabulary for that is a disclosed
exception. Recording it as a waiver would misstate the cause and give the
supersession machinery (waive-and-retire) a meaning it does not have here:
the exception ends when the library, the deck or the cell choice changes,
not when a marker count moves.

**Consequences.**

- A clean T1 item 3 claim needs either a deviation-free cell choice
  (#277's scope) or an upstream change to the deck/library pairing; until
  then every core DRC record states the exception with its per-master
  counts, as the 2026-11-24 record's analysis note does.
- The counter's six `SDT.ACTIVE.AUX.2` markers
  (`flow/smoke/records/2026-11-21/drc.json`) are the same exception on the
  placeholder DUT and need no separate record.
- The disclosure is bound to the pinned deck hash
  (`sha256:14f146f02cd731de3e0b59452eadfdab9c2c947724a219a1002a31b5e0f12d13`,
  decision 0012) and to the pinned cell library (decision 0001); a bump of
  either re-opens this record.

**Rejected:** waiving the family per decision 0005 (misstates the cause);
editing the deck or the cell library (out of scope for this repo, and the
library is used unmodified by decision 0001); switching the CTS buffer
inside this record's PR (a re-route is #277's business, sequenced behind
the pin bump #246).
