# shellcheck shell=bash
# Shared plumbing for the verification scripts (verification/run.sh,
# verification/fv.sh, verification/core/setup.sh). Sourced, not executed.
#
# The counterpart of flow/lib.sh for the PDK-free harness: kept separate so
# verification/ does not have to source the PDK flow helpers, and so the one
# place that reads verification/tool-versions.txt lives beside that file.
#
# These helpers read tool pins only; they make no claim about any design.
#
# Provides:
#   die <msg>                  message prefixed with the script name, exit 1
#   pin <key>                  value of <key> in verification/tool-versions.txt;
#                              dies when the key is missing or empty, so a
#                              misspelled key fails closed instead of reading
#                              as "unpinned"
#   check_version <key> <got>  refuse an installed tool whose version is not the
#                              pinned one; <got> matches the pin exactly or as a
#                              more specific revision of it (5.050 -> 5.050.1)
#   leak_guard <file>          die when <file> still names an absolute host path
#                              (/home/, /tmp/, /Users/, /root/ -- the same
#                              four-root grep flow/smoke/run.sh runs on its own
#                              records); a file that cannot be read fails too.
#                              A committed record names no host path: an input
#                              is pinned by identity, not location.
#   negative_control_verdict <python> <runner-exit> <results.xml> <fingerprint>
#                              the one verdict rule behind run.sh's public
#                              negative controls: die unless the runner's
#                              tests-failed exit (exactly 1) is backed by JUnit
#                              evidence that the intended comparison ran and
#                              detected the injected mismatch -- a testcase
#                              exists and its failure message matches
#                              <fingerprint>, the shape the injected mismatch
#                              produces (run.sh pins one per bench, beside the
#                              testbench that emits it). Startup, build and
#                              report-writing failures propagate directly: any
#                              other exit, or a missing, unparseable or
#                              testcase-less report, dies.
#   fv_negative_control_verdict <python> <runner-exit> <report.json> <fingerprint>
#                              the same verdict rule behind fv.sh's negative
#                              control, whose evidence is fv.py's KLT JSON
#                              report instead of JUnit: die unless fv.py's
#                              tests-failed exit (exactly 1) is backed by a
#                              failed testcase inside a non-error klt response
#                              whose error_message matches <fingerprint>
#                              (fv.sh pins the core one-word signature diff,
#                              the same fingerprint run.sh's core control
#                              uses). A tohost timeout, a multi-word mismatch,
#                              an infrastructure-error response, an unexpected
#                              pass, or a missing, unparseable or result-less
#                              report, dies.
#
# verification/lib_test.sh checks leak_guard: each of the four roots fails with
# the named reason, a redacted record passes, and an unreadable file fails
# closed. It also checks negative_control_verdict on synthetic reports: both
# genuine injected mismatches pass; wrong exit codes, a missing, unparseable or
# testcase-less report, an unrelated failure and an unexpected pass all die.
# And it checks fv_negative_control_verdict on mutations of the committed KLT
# negative-control record (verification/records/2026-11-05/...): the recorded
# one-word mismatch passes; the tohost timeout, a multi-word mismatch, a
# message-less failure, an all-pass report, a klt error response, malformed or
# missing JSON and wrong exits all die.
# It needs no PDK checkout, no klt, no simulator and no network.
#
# PINS is derived from this file's own location, so a caller in any directory
# reads the same pin file.

PINS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/tool-versions.txt"

die() { echo "$(basename "$0"): $*" >&2; exit 1; }

pin() {  # key
  local v
  v="$(sed -n "s/^$1=//p" "$PINS")"
  [ -n "$v" ] || die "no pin for $1 in verification/tool-versions.txt"
  printf '%s\n' "$v"
}

check_version() {  # key installed-version
  local want
  want="$(pin "$1")" || exit 1
  [ -n "$2" ] || die "$1 not found on PATH (pinned: $want)"
  case "$2" in
    "$want"|"$want".*) ;;
    *) die "$1 version mismatch: installed $2, pinned $want (verification/tool-versions.txt)" ;;
  esac
}

leak_guard() {  # file
  local m rc=0
  m="$(grep -nE '(/home/|/tmp/|/Users/|/root/)' "$1")" || rc=$?
  if [ "$rc" -eq 0 ]; then
    printf '%s\n' "$m" >&2
    die "$1 leaks an absolute host path"
  fi
  [ "$rc" -eq 1 ] || die "leak_guard: cannot scan $1 (grep exit $rc)"
}

