#!/usr/bin/env bash
# Core DRC flow (T1 item 3): runs `klt drc --engine klayout` on the
# committed routed GDS (HEAD:layout/cve2_top.gds, read from Git, never from
# the working tree) against the pinned ASAP7 deck (decision 0012: the
# 0.9.0 packaged asap7.drc, sha256 14f146f0...e0f12d13, 267 rule
# categories; spec/core.md "DRC / LVS acceptance"), and writes a dated
# record under flow/core/records/<date>/.
#
# A violations report is a recorded, valid outcome (decision 0005: each
# violation is fixed in the flow or waived under layout/waivers/, and a
# shipped-cell deviation may be a disclosed exception): the script records
# what the pinned deck reports and never filters, patches or re-runs to a
# prettier status. Nothing is suppressed in the deck.
#
# ASAP7 is a predictive PDK; nothing here is fabricated or measured, and no
# DRC verdict is a silicon claim.
#
# usage: flow/core/drc.sh
#
# Prerequisites: `uvx` and network egress (the pinned klt is resolved
# automatically), or KLT_CMD + KLT_DECK_FILE to run a pre-resolved klt and
# deck file. Record publication uses GNU `ln -T` to link each record file
# into place without replacement (flow/core/record_publish.sh).
#
# Environment:
#   RECORD_DATE     record directory name (default: today, UTC). The script
#                  refuses to write into a directory that already has records.
#   KLT_CMD         klt to run (default: the release pinned in spec/core.md,
#                  via uvx)
#   KLT_DECK_FILE   asap7.drc of the pinned build (default: looked up through
#                  the pinned build's own Python; required if KLT_CMD is set)
#   KEEP_SCRATCH=1  keep the scratch directory
#
# Exit status: 0 a report was recorded (clean or violations); 1 a step
# failed, the report names a deck other than the pin, the input GDS is not
# the one the newest committed par.json pins, or a staged record leaked a
# host path; 2 a refused invocation (no committed GDS to check, or records
# already exist for the date).
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=flow/lib.sh
source "$REPO/flow/lib.sh"
# shellcheck source=flow/core/record_publish.sh
source "$REPO/flow/core/record_publish.sh"
TOP=cve2_rv32imc_wrapper
GDS_PATH=layout/cve2_top.gds

# ---- pins, read from the spec -------------------------------------------
# Label-anchored and fail-closed (flow/lib.sh); the same reads the smoke
# flow makes, so the two drivers cannot drift onto different pins. The PDK
# pins are read for the shared provenance rows only (provenance_rows): DRC
# itself consumes just the GDS and the deck file.
PIN_UPSTREAM="$(spec_sha 'Upstream repo')" || exit 1
PIN_CELLS="$(spec_sha 'Cell library')" || exit 1
PIN_PDK="$(spec_sha 'PDK (DRM')" || exit 1
PIN_KLT="$(spec_klt_pin)" || exit 1
PIN_DECK="$(spec_pin 'equal to the pinned hash' 'sha256:[0-9a-f]\{64\}' 1)" || exit 1
# 267: the deck's declared rule-category count at the decision 0012 pin
# (263 was the decision 0005 deck; the 0.9.0 deck adds the four predictive
# THICKOX rules). spec/core.md "DRC / LVS acceptance" states the count.
EXPECT_CATEGORIES=267

# ---- mode gate: append-only records, one pinned date ---------------------
RECORD_DATE="${RECORD_DATE:-$(date -u +%Y-%m-%d)}"
DATE="$RECORD_DATE"
OUT="$REPO/flow/core/records/$DATE"
if compgen -G "$OUT/*.json" >/dev/null; then
  die "records already exist in flow/core/records/$DATE; set RECORD_DATE to a new label (records are append-only evidence)" 2
fi

klt_cmd "$PIN_KLT"
setup_scratch coredrc

# ---- input: the committed routed GDS, byte-bound -------------------------
# Captured once from one Git revision: the routed GDS at HEAD, read as a
# blob. The working tree is never consulted, so an edited or replaced
# layout cannot become the checked input, and the bytes hashed for the
# record are the bytes the deck checks. Both GDS reads name the captured
# revision rather than HEAD, so a checkout that advances mid-run cannot
# supply a layout from a later commit than the routing record below is
# read from (flow/core/par.sh captures its reference GDS the same way).
INPUT_REV="$(git -C "$REPO" rev-parse --verify 'HEAD^{commit}')" \
  || die "cannot resolve HEAD to select the committed GDS" 2
