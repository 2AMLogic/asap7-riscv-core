#!/usr/bin/env bash
# Self-test for the shared helpers in flow/lib.sh: the label-anchored,
# fail-closed pin reads, the synthesized-netlist locator, the shared
# provenance-row head of the flow tool-versions.txt records, the
# record-selection rule behind synth.sh --check, and extract_rvt_liberty's
# counted fail-closed guard.
#
# Needs no PDK checkout, no klt and no network: every case is either a read of
# this repo's own spec/, a read of a crafted spec/ or records/ tree in a
# scratch directory, or a run of a helper over crafted scratch files with its
# tool asks stubbed.
#
# ASAP7 is a predictive PDK; nothing here is fabricated or measured, and this
# script makes no claim about any design -- it only checks how a pin is read
# and how a record directory is selected.
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
echo "# 5. synth_netlist: the newest synthesized netlist, or nothing"
NW="$(mktemp -d "${TMPDIR:-/tmp}/asap7-libtest-net.XXXXXX")"; FAKES+=("$NW")
mkdir -p "$NW/.klt/synthesize/old" "$NW/.klt/synthesize/new"
printf 'module old.\n' >"$NW/.klt/synthesize/old/counter_synth.v"
printf 'module new.\n' >"$NW/.klt/synthesize/new/counter_synth.v"
printf 'module other.\n' >"$NW/.klt/synthesize/new/other_synth.v"
touch -d '2026-01-01 00:00:01' "$NW/.klt/synthesize/old/counter_synth.v"
touch -d '2026-01-01 00:00:02' "$NW/.klt/synthesize/new/counter_synth.v" "$NW/.klt/synthesize/new/other_synth.v"
eq "synth_netlist picks the newest match" \
  "$NW/.klt/synthesize/new/counter_synth.v" \
  "$(read_pin "$SELF_REPO" "synth_netlist $NW counter")"
eq "synth_netlist is empty when nothing matches" \
  "" "$(read_pin "$SELF_REPO" "synth_netlist $NW nosuchtop")"

echo
echo "# 6. provenance_rows: one klt row, keyed klt:, carrying the klt version ask"
STUBS="$(mktemp -d "${TMPDIR:-/tmp}/asap7-libtest-stubs.XXXXXX")"; FAKES+=("$STUBS")
for t in yosys python3 uvx; do
  printf '#!/usr/bin/env bash\necho "stub %s"\n' "$t" >"$STUBS/$t"
  chmod +x "$STUBS/$t"
done
rows() {
  PATH="$STUBS:$PATH" bash -c '
    set -euo pipefail
    source "$REPO_LIB"
    PIN_KLT=klayout-tools==0.9.0 PIN_UPSTREAM=upstream-sha PIN_CELLS=cells-sha
    provenance_rows flow/x.sh "klt 0.9.0"
  '
}
eq "header names the writing script" \
  "# Tool and input versions for flow/x.sh (predictive PDK; nothing here is fabricated)" \
  "$(rows | head -1)"
eq "the one klt row is keyed klt: with the klt version ask" \
  "klt:          klt 0.9.0  (klayout-tools==0.9.0)" \
  "$(rows | grep '^klt:')"
eq "shared rows carry exactly the shared vocabulary" \
  "asap7 asap7sc7p5t_28 klt py7zr python uv yosys" \
  "$(rows | grep -oE '^[a-z0-9_.]+:' | tr -d ':' | sort | tr '\n' ' ' | sed 's/ $//')"

echo "# 7. newest_record_with selects the newest record directory holding the file"
# The issue #105 shape: flow/core/records/ is written by two flows and only
# synth.sh's directories hold a netlist.v, so selection must follow the
# content, not the directory sort order.
R="$(mktemp -d "${TMPDIR:-/tmp}/asap7-libtest.XXXXXX")"; FAKES+=("$R")
mkdir -p "$R/records/2026-11-03" "$R/records/2026-11-05"
printf 'old\n' >"$R/records/2026-11-03/netlist.v"
printf '{}\n' >"$R/records/2026-11-05/ff-simple-check.json"
eq "the #105 shape: the older synthesis record is selected past a netlist-less dir" \
  "$R/records/2026-11-03/" \
  "$(read_pin "$SELF_REPO" "newest_record_with '$R/records' netlist.v")"

