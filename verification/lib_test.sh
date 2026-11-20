#!/usr/bin/env bash
# Self-test for the record-level host-path guard and the negative-control
# verdict rules (JUnit and KLT JSON) in verification/lib.sh.
#
# leak_guard is what keeps a committed record from naming a host path: fv.sh
# runs it on report.json after every run, and fv.py's redaction is what should
# make it pass. These cases pin the four roots it must catch, that a redacted
# record passes, and that it fails closed on a file it cannot read.
#
# negative_control_verdict is the one exit rule behind run.sh's public
# negative controls (issue #208): a control passes only on JUnit evidence
# that the intended comparison ran and detected the injected mismatch, so a
# runner that dies at startup (any exit but the tests-failed 1, or no report)
# can no longer read as a pass. The cases pin both bench fingerprints against
# the exact failure-message shapes the testbenches emit.
#
# fv_negative_control_verdict is the same rule for fv.sh's negative control
# (issue #213), whose evidence is fv.py's KLT JSON report: the cases work from
# the committed November 5 negative-control record -- the real failure shape
# fv.py writes -- and each rejection is a small mutation of it, so a drift in
# what fv.py records breaks here loudly. Needs no PDK checkout, no klt, no
# simulator and no network (python3 stdlib only).
#
# usage: verification/lib_test.sh
# Exit status: 0 every case passed; 1 a case failed.
#
# shellcheck disable=SC2016  # the single-quoted body below is literal on
# purpose: it is a `bash -c` program run in a fresh shell, sourcing the real
# lib.sh the way fv.sh does.
set -uo pipefail

SELF_REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0

ok() { PASS=$((PASS + 1)); echo "ok   - $1"; }
no() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }

SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/asap7-verify-libtest.XXXXXX")"
cleanup() { rm -rf "$SCRATCH"; }
trap cleanup EXIT

# Run leak_guard on $1 in a fresh bash that sources the real lib.sh under
# set -euo pipefail, as fv.sh does. Exit status is leak_guard's.
run_guard() {
  VERIFY_LIB="$SELF_REPO/verification/lib.sh" bash -c '
    set -euo pipefail
    . "$VERIFY_LIB"
    leak_guard "$1"
  ' leak_guard "$1"
}

guard_case() {  # label want_rc file [want_reason]
  local got=0 err
  err="$(run_guard "$3" 2>&1 >/dev/null)" || got=$?
  if [ "$got" -eq "$2" ]; then ok "$1"; else no "$1: want exit $2, got $got"; fi
  if [ $# -ge 4 ]; then
    case "$err" in
      *"$4"*) ok "$1: names the reason" ;;
      *) no "$1: expected reason \"$4\", got: $err" ;;
    esac
  fi
}

echo "# 1. each of the four host roots fails the guard"
for root in /home/me /tmp/fv-pos /Users/me /root; do
  printf '{"environment": {"build_log": "%s/x/build_icarus.log"}}\n' "$root" >"$SCRATCH/leak.json"
  guard_case "a $root/ path fails" 1 "$SCRATCH/leak.json" "leaks an absolute host path"
done

echo
echo "# 2. the guard is fail closed"
guard_case "a missing file fails" 1 "$SCRATCH/no-such-file.json" "cannot scan"

echo
echo "# 3. a redacted record passes"
printf '{"environment": {"build_log": "<scratch>/artifacts/I-add-01/build_icarus.log",\n' \
  >"$SCRATCH/clean.json"
printf '           "netlist": "flow/core/records/2026-11-03/netlist.v"}}\n' >>"$SCRATCH/clean.json"
guard_case "tagged and repo-relative paths pass" 0 "$SCRATCH/clean.json"
printf '{}\n' >"$SCRATCH/empty.json"
guard_case "an empty object passes" 0 "$SCRATCH/empty.json"

# ---- negative_control_verdict (the one verdict rule behind run.sh's public
# ---- negative controls; issue #208) ----------------------------------------
#
# The rule is fed the same evidence run.sh feeds it: the runner's exit status,
# the JUnit report it wrote, and the fingerprint of the failure message the
# injected mismatch produces. The fixtures below pin both fingerprints against
# the exact shapes the testbenches emit (cocotb 2.x writes error_msg=), so a
# drift in either the message or the pattern breaks here loudly.

SMOKE_FP='count=[0-9]+, expected 99'
CORE_FP=': 1/[0-9]+ signature words differ'

mk_failure_xml() {  # outfile failure-attr failure-message
  {
    printf '<testsuites name="results">\n  <testsuite name="all">\n'
    printf '    <testcase name="test_counts_when_enabled" classname="test_counter">\n'
    printf '      <failure %s="%s" />\n' "$2" "$3"
    printf '    </testcase>\n  </testsuite>\n</testsuites>\n'
  } >"$1"
}