GDS_REF="$INPUT_REV:$GDS_PATH"
git -C "$REPO" cat-file -e "$GDS_REF" 2>/dev/null \
  || die "no committed HEAD:$GDS_PATH to check (T1 item 2 has not landed)" 2
W="$SCRATCH/work"; mkdir -p "$W"
GDS_IN="$W/$TOP.gds"
git -C "$REPO" cat-file blob "$GDS_REF" >"$GDS_IN" \
  || die "cannot read $GDS_PATH at $INPUT_REV" 1
[[ -s "$GDS_IN" ]] || die "committed $GDS_PATH is empty" 1
GDS_SHA="$(sha "$GDS_IN")"

# ---- input pin: the GDS the newest committed par.json pins ---------------
# The record must bind to the GDS the committed place-and-route record
# pins in core_flow.gds.sha256, so a future re-route (a new par record and
# a new GDS) cannot leave this DRC record silently describing a superseded
# layout: rerun this script after the new par record lands. Without this
# gate a moved input would record a DRC verdict for bytes no par record
# claims.
PIN_PAR="$(git -C "$REPO" ls-tree -r --name-only "$INPUT_REV" -- flow/core/records/ \
  | grep -E '^flow/core/records/[^/]+/par\.json$' | LC_ALL=C sort | tail -n 1)" || true
[[ -n "$PIN_PAR" ]] || die "no committed flow/core/records/<date>/par.json at HEAD: nothing pins the GDS this run would check" 2
PIN_GDS_SHA="$(git -C "$REPO" cat-file blob "$INPUT_REV:$PIN_PAR" \
  | python3 -I -c 'import json,sys; print(json.load(sys.stdin)["core_flow"]["gds"]["sha256"])' 2>/dev/null)" \
  || die "cannot read core_flow.gds.sha256 from $PIN_PAR at ${INPUT_REV:0:12} (a committed par.json without it is a broken record)" 1
if [[ "$PIN_GDS_SHA" != "$GDS_SHA" ]]; then
  die "input pin mismatch: HEAD:$GDS_PATH is sha256:$GDS_SHA but the newest committed record $PIN_PAR pins sha256:$PIN_GDS_SHA; land the new par record first (run flow/core/par.sh), then rerun this script" 1
fi

# ---- the deck: the pinned build's own file, hash-checked before the run --
DECK_FILE="${KLT_DECK_FILE:-}"
if [[ -z "$DECK_FILE" && -z "${KLT_CMD:-}" ]]; then
  DECK_FILE="$(uvx --quiet --from "$PIN_KLT" python -I -c 'from klayout_tools.decks import asap7_rules as r; print(r.DECK_PATH)')"
fi
[[ -n "$DECK_FILE" && -f "$DECK_FILE" ]] || die "cannot locate the pinned asap7.drc: set KLT_DECK_FILE" 1
DECK_SHA="$(sha "$DECK_FILE")"
[[ "sha256:$DECK_SHA" == "$PIN_DECK" ]] \
  || die "asap7.drc at $DECK_FILE is sha256:$DECK_SHA, not the pin $PIN_DECK (decision 0012)" 1
mkdir -p "$SCRATCH/deck"; cp "$DECK_FILE" "$SCRATCH/deck/asap7.drc"

# ---- run the pinned klt ---------------------------------------------------
# A clean and a violations report are both successful runs of the step: klt
# drc exits non-zero on violations, so usability is judged on the report
# (flow/record_lib.py usable), not on the exit status. --timeout-s 2700:
# klt's 300 s default cannot check a core-sized stream (the counter fits
# comfortably inside it; the 93k-component core GDS does not), and the
# raise is a size accommodation, never a result wait -- the deck's own
# runtime is what it is.
echo "drc.sh: checking $GDS_PATH (sha256:$GDS_SHA) against the pinned deck $PIN_DECK" >&2
rc=0
( cd "$W" && "${KLT[@]}" drc --engine klayout --deck-file "$SCRATCH/deck/asap7.drc" \
    --expect-rule-categories "$EXPECT_CATEGORIES" --timeout-s 2700 --format json "$TOP.gds" ) \
  >"$SCRATCH/drc.out" 2>"$SCRATCH/drc.err" || rc=$?
if ! python3 -I "$REPO/flow/record_lib.py" usable "$SCRATCH/drc.out"; then
  echo "drc.sh: klt drc failed (exit $rc)" >&2
  head -c 2000 "$SCRATCH/drc.out" "$SCRATCH/drc.err" >&2
  exit 1
fi

