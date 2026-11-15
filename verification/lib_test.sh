#!/usr/bin/env bash
# Self-test for the record-level host-path guard in verification/lib.sh.
#
# leak_guard is what keeps a committed record from naming a host path: fv.sh
# runs it on report.json after every run, and fv.py's redaction is what should
# make it pass. These cases pin the four roots it must catch, that a redacted
# record passes, and that it fails closed on a file it cannot read. Needs no
# PDK checkout, no klt and no network.
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

guard_case() {  # label want_rc file
  local got=0 err
  err="$(run_guard "$3" 2>&1 >/dev/null)" || got=$?
  if [ "$got" -eq "$2" ]; then ok "$1"; else no "$1: want exit $2, got $got"; fi
  printf '%s' "$err"
}

echo "# 1. each of the four host roots fails the guard"
for root in /home/me /tmp/fv-pos /Users/me /root; do
  printf '{"environment": {"build_log": "%s/x/build_icarus.log"}}\n' "$root" >"$SCRATCH/leak.json"
  err="$(guard_case "a $root/ path fails" 1 "$SCRATCH/leak.json")"
  case "$err" in
    *"leaks an absolute host path"*) ok "a $root/ path names the reason" ;;
    *) no "a $root/ path: no named reason, got: $err" ;;
  esac
done

echo
echo "# 2. the guard is fail closed"
err="$(guard_case "a missing file fails" 1 "$SCRATCH/no-such-file.json")"
case "$err" in
  *"cannot scan"*) ok "a missing file names the reason" ;;
  *) no "a missing file: no named reason, got: $err" ;;
esac

echo
echo "# 3. a redacted record passes"
printf '{"environment": {"build_log": "<scratch>/artifacts/I-add-01/build_icarus.log",\n' \
  >"$SCRATCH/clean.json"
printf '           "netlist": "flow/core/records/2026-11-03/netlist.v"}}\n' >>"$SCRATCH/clean.json"
guard_case "tagged and repo-relative paths pass" 0 "$SCRATCH/clean.json"
printf '{}\n' >"$SCRATCH/empty.json"
guard_case "an empty object passes" 0 "$SCRATCH/empty.json"

echo
if [ "$FAIL" -eq 0 ]; then
  echo "ALL PASS ($PASS case(s))"
  exit 0
fi
echo "FAILURES: $FAIL of $((PASS + FAIL)) case(s)"
exit 1
