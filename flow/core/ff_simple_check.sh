#!/usr/bin/env bash
# Evidence run for the SIMPLE RVT FF Liberty anomaly (spec/pdk-bringup.md section 5).
# Extracts the RVT FF/TT/SS Liberty of the five asap7sc7p5t_28 groups from the
# pinned checkout, runs ff_simple_check.py, and writes
# flow/core/records/<date>/ff-simple-check.json (append-only: a re-run needs a
# new RECORD_DATE).
#
# ASAP7 is a predictive PDK; nothing here is fabricated or measured.
#
# usage: flow/core/ff_simple_check.sh <asap7-checkout>     (or set ASAP7_DIR)
#
# Environment: RECORD_DATE (record directory name, default today UTC);
#              NO_UPSTREAM=1 skips the later-upstream-commit check (recorded as "not checked").
# Exit status: 0 ok; 1 a step failed; 2 refused invocation.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=flow/lib.sh
source "$REPO/flow/lib.sh"

ASAP7_ARG="${1:-${ASAP7_DIR:-}}"
[[ -n "$ASAP7_ARG" ]] || die "usage: flow/core/ff_simple_check.sh <asap7-checkout> (or set ASAP7_DIR)"
[[ -d "$ASAP7_ARG" ]] || die "not a directory: $ASAP7_ARG"
ASAP7="$(cd "$ASAP7_ARG" && pwd)"
CELLS="$ASAP7/asap7sc7p5t_28"

PIN_UPSTREAM="$(spec_sha 'Upstream repo')" || exit 1
PIN_CELLS="$(spec_sha 'Cell library')" || exit 1
check_pin "$ASAP7" "$PIN_UPSTREAM" "upstream asap7"
check_pin "$CELLS" "$PIN_CELLS" "submodule asap7sc7p5t_28"

setup_scratch ffsimple
new_record_dir core

# Liberty ships as .7z only: extract it with the shared counted extractor
# (flow/lib.sh), which fails closed unless each of FF, TT and SS has exactly
# its five group archives -- the counted check this script used to carry.
extract_rvt_liberty "$ASAP7" "$SCRATCH" FF TT SS

python3 -I "$REPO/flow/core/ff_simple_check.py" "$SCRATCH" "$SCRATCH/check.json"

# Item 4: does a later upstream asap7sc7p5t_28 commit touch the SIMPLE FF file?
UPSTREAM="not checked"
if [[ "${NO_UPSTREAM:-0}" != 1 ]] && git -C "$CELLS" fetch -q origin 2>/dev/null; then
  HEADSHA="$(git -C "$CELLS" rev-parse origin/HEAD 2>/dev/null || true)"
  if [[ -n "$HEADSHA" ]]; then
    UPSTREAM="$(git -C "$CELLS" log --format='%H %cs %s' "$PIN_CELLS..$HEADSHA" -- \
      'LIB/NLDM/asap7sc7p5t_SIMPLE_RVT_FF_nldm_*' | paste -sd'|' -)"
    UPSTREAM="remote head $HEADSHA; commits after pin touching the SIMPLE RVT FF Liberty: ${UPSTREAM:-none}"
  fi
fi

python3 -I - "$SCRATCH/check.json" "$OUT/ff-simple-check.json" "$PIN_CELLS" "$UPSTREAM" <<'PY'
import json, sys
src, dst, pin, upstream = sys.argv[1:]
rec = json.load(open(src))
rec["pinned_asap7sc7p5t_28"] = pin
rec["later_upstream_check"] = upstream
open(dst, "w").write(json.dumps(rec, indent=2, sort_keys=True) + "\n")
PY
echo "ok    wrote ${OUT#"$REPO"/}/ff-simple-check.json"
