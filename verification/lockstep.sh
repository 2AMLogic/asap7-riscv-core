#!/usr/bin/env bash
# Lockstep retirement check: run the riscv-arch-test corpus plus the
# deterministic longer program on cve2_rv32imc_wrapper with every RVFI
# retirement compared against the pinned Spike reference while the simulation
# runs (issue #206, part of #204). See verification/README.md "Lockstep mode".
#
#   verification/lockstep.sh [RUN_DIR]                    exit 0 only if every
#                                                         program matches
#   verification/lockstep.sh --negative-control [RUN_DIR] the longer program
#                                                         clean (must pass),
#                                                         then the same program
#                                                         with one bit of a
#                                                         known write-back
#                                                         corrupted in the
#                                                         observation path;
#                                                         exit 0 only if that
#                                                         exact retirement,
#                                                         pc, destination and
#                                                         value are reported
#
# This lane is deliberately not part of verification/run.sh and its item 9
# attestation: it needs the pinned Spike (a C++ build with dtc/Boost
# prerequisites, verification/core/spike_setup.sh) and runs the whole corpus
# instruction-by-instruction, which the CI budget does not carry (#204 allows
# documenting it as a separate job). Nothing here is installed on the host.
#
# iverilog must be on PATH at the pinned version (as for run.sh); cocotb is
# the verification/requirements.txt pin in the verification venv.
# RUN_DIR defaults to verification/runs/lockstep-<UTC timestamp>-<pid>.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=verification/lib.sh
. "$HERE/lib.sh"
NEGATIVE=0
OUT=""
for arg in "$@"; do
  case "$arg" in
    --negative-control) NEGATIVE=1 ;;
    -*) echo "usage: lockstep.sh [--negative-control] [RUN_DIR]" >&2; exit 2 ;;
    *) OUT="$arg" ;;
  esac
done

check_version iverilog \
  "$(iverilog -V 2>/dev/null | sed -n '1s/.*version \([0-9][0-9.]*\).*/\1/p')"
check_version python \
  "$(python3 -c 'import platform; print(platform.python_version())')"
command -v iverilog >/dev/null || die "iverilog not found on PATH"

"$HERE/core/setup.sh"
"$HERE/core/spike_setup.sh"

# The verification venv run.sh builds (cocotb pin); same bootstrap, no install
# on the host beyond that gitignored tree.
VENV="$HERE/.venv"
if [ ! -x "$VENV/bin/python" ]; then
  python3 -m venv "$VENV"
fi
STAMP="$VENV/.requirements.sha"
WANT="$(sha256sum "$HERE/requirements.txt" | cut -d ' ' -f1)"
if [ "$(cat "$STAMP" 2>/dev/null || true)" != "$WANT" ]; then
  "$VENV/bin/python" -m pip install --quiet --disable-pip-version-check -r "$HERE/requirements.txt"
  echo "$WANT" > "$STAMP"
fi

OUT="${OUT:-$HERE/runs/lockstep-$(date -u +%Y%m%dT%H%M%SZ)-$$}"
mkdir -p "$OUT"
echo "run dir: $OUT"
cd "$HERE/core"
if [ "$NEGATIVE" = 1 ]; then
  set +e
  "$VENV/bin/python" -I lockstep.py "$OUT" --negative-control
  rc=$?
  set -e
  [ -f "$OUT/record.json" ] || die "lockstep.py wrote no record at $OUT/record.json (exit $rc); its output above is the real failure"
  leak_guard "$OUT/record.json"
  [ "$rc" = 0 ] || exit "$rc"
  echo "negative control: the comparator failed on the exact retirement, pc, destination and value"
  exit 0
fi
"$VENV/bin/python" -I lockstep.py "$OUT"
leak_guard "$OUT/record.json"
echo "PASS: results in $OUT/results.xml and $OUT/record.json"
