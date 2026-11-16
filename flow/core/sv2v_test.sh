#!/usr/bin/env bash
# Self-test for the pin read in flow/core/sv2v.sh (issue #126).
#
# Needs no PDK checkout, no klt and no network: every case runs sv2v_ensure in
# a scratch tree holding copies of the real sv2v.sh and fetch_checked.sh plus a
# control spec/core.md, with SV2V pointed at a stub that answers --version with
# the pin, so the pinned release itself is never fetched. The tracked
# spec/core.md is never modified.
#
# The driver runs sv2v_ensure under set -euo pipefail -- the mode both sourcing
# callers (flow/core/synth.sh, verification/core/setup.sh) set, and the one
# that made the original position-dependent read's guard dead.
#
# ASAP7 is a predictive PDK; nothing here is fabricated or measured, and this
# script makes no claim about any design -- it only checks how a pin is read.
#
# Not wired into CI (no step executes shell self-tests, see #125); run by hand.
#
# usage: flow/core/sv2v_test.sh
# Exit status: 0 every case passed; 1 a case failed.
set -uo pipefail

SELF_REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PASS=0
FAIL=0

ok() { PASS=$((PASS + 1)); echo "ok   - $1"; }
no() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }

eq() {  # label want got
  if [[ "$2" == "$3" ]]; then ok "$1"; else no "$1: want '$2', got '$3'"; fi
}

PIN_VERSION="v0.0.13"  # the pins of record, spec/core.md decision 0010; a spec
PIN_SHA="552799a1d76cd177b9b4cc63a3e77823a3d2a6eb4ec006569288abeff28e1ff8"  # bump updates this test in the same PR

