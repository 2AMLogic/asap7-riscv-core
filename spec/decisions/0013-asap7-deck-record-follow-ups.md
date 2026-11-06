# 0013 — Deck record follow-ups: `released: false`, PAD wording, LVS deck pin

**Status:** proposed 2026-11-06. It takes the EE and market keys before the operator ratifies. Follows
decision 0012 and the smoke records in `flow/smoke/records/2026-11-05/` (issue #71). Existing records are not edited.

**Decision.**

1. **`released: false` on the DRC record is expected.** `flow/smoke/run.sh` copies the packaged deck to a scratch
   path and passes it with `--deck-file`, so `drc.json` records `provenance.deck.name: "asap7.drc"`, `released: false`.
   The LVS record, which names the deck, records `name: "asap7"`, `released: true`. The cause (file path versus
   name) is inferred, not traced in `klt`. The pin is the content hash, which equals the packaged deck's; the
   `released` flag is not part of the acceptance. The flow is not changed to pass `--deck asap7`, because that would
   change how `--expect-rule-categories` and the hash are exercised in the ratified flow.
2. **Correction to decision 0012, item 3.** It says PAD is reported in `coverage.unchecked_rules`. The 0.9.0 record
   has `"unchecked_rules": []`. The tool does not name PAD there. PAD remains unchecked (the DRM has no PAD rule),
   and `spec/core.md` states it as unchecked itself. Decision 0012 and the 2026-11-05 record stay as written;
   this note is the correction.
3. **Pin the LVS deck hash.** `spec/core.md` pins `sha256:5c58a50e5f6a9099810b3fde37eaa8d93b0897653cb6597a831baac1f5ebee76`
   (deck `asap7`, `klayout-tools==0.9.0`) beside the DRC pin, so "LVS clean" names a deck as "DRC clean" does.
   Without a pin the hash could drift on a `klt` bump unnoticed. `flow/smoke/run.sh` fails when `lvs.json`
   records a different hash, mirroring the DRC check.
4. **Market-key rule.** A buyer-facing "DRC clean" or "LVS clean" must name the klt ASAP7 deck by hash, not the
   upstream Calibre deck. Both are tool results against a predictive PDK.
5. **Stale wording.** The LVS line in `spec/core.md` named a dev `klt` build; it now names release 0.9.0.

**Not changed:** the DRC/LVS invocation, any rule or threshold, the 549 DRC violations and the LVS mismatch
(results about a placeholder DUT), the `klt signoff` pin, and `flow/smoke/records/2026-11-05/*`.

**Upstream:** the deck header comment states a stale rule-category count (263 against 267 declared). That belongs to
`2AMLogic/klayout-tools` and is filed there as a generic issue (link in the PR).

**Upstream:** the deck header comment issue is filed as 2AMLogic/klayout-tools#5073.
