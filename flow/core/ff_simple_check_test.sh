#!/usr/bin/env bash
# Self-test for the SIMPLE FF/TT identity flag in flow/core/ff_simple_check.py
# (issue #202): the flag must be one equality comparison on the parsed cell
# dictionaries, so a missing cell, a rise/fall kind change with identical
# numbers, or an extra timing table must all flip it to false.
#
# Needs no PDK, no klt, no network and no Liberty archives: each case builds a
# scratch dir of fifteen minimal fixture .lib files (five groups x FF/TT/SS,
# the shape ff_simple_check.py globs) and runs the real script on it, reading
# simple_FF_tables_identical_to_TT back from the produced record. python3 is
# the script under test's own interpreter, so it is the suite's only tool.
#
# Assertions are on the identity flag only, never on verdict wording: the
# verdict bands are spec thresholds, not part of the flag under test.
#
# ASAP7 is a predictive PDK; nothing here is fabricated or measured, and this
# script makes no claim about any design -- it only checks how the identity
# flag compares two parsed table dictionaries.
#
# usage: flow/core/ff_simple_check_test.sh
# Exit status: 0 every case passed; 1 a case failed.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
NPASS=0
NBAD=0

ok() { NPASS=$((NPASS + 1)); echo "ok   - $1"; }
no() { NBAD=$((NBAD + 1)); echo "not ok - $1"; }

eq() {  # label want got
  if [[ "$2" == "$3" ]]; then ok "$1"; else no "$1: want '$2', got '$3'"; fi
}

W="$(mktemp -d "${TMPDIR:-/tmp}/asap7-ffsimpletest.XXXXXX")"
cleanup() { rm -rf "$W"; }
trap cleanup EXIT

# Grids are 6x6 because ff_simple_check.py samples POINTS up to index (5,5).
IDX="0.1, 0.2, 0.3, 0.4, 0.5, 0.6"

table() {  # <kind> <scale> -> one constant 6x6 cell_rise/cell_fall block
  local kind="$1" s="$2" rows row
  row="$s, $s, $s, $s, $s, $s"
  rows="\"$row\""
  for _ in 2 3 4 5 6; do rows+=", \"$row\""; done
  printf '      %s (v) {\n' "$kind"
  printf '        index_1("%s");\n        index_2("%s");\n' "$IDX" "$IDX"
  printf '        values(%s);\n      }\n' "$rows"
}

cellblock() {  # <name:kind:scale[:kind:scale ...]> ... -> liberty cell blocks
  # kind is the liberty keyword itself (cell_rise / cell_fall), so the
  # fixture text carries the exact token the parser matches on.
  local spec name rest kind s
  for spec in "$@"; do
    name="${spec%%:*}"
    rest="${spec#*:}"
    printf '    cell (%s) {\n' "$name"
    while [[ -n "$rest" ]]; do
      kind="${rest%%:*}"
      rest="${rest#*:}"
      if [[ "$rest" == *:* ]]; then s="${rest%%:*}"; rest="${rest#*:}"; else s="$rest"; rest=""; fi
      table "$kind" "$s"
    done
    printf '    }\n'
  done
}

lib() {  # <path> <cellspec ...> -> one minimal fixture liberty file
  local path="$1"; shift
  { printf 'library (fixture) {\n  nom_voltage : 0.7;\n  nom_temperature : 25;\n'
    cellblock "$@"
    printf '}\n'; } >"$path"
}

# scenario <label> <want:true|false> <simple-FF-cellspec ...>
#
# The non-SIMPLE groups keep FF/TT/SS at 5/10/14 so the reference FF/TT ratio
# (~0.5) clears MIN_REF_GAP and the verdict logic runs without a crash; the
# SIMPLE TT fixture holds cells A and B with one rise table each, the shape
# the issue's reproduction varies SIMPLE FF against.
scenario() {
  local label="$1" want="$2"; shift 2
  local d g rc got out
  d="$(mktemp -d "$W/case.XXXXXX")"
  for g in AO OA INVBUF SEQ; do
    lib "$d/asap7sc7p5t_${g}_RVT_TT_nldm_fix.lib" A_ASAP7_75t_R:cell_rise:10:cell_fall:10
    lib "$d/asap7sc7p5t_${g}_RVT_FF_nldm_fix.lib" A_ASAP7_75t_R:cell_rise:5:cell_fall:5
    lib "$d/asap7sc7p5t_${g}_RVT_SS_nldm_fix.lib" A_ASAP7_75t_R:cell_rise:14:cell_fall:14
  done
  lib "$d/asap7sc7p5t_SIMPLE_RVT_TT_nldm_fix.lib" A_ASAP7_75t_R:cell_rise:10 B_ASAP7_75t_R:cell_rise:10
  lib "$d/asap7sc7p5t_SIMPLE_RVT_SS_nldm_fix.lib" A_ASAP7_75t_R:cell_rise:14 B_ASAP7_75t_R:cell_rise:14
  lib "$d/asap7sc7p5t_SIMPLE_RVT_FF_nldm_fix.lib" "$@"
  out="$d/out.json"
  python3 -I "$REPO/flow/core/ff_simple_check.py" "$d" "$out" >"$d/stdout" 2>"$d/stderr"
  rc=$?
  if [[ $rc -ne 0 ]]; then
    no "$label: ff_simple_check.py exited $rc"
    sed 's/^/    /' "$d/stderr"
    return
  fi
  got="$(python3 -I -c 'import json,sys
print("true" if json.load(open(sys.argv[1]))["simple_FF_tables_identical_to_TT"] else "false")' "$out")"
  eq "$label: simple_FF_tables_identical_to_TT" "$want" "$got"
}

# Control: identical cells and tables -> true.
scenario "identical tables report true" true \
  A_ASAP7_75t_R:cell_rise:10 B_ASAP7_75t_R:cell_rise:10

# Cell B absent from SIMPLE FF: zip over an empty list used to read as a
# vacuous pass -> must be false.
scenario "cell missing from FF reports false" false \
  A_ASAP7_75t_R:cell_rise:10

# B's table is cell_fall with the same numbers as TT's cell_rise: slicing the
# kind off used to compare them equal -> must be false.
scenario "rise/fall kind change reports false" false \
  A_ASAP7_75t_R:cell_rise:10 B_ASAP7_75t_R:cell_fall:10

# An extra FF timing table with an otherwise matching prefix: zip truncation
# used to hide it -> must be false.
scenario "extra FF table reports false" false \
  A_ASAP7_75t_R:cell_rise:10:cell_fall:10 B_ASAP7_75t_R:cell_rise:10

echo "1..$((NPASS + NBAD)) pass=$NPASS fail=$NBAD"
[[ "$NBAD" -eq 0 ]]
