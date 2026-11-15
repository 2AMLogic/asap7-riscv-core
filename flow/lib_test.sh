#!/usr/bin/env bash
# Self-test for flow/lib.sh: the label-anchored, fail-closed pin reads, and
# the record plumbing -- the leak guard and the substitution order behind
# flow/*/records/.
#
# Needs no PDK checkout, no klt and no network: every case is either a read of
# this repo's own spec/ or flow/ scripts, or a read of a crafted spec/ or
# record directory in a scratch tree.
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
echo "# 5. record_leak_guard: the post-write host-path check every core record must pass"

# A scratch record directory whose files are the given name=content pairs.
recdir() {  # [name=content]...
  local d kv
  d="$(mktemp -d "${TMPDIR:-/tmp}/asap7-libtest.XXXXXX")"
  FAKES+=("$d")
  for kv in "$@"; do printf '%s\n' "${kv#*=}" >"$d/${kv%%=*}"; done
  printf '%s\n' "$d"
}

# Run record_leak_guard on $1 in a fresh shell, as the flow scripts call it;
# combined output in GUARD_OUT, its exit status in GUARD_RC.
run_guard() {  # dir
  GUARD_RC=0
  GUARD_OUT="$(bash -c 'set -euo pipefail; REPO="$1"; source "$REPO_LIB"; record_leak_guard "$2"' \
    _ "$SELF_REPO" "$1" 2>&1)" || GUARD_RC=$?
}

CLEAN='{"step":"synth","predicted":true}'

d="$(recdir "synth.json=$CLEAN")"
run_guard "$d"
eq "clean *.json, no tool-versions.txt (ff_simple_check.sh's real shape): passes" "0" "$GUARD_RC"

for root in /home/ /tmp/ /Users/ /root/; do
  d="$(recdir "synth.json={\"tool\":\"$root bin/tool\"}")"
  run_guard "$d"
  if [[ $GUARD_RC -ne 0 ]] && grep -qF 'synth.json' <<<"$GUARD_OUT" \
     && grep -qF 'leaks an absolute host path' <<<"$GUARD_OUT"; then
    ok "planted $root dies naming the file"
  else
    no "planted $root: rc=$GUARD_RC out='${GUARD_OUT:0:80}'"
  fi
done

d="$(recdir "synth.json=$CLEAN" "tool-versions.txt=klt: klayout-tools==0.9.0")"
run_guard "$d"
eq "clean *.json + clean tool-versions.txt: passes" "0" "$GUARD_RC"

d="$(recdir "synth.json=$CLEAN" "tool-versions.txt=iverilog: /home/ubuntu/bin/iverilog")"
run_guard "$d"
if [[ $GUARD_RC -ne 0 ]] && grep -qF 'tool-versions.txt' <<<"$GUARD_OUT" \
   && grep -qF 'leaks an absolute host path' <<<"$GUARD_OUT"; then
  ok "leaking tool-versions.txt beside a clean record dies, naming it"
else
  no "leaking tool-versions.txt: rc=$GUARD_RC out='${GUARD_OUT:0:80}'"
fi

# The guard reads bytes, not JSON structure: a path inside a nested array dies.
d="$(recdir 'synth.json={"a":["clean",{"b":["/Users/ops/x"]},["/root/y"]]}')"
run_guard "$d"
eq "host path only inside a nested array dies" "1" "$GUARD_RC"

# Fails closed: no *.json at all -- including when a tool-versions.txt exists.
d="$(recdir "tool-versions.txt=klt: klayout-tools==0.9.0")"
run_guard "$d"
if [[ $GUARD_RC -ne 0 ]] && grep -qF 'no *.json record' <<<"$GUARD_OUT" \
   && ! grep -qF 'leaks an absolute host path' <<<"$GUARD_OUT"; then
  ok "a record dir holding only tool-versions.txt dies with its own reason"
else
  no "json-less dir with tool-versions.txt: rc=$GUARD_RC out='${GUARD_OUT:0:80}'"
fi

d="$(recdir)"
run_guard "$d"
eq "an empty record dir dies too" "1" "$GUARD_RC"

# Fails closed: a candidate grep cannot read dies rather than passing (grep
# exits 2; note this case assumes a non-root runner, as chmod 000 is a no-op
# for root).
d="$(recdir "synth.json=$CLEAN")"
chmod 000 "$d/synth.json"
run_guard "$d"
if [[ $GUARD_RC -ne 0 ]] && grep -qF 'grep failed' <<<"$GUARD_OUT" \
   && ! grep -qF 'leaks an absolute host path' <<<"$GUARD_OUT"; then
  ok "an unreadable record dies with its own reason (grep exit 2)"
else
  no "unreadable record: rc=$GUARD_RC out='${GUARD_OUT:0:80}'"
fi

echo
echo "# 6. the four-root substitution order: a checkout path tags <asap7-checkout>, never <home>/..."

FH="$(mktemp -d "${TMPDIR:-/tmp}/asap7-libtest.XXXXXX")"; FAKES+=("$FH")
FS="$(mktemp -d "${TMPDIR:-/tmp}/asap7-libtest.XXXXXX")"; FAKES+=("$FS")
FR="$(mktemp -d "${TMPDIR:-/tmp}/asap7-libtest.XXXXXX")"; FAKES+=("$FR")
FOUT="$(mktemp -d "${TMPDIR:-/tmp}/asap7-libtest.XXXXXX")"; FAKES+=("$FOUT")
FA="$FH/asap7"  # the checkout normally lives under the operator's home

