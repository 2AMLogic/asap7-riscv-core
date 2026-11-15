#!/usr/bin/env bash
# Self-test for the shared helpers in flow/lib.sh: the label-anchored,
# fail-closed pin reads, the synthesized-netlist locator, and the shared
# provenance-row head of the flow tool-versions.txt records.
#
# Needs no PDK checkout, no klt and no network: every case is either a read of
# this repo's own spec/, a read of a crafted spec/ in a scratch tree, or a run
# of a helper over crafted scratch files with its tool asks stubbed.
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

echo
echo "flow/lib_test.sh: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