negative_control_verdict() {  # python runner-exit results.xml fingerprint
  local py=$1 rc=$2 xml=$3 fp=$4
  [ "$rc" -eq 1 ] \
    || die "negative control: runner exit $rc (want 1, the runner's tests-failed exit); the output above is a real failure, not the injected mismatch"
  [ -f "$xml" ] || die "negative control: no JUnit report at $xml (the runner died before writing it)"
  "$py" -I - "$xml" "$fp" <<'PYEOF' || die "negative control: no evidence the intended comparison ran and detected the injected mismatch (see above)"
import re
import sys
import xml.etree.ElementTree as ET

xml_path, fingerprint = sys.argv[1], sys.argv[2]
try:
    root = ET.parse(xml_path).getroot()
except ET.ParseError as exc:
    sys.exit(f"negative control: {xml_path} does not parse: {exc}")
tests = list(root.iter("testcase"))
if not tests:
    sys.exit(f"negative control: {xml_path} names no testcase - the intended comparison never ran")
pat = re.compile(fingerprint)
for tc in tests:
    for bad in (*tc.findall("failure"), *tc.findall("error")):
        # cocotb 2.x writes the assertion text in error_msg=; other JUnit
        # writers put it in message= or the element text. Accept all three.
        msg = " ".join(x for x in (bad.get("error_msg"), bad.get("message"),
                                   (bad.text or "").strip()) if x)
        if pat.search(msg):
            print(f"negative control: intended mismatch detected: "
                  f"{tc.get('classname') or ''}{'.' if tc.get('classname') else ''}"
                  f"{tc.get('name', '?')}: {msg[:160]}")
            sys.exit(0)
if any(t.find("failure") is not None or t.find("error") is not None for t in tests):
    sys.exit(f"negative control: failed testcase(s) in {xml_path} match no injected "
             f"mismatch ({fingerprint}) - unrelated failure")
sys.exit(f"negative control: every testcase in {xml_path} passed - the injected mismatch went undetected")
PYEOF
}

# fv.py's report.json is klt's JSON, not JUnit, so the same verdict rule needs
# its own reader: the evidence that the intended comparison ran and detected
# the injected mismatch is a failed testcase in a non-error klt response whose
# error_message matches the fingerprint. fv.sh drops any report left by a
# previous run in a reused OUT_DIR before invoking fv.py, so the report this
# rule reads is always the one this invocation wrote.
fv_negative_control_verdict() {  # python runner-exit report.json fingerprint
  local py=$1 rc=$2 rep=$3 fp=$4
  [ "$rc" -eq 1 ] \
    || die "negative control: fv.py exit $rc (want 1, its tests-failed exit); the output above is a real failure, not the injected mismatch"
  [ -f "$rep" ] || die "negative control: no report at $rep (fv.py died before writing it)"
  "$py" -I - "$rep" "$fp" <<'PYEOF' || die "negative control: no evidence the intended comparison ran and detected the injected mismatch (see above)"
import json
import re
import sys

rep_path, fingerprint = sys.argv[1], sys.argv[2]
try:
    with open(rep_path, encoding="utf-8") as fh:
        report = json.load(fh)
except (OSError, ValueError) as exc:
    sys.exit(f"negative control: {rep_path} does not read as JSON: {exc}")
results = report.get("results") if isinstance(report, dict) else None
if not isinstance(results, list) or not results:
    sys.exit(f"negative control: {rep_path} names no test result - the intended comparison never ran")
responses = []
for x in results:
    resp = x.get("response") if isinstance(x, dict) else None
    if not isinstance(resp, dict):
        sys.exit(f"negative control: {rep_path} has a result without a klt response - malformed evidence")
    responses.append(resp)
for resp in responses:
    if resp.get("status") == "error":
        sys.exit(f"negative control: klt reported an infrastructure error in {rep_path} - not the injected mismatch")
pat = re.compile(fingerprint)
failed = []
for resp in responses:
    tests = resp.get("tests")
    if not isinstance(tests, list):
        continue
    failed += [t for t in tests if isinstance(t, dict) and t.get("status") == "failed"]
for t in failed:
    msg = t.get("error_message")
    if isinstance(msg, str) and pat.search(msg):
        print(f"negative control: intended mismatch detected: "
              f"{t.get('name', '?')}: {msg[:160]}")
        sys.exit(0)
if failed:
    sys.exit(f"negative control: failed testcase(s) in {rep_path} match no injected "
             f"mismatch ({fingerprint}) - unrelated failure")
sys.exit(f"negative control: every testcase in {rep_path} passed - the injected mismatch went undetected")
PYEOF
}