# The write-through pair synth.sh uses: record_subs in the smoke order, then
# flow/record_lib.py write. make_record <scratch> <asap7> <repo> <home> <dest>
# [smoke|wrong] -- "wrong" puts $ASAP7 after $HOME, the mis-tagging trap.
make_record() {  # scratch asap7 repo home dest [order]
  bash -c 'set -euo pipefail
    REPO="$1"; S="$2"; A="$3"; R="$4"; H="$5"; DEST="$6"
    source "$REPO_LIB"
    if [[ "${7:-smoke}" == smoke ]]; then
      record_subs "$S/subs.json" "$S=<scratch>" "$A=<asap7-checkout>" "$R=<repo>" "$H=<home>"
    else
      record_subs "$S/subs.json" "$S=<scratch>" "$R=<repo>" "$H=<home>" "$A=<asap7-checkout>"
    fi
    printf "%s\n" "{\"liberty\":\"$A/LIB/x.lib\",\"scratch\":\"$S/w\",\"repo\":\"$R/flow\",\"home\":\"$H/.cache\"}" \
      | python3 -I "$REPO/flow/record_lib.py" write "$DEST" "$S/subs.json"
  ' _ "$SELF_REPO" "$1" "$2" "$3" "$4" "$5" "${6:-smoke}"
}

make_record "$FS" "$FA" "$FR" "$FH" "$FOUT/synth.json"
eq "checkout under home: tagged <asap7-checkout>" "1" "$(grep -c '<asap7-checkout>' "$FOUT/synth.json")"
if grep -q '<home>/asap7' "$FOUT/synth.json"; then
  no "checkout path mis-tagged under <home>"
else
  ok "checkout path not mis-tagged <home>/asap7"
fi
eq "no host root anywhere in the redacted record" "0" "$(grep -cE '/home/|/tmp/|/Users/|/root/' "$FOUT/synth.json")"

# Contrast only: with $ASAP7 after $HOME the same input mis-tags into
# <home>/asap7, which the four-root grep cannot catch -- why the order is
# load-bearing.
make_record "$FS" "$FA" "$FR" "$FH" "$FOUT/synth.json" wrong
eq "contrast: wrong order yields <home>/asap7 (grep-invisible)" "1" "$(grep -c '<home>/asap7' "$FOUT/synth.json")"

# ff_simple_check.sh's record-assembly pipeline: its heredoc prints to stdout
# through flow/record_lib.py write, so a synthetic check.json carrying a path
# under every root comes out redacted, with the analysis fields intact.
ff_pipeline() {  # scratch asap7 repo home src dest
  bash -c 'set -euo pipefail
    REPO="$1"; S="$2"; A="$3"; R="$4"; H="$5"; SRC="$6"; DEST="$7"
    source "$REPO_LIB"
    record_subs "$S/subs.json" "$S=<scratch>" "$A=<asap7-checkout>" "$R=<repo>" "$H=<home>"
    python3 -I - "$SRC" "0123456789abcdef0123456789abcdef01234567" "remote head abc; commits after pin: none" <<PY | python3 -I "$REPO/flow/record_lib.py" write "$DEST" "$S/subs.json"
import json, sys
src, pin, upstream = sys.argv[1:]
rec = json.load(open(src))
rec["pinned_asap7sc7p5t_28"] = pin
rec["later_upstream_check"] = upstream
print(json.dumps(rec))
PY
  ' _ "$SELF_REPO" "$1" "$2" "$3" "$4" "$5" "$6"
}

cat >"$FS/check.json" <<JSON
{"found": ["$FA/LIB/NLDM/x.lib", "$FS/work/y.lib", "$FR/flow/z", "$FH/.klt"], "min_width_nm": 54}
JSON
ff_pipeline "$FS" "$FA" "$FR" "$FH" "$FS/check.json" "$FOUT/ff-simple-check.json" \
  || no "ff record-assembly pipeline exited non-zero"
eq "ff pipeline output is grep-clean" "0" "$(grep -cE '/home/|/tmp/|/Users/|/root/' "$FOUT/ff-simple-check.json")"
eq "ff pipeline keeps the pinned-sha field" \
  '"pinned_asap7sc7p5t_28": "0123456789abcdef0123456789abcdef01234567"' \
  "$(grep -F 'pinned_asap7sc7p5t_28' "$FOUT/ff-simple-check.json" | sed 's/^ *//')"
eq "ff pipeline keeps the later-upstream field" \
  '"later_upstream_check": "remote head abc; commits after pin: none",' \
  "$(grep -F 'later_upstream_check' "$FOUT/ff-simple-check.json" | sed 's/^ *//')"
run_guard "$FOUT"
eq "and the written record passes record_leak_guard" "0" "$GUARD_RC"

echo
echo "# 7. every record_subs call site lists the same four roots, in the smoke flow's order"

subs_args() {  # flow-script -- the roots of its record_subs call, verbatim
  grep -h 'record_subs "\$SCRATCH/subs.json"' "$SELF_REPO/$1" \
    | sed 's/^record_subs "\$SCRATCH\/subs.json" //'
}

WANT='"$SCRATCH=<scratch>" "$ASAP7=<asap7-checkout>" "$REPO=<repo>" "$HOME=<home>"'
eq "flow/smoke/run.sh (the reference order)" "$WANT" "$(subs_args flow/smoke/run.sh)"
eq "flow/core/synth.sh matches the reference" "$WANT" "$(subs_args flow/core/synth.sh)"
eq "flow/core/ff_simple_check.sh matches the reference" "$WANT" "$(subs_args flow/core/ff_simple_check.sh)"

for f in flow/core/synth.sh flow/core/ff_simple_check.sh; do
  if grep -q 'record_leak_guard "\$OUT"' "$SELF_REPO/$f"; then
    ok "$f calls record_leak_guard on the record dir"
  else
    no "$f does not call record_leak_guard"
  fi
done

echo
echo "flow/lib_test.sh: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
