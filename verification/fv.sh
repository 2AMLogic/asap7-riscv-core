#!/usr/bin/env bash
# Regenerate the `klt functional-verification` report for the core arch-test suite.
#
#   verification/fv.sh [OUT_DIR]                    exit 0 only if every test passes
#   verification/fv.sh --negative-control [OUT_DIR] flipped signature word; exit 0
#                                                   only if the run FAILS
#
# klt comes from the pinned release (klayout_tools in verification/tool-versions.txt),
# fetched with uvx into a throwaway env; cocotb is the verification/requirements.txt
# pin. iverilog must be on PATH at the pinned version (as for run.sh).
# OUT_DIR defaults to verification/runs/fv-<UTC timestamp>-<pid>; report.json inside.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NEGATIVE=0
OUT=""
for arg in "$@"; do
  case "$arg" in
    --negative-control) NEGATIVE=1 ;;
    -*) echo "usage: fv.sh [--negative-control] [OUT_DIR]" >&2; exit 2 ;;
    *) OUT="$arg" ;;
  esac
done
die() { echo "fv.sh: $*" >&2; exit 1; }
pinned() { sed -n "s/^$1=//p" "$HERE/tool-versions.txt"; }

KLT_VER="$(pinned klayout_tools)"; [ -n "$KLT_VER" ] || die "no klayout_tools pin in verification/tool-versions.txt"
COCOTB="$(sed -n 's/^\(cocotb==[^ ]*\).*/\1/p' "$HERE/requirements.txt")"; [ -n "$COCOTB" ] || die "no cocotb pin"
IV="$(iverilog -V 2>/dev/null | sed -n '1s/.*version \([0-9][0-9.]*\).*/\1/p')"
case "$IV" in "$(pinned iverilog)"|"$(pinned iverilog)".*) ;; *) die "iverilog $IV != pinned $(pinned iverilog)" ;; esac
command -v uvx >/dev/null || die "uvx not found on PATH"

OUT="${OUT:-$HERE/runs/fv-$(date -u +%Y%m%dT%H%M%SZ)-$$}"
mkdir -p "$OUT"
"$HERE/core/setup.sh"

export KLT_CMD="uvx --python $(pinned python) --from klayout-tools==$KLT_VER --with $COCOTB klt"
cd "$HERE/core"
if [ "$NEGATIVE" = 1 ]; then
  rc=0; python3 -I fv.py "$OUT" --negative-control || rc=$?
  [ "$rc" = 1 ] && [ -f "$OUT/report.json" ] || die "negative control: expected a reported test failure, got exit $rc"
  python3 -I -c 'import json,sys; r=json.load(open(sys.argv[1])); sys.exit(0 if r["tests_failed"]>=1 and all(x["response"].get("status")!="error" for x in r["results"]) else 1)' "$OUT/report.json" \
    || die "negative control: no genuine test failure in $OUT/report.json"
  echo "negative control: run failed as expected"
  exit 0
fi
python3 -I fv.py "$OUT"
