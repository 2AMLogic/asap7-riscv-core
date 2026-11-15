#!/usr/bin/env bash
# Self-test for the label-anchored, fail-closed pin reads in flow/lib.sh.
#
# Needs no PDK checkout, no klt and no network: every case is either a read of
# this repo's own spec/ or a read of a crafted spec/ in a scratch tree.
#
# ASAP7 is a predictive PDK; nothing here is fabricated or measured, and this
# script makes no claim about any design -- it only checks how a pin is read.
#
# usage: flow/lib_test.sh
# Exit status: 0 every case passed; 1 a case failed.
#
# shellcheck disable=SC2016  # the single-quoted bodies below are literal on
# purpose: they are `bash -c` programs run in a fresh shell, and crafted spec
# prose that must keep its own backticks and $-free text unexpanded.
set -uo pipefail

SELF_REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0

ok() { PASS=$((PASS + 1)); echo "ok   - $1"; }
no() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }

eq() {  # label want got
  if [[ "$2" == "$3" ]]; then ok "$1"; else no "$1: want '$2', got '$3'"; fi
}

# Run one helper in a fresh bash with REPO pointed at $1, as the flow scripts
# call it: set -euo pipefail, plain assignment, `|| exit 1`. Prints the value on
# stdout; returns the exit status the flow script would take.
read_pin() {  # repo expr
  local repo="$1"; shift
  env -u KLT_CMD bash -c '
    set -euo pipefail
    REPO="$1"
    source "$REPO_LIB"
    V="$(eval "$2")" || exit 1
    printf "%s\n" "$V"
  ' _ "$repo" "$1"
}
export REPO_LIB="$SELF_REPO/flow/lib.sh"