mkdir -p "$R/records/2026-11-14"
printf 'new\n' >"$R/records/2026-11-14/netlist.v"
eq "the newest directory holding the file is selected" "$R/records/2026-11-14/" \
  "$(read_pin "$SELF_REPO" "newest_record_with '$R/records' netlist.v")"

mkdir -p "$R/records/2026-11-20"
printf '{}\n' >"$R/records/2026-11-20/ff-simple-check.json"
eq "a newer netlist-less directory still does not take over selection" \
  "$R/records/2026-11-14/" \
  "$(read_pin "$SELF_REPO" "newest_record_with '$R/records' netlist.v")"

got="$(read_pin "$SELF_REPO" "newest_record_with '$R/no-file-anywhere' netlist.v" 2>/dev/null)"; rc=$?
if [[ $rc -ne 0 && -z "$got" ]]; then
  ok "no directory holds the file: exits $rc with no value"
else
  no "no directory holds the file: fell through with rc=$rc, value '$got'"
fi

got="$(read_pin "$SELF_REPO" "newest_record_with '$R/no-such-root' netlist.v" 2>/dev/null)"; rc=$?
if [[ $rc -ne 0 && -z "$got" ]]; then
  ok "records root absent entirely: exits $rc with no value"
else
  no "records root absent: fell through with rc=$rc, value '$got'"
fi

S="$(mktemp -d "${TMPDIR:-/tmp}/asap7-libtest.XXXXXX")"; FAKES+=("$S")
mkdir -p "$S/records/2026-11-03"
printf 'only\n' >"$S/records/2026-11-03/netlist.v"
eq "a single directory holding the file is selected" "$S/records/2026-11-03/" \
  "$(read_pin "$SELF_REPO" "newest_record_with '$S/records' netlist.v")"

E="$(mktemp -d "${TMPDIR:-/tmp}/asap7-libtest.XXXXXX")"; FAKES+=("$E")
mkdir -p "$E/records/2026-11-03"
got="$(read_pin "$SELF_REPO" "newest_record_with '$E/records' netlist.v" 2>/dev/null)"; rc=$?
if [[ $rc -ne 0 && -z "$got" ]]; then
  ok "an existing but empty record directory is skipped, not selected: exits $rc"
else
  no "empty record directory: fell through with rc=$rc, value '$got'"
fi

D="$(mktemp -d "${TMPDIR:-/tmp}/asap7-libtest.XXXXXX")"; FAKES+=("$D")
mkdir -p "$D/records/2026-11-03/netlist.v"
got="$(read_pin "$SELF_REPO" "newest_record_with '$D/records' netlist.v" 2>/dev/null)"; rc=$?
if [[ $rc -ne 0 && -z "$got" ]]; then
  ok "a netlist.v that is a directory rather than a file does not qualify: exits $rc"
else
  no "directory-shaped netlist.v: fell through with rc=$rc, value '$got'"
fi

echo
echo "# 8. the record-writing path still refuses an existing record set"
EX="$(fake_repo '# pins
not read here')"
mkdir -p "$EX/flow/core/records/2026-11-03"
printf '{}\n' >"$EX/flow/core/records/2026-11-03/synth.json"
got="$(read_pin "$EX" 'RECORD_DATE=2026-11-03; new_record_dir core' 2>/dev/null)"; rc=$?
if [[ $rc -ne 0 && -z "$got" ]]; then
  ok "new_record_dir refuses an existing record set (exit $rc)"
else
  no "new_record_dir wrote into an existing record set: rc=$rc"
fi

FREE="$(fake_repo '# pins
not read here')"
eq "new_record_dir on a free date still sets OUT" \
  "$FREE/flow/core/records/2026-12-25" \
  "$(read_pin "$FREE" 'RECORD_DATE=2026-12-25; new_record_dir core; printf "%s" "$OUT"')"

echo
echo "# 9. extract_rvt_liberty fails closed on a wrong archive count"
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
