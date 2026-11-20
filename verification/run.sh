#!/usr/bin/env bash
# Cold-start entry point for the PDK-free cocotb + Icarus harness.
#
#   verification/run.sh                    lint + placeholder test; exit 0 on pass
#   verification/run.sh --negative-control same, but with a deliberately wrong
#                                          expected count; exit 0 only when the
#                                          JUnit report shows that comparison
#                                          ran and detected the mismatch
#   verification/run.sh --core             riscv-arch-test I/M/C on the RV32IMC core
#                                          (cve2_rv32imc_wrapper), signatures vs Sail
#   verification/run.sh --core --negative-control
#                                          same with one expected signature word
#                                          flipped; exit 0 only when the JUnit
#                                          report shows the flip was detected
#   verification/run.sh --core --gate      same programs on the committed synthesized
#                                          netlist + pinned ASAP7 cell Verilog
#                                          (zero-delay, pre-layout); writes record.json
#   verification/run.sh --core --gate --negative-control
#                                          flipped word; exit 0 only when the JUnit
#                                          report shows the flip was detected
#
# Every negative control goes through one verdict rule,
# negative_control_verdict in lib.sh: the runner's tests-failed exit (exactly
# 1) must be backed by JUnit evidence that the intended comparison ran and
# detected the injected mismatch. Startup, build and report-writing failures
# propagate directly instead of reading as a pass.
#
# Tool versions come from verification/tool-versions.txt and
# verification/requirements.txt, never from whatever is on PATH.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=verification/lib.sh
. "$HERE/lib.sh"
VENV="$HERE/.venv"
NEGATIVE=0
CORE=0
GATE=0
for arg in "$@"; do
  case "$arg" in
    --negative-control) NEGATIVE=1 ;;
    --core) CORE=1 ;;
    --gate) GATE=1 ;;
    *) echo "usage: run.sh [--core [--gate]] [--negative-control]" >&2; exit 2 ;;
  esac
done
[ "$GATE" = 0 ] || [ "$CORE" = 1 ] || { echo "run.sh: --gate needs --core" >&2; exit 2; }

command -v iverilog >/dev/null || die "iverilog not found on PATH"
command -v verilator >/dev/null || die "verilator not found on PATH"
command -v python3 >/dev/null || die "python3 not found on PATH"

check_version iverilog \
  "$(iverilog -V 2>/dev/null | sed -n '1s/.*version \([0-9][0-9.]*\).*/\1/p')"
check_version verilator \
  "$(verilator --version | sed -n '1s/^Verilator \([0-9][0-9.]*\).*/\1/p')"
check_version python \
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

if [ "$CORE" = 1 ]; then
  "$HERE/core/setup.sh"
  ARGS=()
  [ "$GATE" = 1 ] && ARGS+=(--gate)
  if [ "$GATE" = 1 ]; then
    echo "== riscv-arch-test I/M/C on the committed gate-level netlist + ASAP7 RVT cell models (zero-delay, pre-layout) =="
  else
    echo "== riscv-arch-test I/M/C on cve2_rv32imc_wrapper (cocotb + icarus) =="
  fi
  if [ "$NEGATIVE" = 1 ]; then
    rc=0
    "$VENV/bin/python" "$HERE/core/runner.py" "$RUN_DIR" --negative-control "${ARGS[@]}" || rc=$?
    # core/test_archtest.py flips exactly one expected word, so the injected
    # mismatch is a one-word signature diff; the failed testcase stays visible
    # in $RUN_DIR/results.xml and, for --gate, in record.json.
    negative_control_verdict "$VENV/bin/python" "$rc" "$RUN_DIR/results.xml" \
      ': 1/[0-9]+ signature words differ'
    exit 0
  fi
  "$VENV/bin/python" "$HERE/core/runner.py" "$RUN_DIR" "${ARGS[@]}"
  echo "PASS: results in $RUN_DIR/results.xml"
  exit 0
fi

echo "== lint (verilator --lint-only -Wall) =="
verilator --lint-only -Wall --top-module counter "$HERE/smoke/counter.sv"

echo "== cocotb + icarus =="
if [ "$NEGATIVE" = 1 ]; then
  rc=0
  SMOKE_NEGATIVE_CONTROL=1 "$VENV/bin/python" "$HERE/smoke/runner.py" "$RUN_DIR" || rc=$?
  # smoke/test_counter.py expects 99 instead of the real count 5, so the
  # injected mismatch fails the final count comparison with a
  # "count=N, expected 99" message; any other failure stays a failure.
  negative_control_verdict "$VENV/bin/python" "$rc" "$RUN_DIR/results.xml" \
    'count=[0-9]+, expected 99'
  exit 0
fi
"$VENV/bin/python" "$HERE/smoke/runner.py" "$RUN_DIR"
echo "PASS: results in $RUN_DIR/results.xml"