mk_failure_xml "$SCRATCH/ok-smoke.xml" error_msg "count=5, expected 99"
mk_failure_xml "$SCRATCH/ok-core.xml" error_msg \
  "I-add-01: 1/588 signature words differ, first at word 294: dut=33333336, sail=33333337"
mk_failure_xml "$SCRATCH/ok-core-msgattr.xml" message \
  "I-add-01: 1/588 signature words differ, first at word 294: dut=33333336, sail=33333337"
mk_failure_xml "$SCRATCH/unrelated.xml" error_msg \
  "I-add-01: no store to tohost within 3000000 cycles"
mk_failure_xml "$SCRATCH/multiword.xml" error_msg \
  "I-add-01: 5/588 signature words differ, first at word 294: dut=33333336, sail=33333337"
printf '<testsuites name="results">\n  <testsuite name="all">\n' >"$SCRATCH/passing.xml"
printf '    <testcase name="test_counts_when_enabled" classname="test_counter" />\n' >>"$SCRATCH/passing.xml"
printf '  </testsuite>\n</testsuites>\n' >>"$SCRATCH/passing.xml"
printf '<testsuites name="results"><testsuite name="all"></testsuite></testsuites>\n' \
  >"$SCRATCH/notests.xml"
printf '<testsuites name="results"><testsuite name="al' >"$SCRATCH/broken.xml"

# Run negative_control_verdict on ($1..$4 = python rc xml fingerprint) in a
# fresh bash that sources the real lib.sh under set -euo pipefail, as run.sh
# does. Exit status is the verdict's.
run_verdict() {
  VERIFY_LIB="$SELF_REPO/verification/lib.sh" bash -c '
    set -euo pipefail
    . "$VERIFY_LIB"
    negative_control_verdict "$1" "$2" "$3" "$4"
  ' negative_control_verdict "$1" "$2" "$3" "$4"
}

verdict_case() {  # label want_rc python rc xml fp [want_reason]
  local got=0 out
  out="$(run_verdict "$3" "$4" "$5" "$6" 2>&1)" || got=$?
  if [ "$got" -eq "$2" ]; then ok "$1"; else no "$1: want exit $2, got $got"; fi
  if [ $# -ge 7 ]; then
    case "$out" in
      *"$7"*) ok "$1: names the reason" ;;
      *) no "$1: expected reason \"$7\", got: $out" ;;
    esac
  fi
}

echo
echo "# 4. the genuine injected mismatches satisfy the control"
verdict_case "the wrong count is detected (error_msg attr)" 0 python3 1 "$SCRATCH/ok-smoke.xml" "$SMOKE_FP" "intended mismatch detected"
verdict_case "the flipped signature word is detected" 0 python3 1 "$SCRATCH/ok-core.xml" "$CORE_FP" "intended mismatch detected"
verdict_case "the flip is detected via a message= attribute too" 0 python3 1 "$SCRATCH/ok-core-msgattr.xml" "$CORE_FP" "intended mismatch detected"

echo
echo "# 5. a startup, build or report-writing failure never reads as a pass"
verdict_case "runner exit 17 (startup death) fails" 1 python3 17 "$SCRATCH/ok-smoke.xml" "$SMOKE_FP" "runner exit 17"
verdict_case "runner exit 2 fails" 1 python3 2 "$SCRATCH/ok-core.xml" "$CORE_FP" "runner exit 2"
verdict_case "no JUnit report fails" 1 python3 1 "$SCRATCH/no-such-results.xml" "$SMOKE_FP" "no JUnit report"
verdict_case "an unparseable report fails" 1 python3 1 "$SCRATCH/broken.xml" "$SMOKE_FP" "does not parse"
verdict_case "a report naming no testcase fails" 1 python3 1 "$SCRATCH/notests.xml" "$CORE_FP" "names no testcase"

echo
echo "# 6. only the injected mismatch satisfies the control"
verdict_case "an unrelated test failure fails" 1 python3 1 "$SCRATCH/unrelated.xml" "$CORE_FP" "unrelated failure"
verdict_case "a multi-word mismatch is not the one-word flip" 1 python3 1 "$SCRATCH/multiword.xml" "$CORE_FP" "unrelated failure"
verdict_case "an unexpected pass fails" 1 python3 1 "$SCRATCH/passing.xml" "$SMOKE_FP" "undetected"
verdict_case "runner exit 0 (unexpected pass) fails" 1 python3 0 "$SCRATCH/ok-smoke.xml" "$SMOKE_FP" "runner exit 0"

# ---- fv_negative_control_verdict (fv.sh's negative control; issue #213) ----
#
# Same rule, KLT JSON evidence instead of JUnit: fv.py's report.json. The base
# fixture is the committed negative-control record -- the exact shape fv.py
# wrote on 2026-11-05 -- and every case is that record or a small mutation of
# it, so the pin is against real recorded evidence, not a hand-written shape.