# A scratch repo holding only the two spec files the helpers read.
fake_repo() {  # core-md-body
  local d; d="$(mktemp -d "${TMPDIR:-/tmp}/asap7-libtest.XXXXXX")"
  FAKES+=("$d")
  mkdir -p "$d/spec"
  printf '%s\n' "$1" >"$d/spec/core.md"
  cp "$SELF_REPO/spec/pdk-bringup.md" "$d/spec/pdk-bringup.md"
  printf '%s' "$d"
}
FAKES=()
cleanup() { [[ ${#FAKES[@]} -eq 0 ]] || rm -rf "${FAKES[@]}"; }
trap cleanup EXIT

echo "# 1. the real spec reads the pins of record"
eq "spec_klt_pin is the flow pin"      "klayout-tools==0.9.0" "$(read_pin "$SELF_REPO" 'spec_klt_pin')"
eq "PIN_DECK is the pinned DRC deck" \
  "sha256:14f146f02cd731de3e0b59452eadfdab9c2c947724a219a1002a31b5e0f12d13" \
  "$(read_pin "$SELF_REPO" "spec_pin 'equal to the pinned hash' 'sha256:[0-9a-f]\{64\}' 1")"
eq "PIN_LVS_DECK is the pinned LVS deck" \
  "sha256:5c58a50e5f6a9099810b3fde37eaa8d93b0897653cb6597a831baac1f5ebee76" \
  "$(read_pin "$SELF_REPO" "spec_pin 'pinned LVS deck hash' 'sha256:[0-9a-f]\{64\}' 1")"
eq "spec_sha reads the upstream asap7 pin" \
  "d24f8b857ff74cf5b21ab18a7e1b11a3954c449b" "$(read_pin "$SELF_REPO" "spec_sha 'Upstream repo'")"

echo
echo "# 2. a label that does not match fails closed (never an empty pin)"
for expr in \
  "spec_pin 'no such label in the spec' 'klayout-tools==[0-9][0-9.]*'" \
  "spec_pin 'equal to the pinned hash' 'sha256:[0-9a-f]\{64\}' 0" \
  "spec_sha 'No Such Row'" ; do
  got="$(read_pin "$SELF_REPO" "$expr" 2>/dev/null)"; rc=$?
  if [[ $rc -ne 0 && -z "$got" ]]; then
    ok "exits $rc with no value: $expr"
  else
    no "fell through with rc=$rc, value '$got': $expr"
  fi
done

echo
echo "# 3. the pin survives a reorder of the spec paragraph (the point of the change)"
# The hazard: spec/core.md states the flow pin (0.9.0) and the signoff pin
# (0.8.0) two lines apart in one paragraph. `head -1` picks whichever is written
# first, so swapping two prose sentences silently repins DRC, LVS and the smoke
# flow. The label is attached to the flow pin, so the anchored read does not care.
SWAPPED="$(fake_repo '## PDK and tools (pinned)

- `klt signoff` stays at `klayout-tools==0.8.0` (decision 0008).
- `klt`: release `klayout-tools==0.9.0` is the pinned release for DRC, LVS and the smoke flow
  (decision 0012).')"
eq "reordered pins: anchored read still gets 0.9.0" \
  "klayout-tools==0.9.0" "$(read_pin "$SWAPPED" 'spec_klt_pin')"
eq "reordered pins: the old head -1 read would have got 0.8.0 (contrast only)" \
  "klayout-tools==0.8.0" \
  "$(grep -o 'klayout-tools==[0-9][0-9.]*' "$SWAPPED/spec/core.md" | head -1)"

# Same hazard for PIN_DECK: a superseded deck hash written out in full above the
# pinned one. Today spec/core.md is safe only because the superseded 0005 hash is
# written truncated.
SUPERSEDED="$(fake_repo '## DRC / LVS acceptance

- Decision 0005 pinned
  `sha256:08dba3ee00000000000000000000000000000000000000000000000000000000`
  (263 categories), superseded.
- The report`s `provenance.deck.content_hash` equal to the pinned hash:
  `sha256:14f146f02cd731de3e0b59452eadfdab9c2c947724a219a1002a31b5e0f12d13`
  (267 categories; decision 0012).')"
eq "superseded hash above the pin: anchored read still gets the pin" \
  "sha256:14f146f02cd731de3e0b59452eadfdab9c2c947724a219a1002a31b5e0f12d13" \
  "$(read_pin "$SUPERSEDED" "spec_pin 'equal to the pinned hash' 'sha256:[0-9a-f]\{64\}' 1")"
eq "superseded hash above the pin: the old head -1 read would have gated on it (contrast only)" \
  "sha256:08dba3ee00000000000000000000000000000000000000000000000000000000" \
  "$(grep -o 'sha256:[0-9a-f]\{64\}' "$SUPERSEDED/spec/core.md" | head -1)"

echo
echo "# 4. klt_cmd builds one KLT array, KLT_CMD overrides it"
eq "default is the pinned release through uvx --quiet" \
  "uvx|--quiet|--from|klayout-tools==0.9.0|klt" \
  "$(env -u KLT_CMD bash -c 'set -euo pipefail; source "$REPO_LIB"
                             klt_cmd klayout-tools==0.9.0
                             IFS="|"; printf "%s\n" "${KLT[*]}"')"
eq "KLT_CMD overrides the whole command" \
  "my-klt|--flag" \
  "$(KLT_CMD='my-klt --flag' bash -c 'set -euo pipefail; source "$REPO_LIB"
                                      klt_cmd klayout-tools==0.9.0
                                      IFS="|"; printf "%s\n" "${KLT[*]}"')"

echo
echo "# 5. extract_rvt_liberty fails closed on a wrong archive count"
# The counted guard is the point of the helper: a requested corner without
# exactly its five group archives must die before the py7zr env is built --
# the empty-glob fall-through that used to hand merge_lib.py a literal
# `*_RVT_<c>_nldm_*.lib` filename. The expectation is 5 per corner asked for,
# so a single-corner caller is not wrong by construction (contrast the
# literal 15 the all-corners copy asserted). These cases die before uvx runs,
# so they need no py7zr, no network and no PDK checkout.
fake_libdir() {  # corner n-groups -> a fake asap7 checkout whose NLDM holds
  # the first <n-groups> of the five group archives for <corner>
  local d; d="$(mktemp -d "${TMPDIR:-/tmp}/asap7-libtest.XXXXXX")"
  mkdir -p "$d/asap7sc7p5t_28/LIB/NLDM"
  local corner="$1" n="$2" g
  for g in AO INVBUF OA SEQ SIMPLE; do
    [[ "$n" -gt 0 ]] || break
    : >"$d/asap7sc7p5t_28/LIB/NLDM/asap7sc7p5t_${g}_RVT_${corner}_nldm_g0.lib.7z"
    n=$((n - 1))
  done
  printf '%s\n' "$d"
}
run_extract() {  # dir corner... -> the extractor's combined output
  local dir="$1"; shift
  bash -c 'set -euo pipefail
           REPO="$1" DEST="$2" ASAP7="$3"; shift 3
           source "$REPO/flow/lib.sh"
           extract_rvt_liberty "$ASAP7" "$DEST" "$@"' \
    _ "$SELF_REPO" "$dir/dest" "$dir" "$@" 2>&1
}
expect_counted_die() {  # label want-found want-corner dir corner...
  local label="$1" want_found="$2" want_corner="$3" dir="$4"; shift 4
  local got rc
  got="$(run_extract "$dir" "$@")"; rc=$?
  if [[ $rc -eq 0 ]]; then no "$label: exited 0, expected a counted die"; return; fi
  if grep -q "expected 5 RVT Liberty archives for corner $want_corner" <<<"$got" \
     && grep -q "found $want_found" <<<"$got"; then
    ok "$label"
  else
    no "$label: rc=$rc, output '$got'"
  fi
}
expect_counted_die "corner with no archive dies counted (found 0)" \
  0 FF "$(fake_libdir FF 0)" FF
expect_counted_die "partial corner dies counted (found 2)" \
  2 SS "$(fake_libdir SS 2)" SS
expect_counted_die "a good first corner does not excuse the next (TT found 0)" \
  0 TT "$(fake_libdir FF 5)" FF TT

echo
echo "flow/lib_test.sh: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