# ---- validate the report --------------------------------------------------
# The report must name the pinned deck and a known status before anything
# is recorded; a report from any other deck is not the acceptance check.
if ! DRC_ERR="$(python3 -I - "$SCRATCH/drc.out" "$PIN_DECK" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
want_deck = sys.argv[2]
deck = d.get("provenance", {}).get("deck", {}).get("content_hash")
if deck != want_deck:
    print(f"provenance.deck.content_hash is {deck!r}, expected the pin {want_deck!r}")
    sys.exit(1)
if d.get("status") not in ("clean", "violations"):
    print(f"status is {d.get('status')!r}, expected 'clean' or 'violations'")
    sys.exit(1)
PY
)"; then
  die "$DRC_ERR" 1
fi

# ---- stage & validate record before publishing ----------------------------
# Assemble drc.json and tool-versions.txt in scratch and run
# record_leak_guard before creating flow/core/records/$DATE, so a redaction
# miss or tool error never leaves published outputs behind.
STAGE="$SCRATCH/record"; mkdir -p "$STAGE"
record_subs "$SCRATCH/subs.json" "$SCRATCH=<scratch>" "$REPO=<repo>" "$HOME=<home>"
python3 -I - "$SCRATCH/drc.out" "$GDS_SHA" "$PIN_PAR" "$INPUT_REV" <<'PY' | python3 -I "$REPO/flow/record_lib.py" write "$STAGE/drc.json" "$SCRATCH/subs.json"
import json, sys
src, gds_sha, pin_par, input_rev = sys.argv[1:5]
d = json.load(open(src, encoding="utf-8"))
d["core_flow"] = {
    "note": "klt drc of the committed routed GDS on the pinned ASAP7 deck "
            "(decision 0012); predictive PDK, a tool result never a silicon "
            "claim. A violations report is a recorded outcome: every marker "
            "is waived under layout/waivers/ or disclosed by a spec decision "
            "record (decision 0005); nothing is filtered or suppressed.",
    "predicted": True,
    "input_gds": {"path": "layout/cve2_top.gds", "sha256": gds_sha,
                  "top_cell": "cve2_rv32imc_wrapper"},
    "input_pin": {"record": pin_par, "at_commit": input_rev[:12]},
}
print(json.dumps(d))
PY

# One `klt version` ask, the spelling the shared provenance rows record; klt
# has already run successfully by this point, so this only echoes a version.
KLT_V="$("${KLT[@]}" version 2>&1 | head -1 || true)"
{
  provenance_rows flow/core/drc.sh "$KLT_V"
  echo "pinned_drc_deck: $PIN_DECK  ($EXPECT_CATEGORIES categories, decision 0012)"
  echo "gds:          layout/cve2_top.gds  sha256:$GDS_SHA  (blob at HEAD ${INPUT_REV:0:12})"
  echo "input_pin:    $PIN_PAR  (core_flow.gds.sha256 equals the checked blob)"
} >"$STAGE/tool-versions.txt"

record_leak_guard "$STAGE"

# ---- publish dated record --------------------------------------------------
# Records only: each file is installed exclusively (flow/core/record_publish.sh:
# the copy is finished under a private name and linked to its final pathname
# without replacement, so nothing existing is overwritten and a copy that
# fails partway leaves no record behind), and a failure removes exactly what
# this run created.
CREATED=()
OUT_MADE=0
[[ -d "$OUT" ]] || OUT_MADE=1
publish_rollback() {
  local f
  for f in ${CREATED[@]+"${CREATED[@]}"}; do rm -f "$f"; done
  if [[ $OUT_MADE == 1 ]]; then rmdir "$OUT" 2>/dev/null || true; fi
  return 0
}
publish() {
  mkdir -p "$OUT" || return 1
  record_publish "$STAGE" "$OUT" drc.json tool-versions.txt || return 1
  ( record_leak_guard "$OUT" ) || return 1
}
if ! publish; then
  publish_rollback
  die "publishing the record failed; nothing was left published, retry the run" 1
fi

# ---- summary ----------------------------------------------------------------
echo "drc.sh: records -> flow/core/records/$DATE" >&2
python3 -I - "$OUT/drc.json" <<'PY' >&2
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
counts = {}
for v in d.get("violations") or []:
    counts[v.get("rule", "?")] = counts.get(v.get("rule", "?"), 0) + 1
print(f"drc.sh: status={d.get('status')} violation_count={d.get('violation_count')}")
for rule, n in sorted(counts.items()):
    print(f"  {rule}: {n}")
PY