FV_RECORD="$SELF_REPO/verification/records/2026-11-05/klt-fv-core-archtest-negative-control.json"
FV_FP=': 1/[0-9]+ signature words differ'

fv_mutate() {  # outfile python-statement (applied to a copy of the record)
  python3 - "$FV_RECORD" "$1" "$2" <<'EOF'
import json, sys
report = json.load(open(sys.argv[1]))
exec(sys.argv[3], {"report": report})
json.dump(report, open(sys.argv[2], "w"), indent=2)
EOF
}

fv_mutate "$SCRATCH/fv-ok.json" "pass"
fv_mutate "$SCRATCH/fv-timeout.json" \
  'report["results"][0]["response"]["tests"][0]["error_message"] = "I-add-01: no store to tohost within 1 cycles"'
fv_mutate "$SCRATCH/fv-multiword.json" \
  'm = report["results"][0]["response"]["tests"][0]; m["error_message"] = m["error_message"].replace("1/588", "2/588", 1)'
fv_mutate "$SCRATCH/fv-nomsg.json" \
  'del report["results"][0]["response"]["tests"][0]["error_message"]'
fv_mutate "$SCRATCH/fv-pass.json" \
  'r = report["results"][0]["response"]; t = r["tests"][0]; report["tests_failed"] = 0; report["results"][0]["exit_code"] = 0; r["status"] = "pass"; r["passed_count"] = 1; r["failed_count"] = 0; t["status"] = "passed"; t.pop("error_type", None); t.pop("error_message", None)'
fv_mutate "$SCRATCH/fv-error.json" \
  'report["results"][0]["response"]["status"] = "error"'
fv_mutate "$SCRATCH/fv-noresults.json" \
  'report["results"] = []'
printf '{"results": [{"test": "I-add-01"' >"$SCRATCH/fv-broken.json"

# Run fv_negative_control_verdict on ($1..$4 = python rc report fp) in a fresh
# bash that sources the real lib.sh under set -euo pipefail, as fv.sh does.
# Exit status is the verdict's.
run_fv_verdict() {
  VERIFY_LIB="$SELF_REPO/verification/lib.sh" bash -c '
    set -euo pipefail
    . "$VERIFY_LIB"
    fv_negative_control_verdict "$1" "$2" "$3" "$4"
  ' fv_negative_control_verdict "$1" "$2" "$3" "$4"
}

fv_case() {  # label want_rc python rc report fp [want_reason]
  local got=0 out
  out="$(run_fv_verdict "$3" "$4" "$5" "$6" 2>&1)" || got=$?
  if [ "$got" -eq "$2" ]; then ok "$1"; else no "$1: want exit $2, got $got"; fi
  if [ $# -ge 7 ]; then
    case "$out" in
      *"$7"*) ok "$1: names the reason" ;;
      *) no "$1: expected reason \"$7\", got: $out" ;;
    esac
  fi
}

echo
echo "# 7. the recorded one-word mismatch satisfies the FV control"
fv_case "the committed record's flipped word is detected" 0 python3 1 "$SCRATCH/fv-ok.json" "$FV_FP" "intended mismatch detected"

echo
echo "# 8. any other FV outcome never reads as a pass"
fv_case "the tohost timeout is not the mismatch" 1 python3 1 "$SCRATCH/fv-timeout.json" "$FV_FP" "unrelated failure"
fv_case "a multi-word mismatch is not the one-word flip" 1 python3 1 "$SCRATCH/fv-multiword.json" "$FV_FP" "unrelated failure"
fv_case "a failed test with no message fails" 1 python3 1 "$SCRATCH/fv-nomsg.json" "$FV_FP" "unrelated failure"
fv_case "an all-pass report fails" 1 python3 1 "$SCRATCH/fv-pass.json" "$FV_FP" "undetected"
fv_case "a klt infrastructure error fails" 1 python3 1 "$SCRATCH/fv-error.json" "$FV_FP" "infrastructure error"
fv_case "a report naming no test result fails" 1 python3 1 "$SCRATCH/fv-noresults.json" "$FV_FP" "names no test result"
fv_case "a malformed report fails" 1 python3 1 "$SCRATCH/fv-broken.json" "$FV_FP" "does not read as JSON"
fv_case "no report fails" 1 python3 1 "$SCRATCH/no-such-fv-report.json" "$FV_FP" "no report at"
fv_case "fv.py exit 17 (startup death) fails" 1 python3 17 "$SCRATCH/fv-ok.json" "$FV_FP" "fv.py exit 17"
fv_case "fv.py exit 0 (unexpected pass) fails" 1 python3 0 "$SCRATCH/fv-ok.json" "$FV_FP" "fv.py exit 0"

echo
if [ "$FAIL" -eq 0 ]; then
  echo "ALL PASS ($PASS case(s))"
  exit 0
fi
echo "FAILURES: $FAIL of $((PASS + FAIL)) case(s)"
exit 1
