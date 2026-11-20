#!/usr/bin/env bash
# Regenerate the `klt functional-verification` report for the core arch-test suite.
#
#   verification/fv.sh [OUT_DIR]                    exit 0 only if every test passes
#   verification/fv.sh --negative-control [OUT_DIR] flipped signature word; exit 0
#                                                   only if the report evidences that
#                                                   one-word mismatch (any other
#                                                   failure stays a failure)
#
# klt comes from the pinned release (klayout_tools in verification/tool-versions.txt),
# fetched with uvx into a throwaway env; cocotb is the verification/requirements.txt
# pin. iverilog must be on PATH at the pinned version (as for run.sh).
# OUT_DIR defaults to verification/runs/fv-<UTC timestamp>-<pid>; report.json inside.
# After the run a leak_guard scan fails the script if report.json still names a
# host path (fv.py redacts the two roots it knows; the guard catches any other).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=verification/lib.sh
. "$HERE/lib.sh"
NEGATIVE=0
OUT=""
for arg in "$@"; do
  case "$arg" in
    --negative-control) NEGATIVE=1 ;;
    -*) echo "usage: fv.sh [--negative-control] [OUT_DIR]" >&2; exit 2 ;;
    *) OUT="$arg" ;;
  esac
done
KLT_VER="$(pin klayout_tools)"
PY_VER="$(pin python)"
COCOTB="$(sed -n 's/^\(cocotb==[^ ]*\).*/\1/p' "$HERE/requirements.txt")"; [ -n "$COCOTB" ] || die "no cocotb pin"
check_version iverilog \
  "$(iverilog -V 2>/dev/null | sed -n '1s/.*version \([0-9][0-9.]*\).*/\1/p')"
command -v uvx >/dev/null || die "uvx not found on PATH"

OUT="${OUT:-$HERE/runs/fv-$(date -u +%Y%m%dT%H%M%SZ)-$$}"
mkdir -p "$OUT"
"$HERE/core/setup.sh"

export KLT_CMD="uvx --python $PY_VER --from klayout-tools==$KLT_VER --with $COCOTB klt"
cd "$HERE/core"
if [ "$NEGATIVE" = 1 ]; then
  # A reused OUT_DIR must not satisfy the verdict below with a previous run's
  # report: only evidence fv.py writes during this invocation counts, so drop
  # any stale report before the run (fv.py writes none if it dies early).
  rm -f "$OUT/report.json"
  rc=0; python3 -I fv.py "$OUT" --negative-control || rc=$?
  # core/test_archtest.py flips exactly one expected signature word, so the
  # injected mismatch is a one-word signature diff in the failed test_signature
  # assertion fv.py records -- the same fingerprint run.sh's core control pins.
  fv_negative_control_verdict python3 "$rc" "$OUT/report.json" \
    ': 1/[0-9]+ signature words differ'
  leak_guard "$OUT/report.json"
  echo "negative control: run failed as expected"
  exit 0
fi
rc=0; python3 -I fv.py "$OUT" || rc=$?
[ -f "$OUT/report.json" ] || die "fv.py wrote no report at $OUT/report.json (fv.py exit $rc); its output above is the real failure"
leak_guard "$OUT/report.json"
exit "$rc"
