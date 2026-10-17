#!/usr/bin/env bash
# Cold-start entry point for the PDK-free cocotb + Icarus harness.
#
#   verification/run.sh                    lint + placeholder test; exit 0 on pass
#   verification/run.sh --negative-control same, but with a deliberately failing
#                                          assertion; exit 0 only if the test FAILS
#
# Tool versions come from verification/tool-versions.txt and
# verification/requirements.txt, never from whatever is on PATH.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV="$HERE/.venv"
NEGATIVE=0
case "${1:-}" in
  "") ;;
  --negative-control) NEGATIVE=1 ;;
  *) echo "usage: run.sh [--negative-control]" >&2; exit 2 ;;
esac

die() { echo "run.sh: $*" >&2; exit 1; }

pinned() { sed -n "s/^$1=//p" "$HERE/tool-versions.txt"; }

check_version() { # name pinned installed
  [ -n "$2" ] || die "no pin for $1 in verification/tool-versions.txt"
  [ -n "$3" ] || die "$1 not found on PATH (pinned: $2)"
  case "$3" in
    "$2"|"$2".*) ;;
    *) die "$1 version mismatch: installed $3, pinned $2 (verification/tool-versions.txt)" ;;
  esac
}

command -v iverilog >/dev/null || die "iverilog not found on PATH"
command -v verilator >/dev/null || die "verilator not found on PATH"
command -v python3 >/dev/null || die "python3 not found on PATH"

check_version iverilog "$(pinned iverilog)" \
  "$(iverilog -V 2>/dev/null | sed -n '1s/.*version \([0-9][0-9.]*\).*/\1/p')"
check_version verilator "$(pinned verilator)" \
  "$(verilator --version | sed -n '1s/^Verilator \([0-9][0-9.]*\).*/\1/p')"
check_version python "$(pinned python)" \
  "$(python3 -c 'import platform; print(platform.python_version())')"

# Venv inside the checkout (gitignored); reinstall when the pin file changes.
if [ ! -x "$VENV/bin/python" ]; then
  python3 -m venv "$VENV"
fi
STAMP="$VENV/.requirements.sha"
WANT="$(sha256sum "$HERE/requirements.txt" | cut -d' ' -f1)"
if [ "$(cat "$STAMP" 2>/dev/null || true)" != "$WANT" ]; then
  "$VENV/bin/python" -m pip install --quiet --disable-pip-version-check -r "$HERE/requirements.txt"
  echo "$WANT" > "$STAMP"
fi

RUN_DIR="$HERE/runs/$(date -u +%Y%m%dT%H%M%SZ)-$$"
mkdir -p "$RUN_DIR"
echo "run dir: $RUN_DIR"

echo "== lint (verilator --lint-only -Wall) =="
verilator --lint-only -Wall --top-module counter "$HERE/smoke/counter.sv"

echo "== cocotb + icarus =="
if [ "$NEGATIVE" = 1 ]; then
  if SMOKE_NEGATIVE_CONTROL=1 "$VENV/bin/python" "$HERE/smoke/runner.py" "$RUN_DIR"; then
    die "negative control: test passed but was expected to fail"
  fi
  echo "negative control: test failed as expected"
  exit 0
fi
"$VENV/bin/python" "$HERE/smoke/runner.py" "$RUN_DIR"
echo "PASS: results in $RUN_DIR/results.xml"
