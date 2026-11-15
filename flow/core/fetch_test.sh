#!/usr/bin/env bash
# Self-test for the CVE2 fetch contract: flow/core/fetch.sh, the pinned
# download-and-verify path whose entire job is to fail closed on a bad pin.
#
# Covers the three outcomes of the contract -- success, hash mismatch,
# download failure -- and the all-or-nothing staging promise: the out-dir is
# replaced only after every file verifies, so a failed run leaves a
# pre-existing good out-dir byte-identical and never creates a fresh one.
#
# Needs no network and writes nothing inside the checkout: the pinned
# upstream is stood in by a file:// fixture root, the lock by a throwaway
# two-file CVE2_LOCK, and the out-dir by scratch paths under mktemp -d. The
# real reuse.lock.json is never read as a fixture.
#
# Assertions are on exit status and filesystem state only, never on message
# text: the failure wording changed while exit codes and filesystem effects
# did not, and curl writes its own stderr lines on a download failure. The
# scripts' output is kept in the scratch dir and shown only on an unexpected
# result.
#
# ASAP7 is a predictive PDK; nothing here is fabricated or measured, and this
# script makes no claim about any design -- it only checks how pinned sources
# are fetched and verified.
#
# usage: flow/core/fetch_test.sh
# Exit status: 0 every case passed; 1 a case failed.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
NPASS=0
NBAD=0

ok() { NPASS=$((NPASS + 1)); echo "ok   - $1"; }
no() { NBAD=$((NBAD + 1)); echo "not ok - $1"; }

W="$(mktemp -d "${TMPDIR:-/tmp}/asap7-fetchtest.XXXXXX")"
cleanup() { rm -rf "$W"; }
trap cleanup EXIT

# A fixture root shaped like the pinned upstream: CVE2_BASE_URL is suffixed
# with the import's commit, so the fixtures must sit under a <commit>/
# directory at their upstream-relative paths -- without that directory the
# success case would fail as a download error and pass for the wrong reason.
COMMIT=0123456789abcdef0123456789abcdef01234567
mkdir -p "$W/root/$COMMIT/rtl"
printf 'module fixture_a; endmodule\n' >"$W/root/$COMMIT/rtl/a.sv"
printf 'module fixture_b; endmodule\n' >"$W/root/$COMMIT/rtl/b.sv"
SA="$(sha256sum "$W/root/$COMMIT/rtl/a.sv" | cut -d' ' -f1)"
SB="$(sha256sum "$W/root/$COMMIT/rtl/b.sv" | cut -d' ' -f1)"

# Throwaway locks in exactly the shape fetch.sh reads: imports[] with
# from == "openhwgroup/cve2", a commit, and files[].{upstream,sha256}.
# Never the real reuse.lock.json, which names 32 files at a network commit.
lock() {  # <file> <sha-for-a> <sha-for-b>
  printf '{"imports":[{"from":"openhwgroup/cve2","commit":"%s","files":[\n' "$COMMIT" >"$1"
  printf '  {"upstream":"rtl/a.sv","sha256":"%s"},\n' "$2" >>"$1"
  printf '  {"upstream":"rtl/b.sv","sha256":"%s"}]}]}\n' "$3" >>"$1"
}
ZERO=0000000000000000000000000000000000000000000000000000000000000000
GOOD="$W/good.lock.json"
BAD_LATE="$W/bad-late.lock.json"
BAD_FIRST="$W/bad-first.lock.json"
lock "$GOOD" "$SA" "$SB"
lock "$BAD_LATE" "$SA" "$ZERO"
lock "$BAD_FIRST" "$ZERO" "$SB"

fetch() {  # <lock> <base-url> <out-dir>; the out-dir is always fetch.sh's $1 --
  # never its git-ignored default, which a rm -rf would take to. Its output
  # lands in the scratch dir: wording is not part of the contract under test.
  local rc=0
  CVE2_LOCK="$1" CVE2_BASE_URL="$2" "$REPO/flow/core/fetch.sh" "$3" \
    >"$W/last-run.log" 2>&1 || rc=$?
  return "$rc"
}
show_log() { sed 's/^/        /' "$W/last-run.log"; }

tree_sha() {  # <dir> -> an order-independent content fingerprint, or empty
  # if the directory does not exist; comparing two empties would look equal,
  # so callers guard on the first fingerprint being non-empty.
  (cd "$1" && find . -type f -print0 | sort -z | xargs -0 sha256sum)
}

echo "# 1. a good lock fetches every file to its upstream-relative path"
OUT1="$W/out"
rc=0; fetch "$GOOD" "file://$W/root" "$OUT1" || rc=$?
if [[ $rc -eq 0 ]]; then
  ok "success exits 0"
else
  no "success exited $rc"; show_log
fi
if [[ -f "$OUT1/rtl/a.sv" && -f "$OUT1/rtl/b.sv" ]]; then
  ok "the out-dir holds both files at their upstream-relative paths"
else
  no "the out-dir is missing a file:"; show_log; find "$OUT1" 2>/dev/null | sed 's/^/        /'
fi
if cmp -s "$OUT1/rtl/a.sv" "$W/root/$COMMIT/rtl/a.sv" \
   && cmp -s "$OUT1/rtl/b.sv" "$W/root/$COMMIT/rtl/b.sv"; then
  ok "the fetched contents are the fixtures, byte for byte"
else
  no "fetched contents differ from the fixtures"
fi

echo
echo "# 2. a bad pin on the last file fails closed; the good tree survives"
BEFORE="$(tree_sha "$OUT1")"
rc=0; fetch "$BAD_LATE" "file://$W/root" "$OUT1" || rc=$?
if [[ $rc -eq 1 ]]; then
  ok "a zeroed sha256 exits 1"
else
  no "a zeroed sha256 exited $rc"; show_log
fi
AFTER="$(tree_sha "$OUT1")"
if [[ -n "$BEFORE" && "$BEFORE" == "$AFTER" ]]; then
  ok "the pre-existing out-dir is unchanged after the failure (contents compared)"
else
  no "the pre-existing out-dir changed across the failure"
fi

echo
echo "# 3. a bad pin on the first file fails closed on a fresh out-dir"
OUT2="$W/out2"
rc=0; fetch "$BAD_FIRST" "file://$W/root" "$OUT2" || rc=$?
if [[ $rc -eq 1 ]]; then
  ok "a zeroed sha256 on the first file exits 1"
else
  no "a zeroed sha256 on the first file exited $rc"; show_log
fi
if [[ ! -e "$OUT2" ]]; then
  ok "no out-dir is created on the failure"
else
  no "a fresh out-dir appeared on the failure"
fi

echo
echo "# 4. an unreachable base URL fails closed"
OUT3="$W/out3"
rc=0; fetch "$GOOD" "file://$W/no-such-root" "$OUT3" || rc=$?
if [[ $rc -eq 1 ]]; then
  ok "a download failure exits 1"
else
  no "a download failure exited $rc"; show_log
fi
if [[ ! -e "$OUT3" ]]; then
  ok "no out-dir is created on the failure"
else
  no "a fresh out-dir appeared on the failure"
fi

echo
echo "flow/core/fetch_test.sh: $NPASS passed, $NBAD failed"
[[ $NBAD -eq 0 ]]