# A scratch tree holding copies of the real sv2v.sh + fetch_checked.sh and a
# spec/core.md (a control body if given, else this repo's real spec).
# shellcheck disable=SC2120  # the bare calls are deliberate: no body means the real spec copy
fake_tree() {  # [core-md-body]
  local d; d="$(mktemp -d "${TMPDIR:-/tmp}/asap7-sv2vtest.XXXXXX")"
  FAKES+=("$d")
  mkdir -p "$d/flow/core" "$d/spec" "$d/build"
  cp "$SELF_REPO/flow/core/sv2v.sh" "$d/flow/core/sv2v.sh"
  cp "$SELF_REPO/fetch_checked.sh" "$d/fetch_checked.sh"
  if [[ $# -gt 0 ]]; then printf '%s\n' "$1" >"$d/spec/core.md"
  else cp "$SELF_REPO/spec/core.md" "$d/spec/core.md"; fi
  printf '#!/bin/sh\necho "sv2v %s"\n' "$PIN_VERSION" >"$d/stub"
  chmod +x "$d/stub"
  # One sourcing caller's exact mode: set -euo pipefail, then sv2v_ensure.
  # NO_PIPEFAIL=1 drops pipefail to show the guards fire in both modes.
  cat >"$d/drive.sh" <<'EOF'
set -euo pipefail
[[ -z "${NO_PIPEFAIL:-}" ]] || set +o pipefail
. "$1/flow/core/sv2v.sh"
export SV2V="$2"
sv2v_ensure "$3"
printf '%s\n' "$PIN_SV2V" "$PIN_SV2V_SHA"
EOF
  printf '%s' "$d"
}
FAKES=()
cleanup() { [[ ${#FAKES[@]} -eq 0 ]] || rm -rf "${FAKES[@]}"; }
trap cleanup EXIT

run_ensure() {  # tree -> the two pins on stdout; exit status as a caller sees
  bash "$1/drive.sh" "$1" "$1/stub" "$1/build"
}

expect_fail() {  # label tree want-substring [nopipefail]
  local out err rc
  err="$2/run.err"
  if [[ "${4:-}" == nopipefail ]]; then
    out="$(env NO_PIPEFAIL=1 bash "$2/drive.sh" "$2" "$2/stub" "$2/build" 2>"$err")"; rc=$?
  else
    out="$(bash "$2/drive.sh" "$2" "$2/stub" "$2/build" 2>"$err")"; rc=$?
  fi
  if [[ $rc -eq 1 && -z "$out" ]] && grep -q "$3" "$err"; then
    ok "$1"
  else
    no "$1: rc=$rc, stdout '$out', stderr: $(cat "$err")"
  fi
}

echo "# 1. the real spec reads the pins of record through sv2v_ensure"
TREE="$(fake_tree)"
eq "PIN_SV2V is the pinned version" "$PIN_VERSION" "$(run_ensure "$TREE" | sed -n 1p)"
eq "PIN_SV2V_SHA is the pinned sha" "$PIN_SHA" "$(run_ensure "$TREE" | sed -n 2p)"

echo
echo "# 2. position independence, C1: a superseded version named in unrelated prose"
# The hazard: the old read took the first 'sv2v v<version>' anywhere in the
# document, so a sentence mentioning a superseded release repinned the version
# while leaving the sha untouched -- fetch_checked then reported a mismatch
# that read as a supply-chain alarm.
sed -i '5a An earlier decision converted with sv2v v0.0.11 before 0010 superseded it.' \
  "$TREE/spec/core.md"
eq "C1: version stays $PIN_VERSION" "$PIN_VERSION" "$(run_ensure "$TREE" | sed -n 1p)"
eq "C1: sha stays the pin" "$PIN_SHA" "$(run_ensure "$TREE" | sed -n 2p)"

echo
echo "# 3. position independence, C2b: prose reflowed between the repo anchor and the sha"
# The hazard: the old sha read took the first 64-hex string within two lines of
# 'zachjs/sv2v', so three inserted prose lines emptied it -- and under pipefail
# the caller died before its guard could say why.
awk '{print} /zachjs\/sv2v/{print "prose line one"; print "prose line two"; print "prose line three"}' \
  "$TREE/spec/core.md" >"$TREE/spec.new" && mv "$TREE/spec.new" "$TREE/spec/core.md"
eq "C2b: version stays $PIN_VERSION" "$PIN_VERSION" "$(run_ensure "$TREE" | sed -n 1p)"
eq "C2b: sha survives the reflow" "$PIN_SHA" "$(run_ensure "$TREE" | sed -n 2p)"

echo
echo "# 4. a spec without the labelled paragraph fails closed, naming the label"
CLEAN="$(fake_tree)"
sed -i '/^\*\*sv2v (decision 0010):\*\*/,/^$/d' "$CLEAN/spec/core.md"
expect_fail "no paragraph: exits 1 naming the label (pipefail)" "$CLEAN" \
  "no '\*\*sv2v (decision 0010):\*\*' paragraph"
expect_fail "no paragraph: exits 1 naming the label (no pipefail)" "$CLEAN" \
  "no '\*\*sv2v (decision 0010):\*\*' paragraph" nopipefail

echo
echo "# 5. a paragraph missing one pin fails closed, naming that pin"
NOVER="$(fake_tree)"
sed -i 's/sv2v v0\.0\.13/superseded converter/' "$NOVER/spec/core.md"
expect_fail "no version: exits 1 naming the version pin" "$NOVER" "no 'sv2v v<version>'"

NOSHA="$(fake_tree)"
sed -i 's/[0-9a-f]\{64\}/not-a-sha/' "$NOSHA/spec/core.md"
expect_fail "no sha: exits 1 naming the sha pin" "$NOSHA" "no sha256"

echo
echo "# 6. sv2v.sh stays self-contained: no lib.sh sourced, no foreign failure helper"
if bash -n "$SELF_REPO/flow/core/sv2v.sh"; then ok "bash -n parses sv2v.sh"
else no "bash -n fails on sv2v.sh"; fi
if grep -q 'die' "$SELF_REPO/flow/core/sv2v.sh"; then
  no "sv2v.sh mentions a foreign failure helper (die)"
else ok "no die in sv2v.sh"; fi
if grep -Eq '^[[:space:]]*(\.|source)[[:space:]].*lib\.sh' "$SELF_REPO/flow/core/sv2v.sh"; then
  no "sv2v.sh sources a lib.sh"
else ok "sv2v.sh sources no lib.sh"; fi

echo
echo "flow/core/sv2v_test.sh: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
