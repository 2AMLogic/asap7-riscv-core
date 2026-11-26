#!/usr/bin/env bash
# Self-test for the shared helpers in flow/lib.sh: the label-anchored,
# fail-closed pin reads, the synthesized-netlist locator, the shared
# provenance-row head of the flow tool-versions.txt records, the
# record-selection rule behind synth.sh --check, extract_rvt_liberty's
# counted fail-closed guard, and the physical-overlay staging both routing
# drivers share -- plus the record redaction plumbing: the
# leak guard and the substitution order behind flow/*/records/.
#
# Needs no PDK checkout, no klt and no network: every case is either a read of
# this repo's own spec/ or flow/ scripts, a read of a crafted spec/ or
# records/ tree in a scratch directory, or a run of a helper over crafted
# scratch files with its tool asks stubbed.
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

# One scratch root, created here in the parent shell: every scratch directory
# the suite makes is mktemp -d'd inside it, and the trap removes just the
# root. A command substitution runs in a subshell, so a path registered there
# never reaches this shell's array -- the per-path registration array the
# helpers used to feed was dead code (#149): every subshell-created dir
# survived the run. A parent-owned root makes the subshell depth of a call
# site irrelevant. #199 finished the sweep: the record, four-root, netlist
# and stub fixtures that still allocated outside the root moved under it,
# and the dead FAKES appends went away.
SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/asap7-libtest.XXXXXX")" || exit 1
cleanup() { rm -rf "$SCRATCH"; }
trap cleanup EXIT

# A scratch repo holding only the two spec files the helpers read.
fake_repo() {  # core-md-body
  local d; d="$(mktemp -d "$SCRATCH/repo.XXXXXX")"
  mkdir -p "$d/spec"
  printf '%s\n' "$1" >"$d/spec/core.md"
  cp "$SELF_REPO/spec/pdk-bringup.md" "$d/spec/pdk-bringup.md"
  printf '%s' "$d"
}

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
# A negative case must assert *why* the read refused, not just rc != 0 with
# empty stdout: bash's own "command not found" also produces that, so a
# renamed or missing helper used to read as a pass (#149). Capture the
# combined output and grep for the helper's die text -- the idiom
# expect_counted_die already uses for extract_rvt_liberty below.
expect_refusal() {  # label expr die-text [repo]
  local label="$1" expr="$2" want="$3" repo="${4:-$SELF_REPO}" got rc
  got="$(read_pin "$repo" "$expr" 2>&1)"; rc=$?
  if [[ $rc -ne 0 ]] && grep -qF -- "$want" <<<"$got"; then
    ok "$label"
  else
    no "$label: rc=$rc, output '$got'"
  fi
}
expect_refusal "no such label dies with the no-match refusal" \
  "spec_pin 'no such label in the spec' 'klayout-tools==[0-9][0-9.]*'" \
  'spec/core.md: no match for /klayout-tools==[0-9][0-9.]*/ on or within 0 line(s) below "no such label in the spec"'
expect_refusal "a match outside the label window dies with the same refusal" \
  "spec_pin 'equal to the pinned hash' 'sha256:[0-9a-f]\{64\}' 0" \
  'spec/core.md: no match for /sha256:[0-9a-f]\{64\}/ on or within 0 line(s) below "equal to the pinned hash"'
expect_refusal "an unmatched row label dies with the spec_sha refusal" \
  "spec_sha 'No Such Row'" \
  'spec/pdk-bringup.md: no 40-hex sha on a row starting "| No Such Row"'

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
  d="$(mktemp -d "$SCRATCH/rec.XXXXXX")"
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

FH="$(mktemp -d "$SCRATCH/home.XXXXXX")"
FS="$(mktemp -d "$SCRATCH/scratch.XXXXXX")"
FR="$(mktemp -d "$SCRATCH/repo.XXXXXX")"
FOUT="$(mktemp -d "$SCRATCH/out.XXXXXX")"
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

echo "# 8. synth_netlist: the newest synthesized netlist, or nothing"
NW="$(mktemp -d "$SCRATCH/net.XXXXXX")"
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
echo "# 9. provenance_rows: one klt row, keyed klt:, carrying the klt version ask"
STUBS="$(mktemp -d "$SCRATCH/stubs.XXXXXX")"
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

echo "# 10. newest_record_with selects the newest record directory holding the file"
# The issue #105 shape: flow/core/records/ is written by two flows and only
# synth.sh's directories hold a netlist.v, so selection must follow the
# content, not the directory sort order.
R="$(mktemp -d "$SCRATCH/rec.XXXXXX")"
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

# The refusal contract here is a bare `return 1` with no message, so the
# assertion is exit 1 with nothing on stdout *or* stderr: read_pin's
# `|| exit 1` gives a missing helper the same exit 1, and only bash's
# "command not found" noise on stderr distinguishes it (#149).
expect_silent_refusal() {  # label expr
  local label="$1" expr="$2" got rc
  got="$(read_pin "$SELF_REPO" "$expr" 2>&1)"; rc=$?
  if [[ $rc -eq 1 && -z "$got" ]]; then
    ok "$label"
  else
    no "$label: rc=$rc, output '$got'"
  fi
}
expect_silent_refusal "no directory holds the file: exits 1 with no value" \
  "newest_record_with '$R/no-file-anywhere' netlist.v"
expect_silent_refusal "records root absent entirely: exits 1 with no value" \
  "newest_record_with '$R/no-such-root' netlist.v"

S="$(mktemp -d "$SCRATCH/rec.XXXXXX")"
mkdir -p "$S/records/2026-11-03"
printf 'only\n' >"$S/records/2026-11-03/netlist.v"
eq "a single directory holding the file is selected" "$S/records/2026-11-03/" \
  "$(read_pin "$SELF_REPO" "newest_record_with '$S/records' netlist.v")"

E="$(mktemp -d "$SCRATCH/rec.XXXXXX")"
mkdir -p "$E/records/2026-11-03"
expect_silent_refusal \
  "an existing but empty record directory is skipped, not selected: exits 1" \
  "newest_record_with '$E/records' netlist.v"

D="$(mktemp -d "$SCRATCH/rec.XXXXXX")"
mkdir -p "$D/records/2026-11-03/netlist.v"
expect_silent_refusal \
  "a netlist.v that is a directory rather than a file does not qualify: exits 1" \
  "newest_record_with '$D/records' netlist.v"

echo
echo "# 11. the record-writing path still refuses an existing record set"
EX="$(fake_repo '# pins
not read here')"
mkdir -p "$EX/flow/core/records/2026-11-03"
printf '{}\n' >"$EX/flow/core/records/2026-11-03/synth.json"
expect_refusal "new_record_dir refuses an existing record set" \
  'RECORD_DATE=2026-11-03; new_record_dir core' \
  'records already exist in flow/core/records/2026-11-03' \
  "$EX"

FREE="$(fake_repo '# pins
not read here')"
eq "new_record_dir on a free date still sets OUT" \
  "$FREE/flow/core/records/2026-12-25" \
  "$(read_pin "$FREE" 'RECORD_DATE=2026-12-25; new_record_dir core; printf "%s" "$OUT"')"

echo
echo "# 12. extract_rvt_liberty fails closed on a wrong archive count"
# The counted guard is the point of the helper: a requested corner without
# exactly its five group archives must die before the py7zr env is built --
# the empty-glob fall-through that used to hand merge_lib.py a literal
# `*_RVT_<c>_nldm_*.lib` filename. The expectation is 5 per corner asked for,
# so a single-corner caller is not wrong by construction (contrast the
# literal 15 the all-corners copy asserted). These cases die before uvx runs,
# so they need no py7zr, no network and no PDK checkout.
fake_libdir() {  # corner n-groups -> a fake asap7 checkout whose NLDM holds
  # the first <n-groups> of the five group archives for <corner>
  local d; d="$(mktemp -d "$SCRATCH/lib.XXXXXX")"
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
echo "# 13. par_request: one place-and-route request serves both drivers"
# The core driver inherits its grid from the verified smoke run, and one
# template is what keeps that true when a track or a strap changes (#289): the
# request schema is spelled in flow/lib.sh alone, and each driver renders its
# request through the shared writer with its own top cell and clock port.
TEMPLATE_FILES="$(grep -l --exclude='*_test.sh' 'klt\.place_and_route\.request/1' \
  "$SELF_REPO"/flow/*.sh "$SELF_REPO"/flow/*/*.sh | sed "s|^$SELF_REPO/||" | sort | tr '\n' ' ' | sed 's/ $//')"
eq "the request schema is spelled in flow/lib.sh alone" "flow/lib.sh" "$TEMPLATE_FILES"
eq "the core driver renders the wrapper's request through the shared writer" \
  'par_request "$TOP" clk_i "$CELL_LIB" >"$W/par.req.json"' \
  "$(grep -F 'par_request "$TOP" clk_i "$CELL_LIB" >"$W/par.req.json"' "$SELF_REPO/flow/core/par.sh" | sed 's/^ *//')"
eq "the smoke driver renders the counter's request through the shared writer" \
  'par_request "$DUT" clk "$CELL_LIB" >"$W/par.req.json"' \
  "$(grep -F 'par_request "$DUT" clk "$CELL_LIB" >"$W/par.req.json"' "$SELF_REPO/flow/smoke/run.sh" | sed 's/^ *//')"

echo
echo "# 14. stage_physical_overlay: one physical staging serves both drivers"
# flow/smoke/run.sh (the counter) and flow/core/par.sh (the core wrapper) route
# on the same physical overlay: the cell LEF, cell GDS and tech LEF copied
# unmodified into the scratch PDK root, with the pinned PDK's DEF->GDS layer
# map registered there as the KLayout asset. Each driver staged it with its own
# copy of the same commands, so a source filename or a destination had two edit
# sites (#301); one stager gives them one. The Liberty half stays each driver's
# own build_liberty_overlay call -- SS for the core, SS and TT for the smoke
# flow -- and the stager runs after it, adding to the manifest it wrote, which
# must leave the Liberty entries exactly as they were.
PA="$(mktemp -d "$SCRATCH/asap7.XXXXXX")"
mkdir -p "$PA/asap7sc7p5t_28/LEF" "$PA/asap7sc7p5t_28/GDS" "$PA/asap7sc7p5t_28/techlef_misc" \
         "$PA/asap7_pdk_r1p7/cdslib/asap7_TechLib_10"
printf 'fixture cell LEF\n' >"$PA/asap7sc7p5t_28/LEF/asap7sc7p5t_28_R_1x_220121a.lef"
printf 'fixture cell GDS\377\001' >"$PA/asap7sc7p5t_28/GDS/asap7sc7p5t_28_R_220121a.gds"
printf 'fixture tech LEF\n' >"$PA/asap7sc7p5t_28/techlef_misc/asap7_tech_1x_201209.lef"
printf 'fixture layer map\n' >"$PA/asap7_pdk_r1p7/cdslib/asap7_TechLib_10/asap7_fromAPR.layermap"
# The agreed mapping: <source under the checkout>=<destination under the overlay root>.
PHYSICAL_INPUTS=(
  "asap7sc7p5t_28/LEF/asap7sc7p5t_28_R_1x_220121a.lef=libs/asap7sc7p5t_28_R/lef/asap7sc7p5t_28_R.lef"
  "asap7sc7p5t_28/GDS/asap7sc7p5t_28_R_220121a.gds=libs/asap7sc7p5t_28_R/gds/asap7sc7p5t_28_R.gds"
  "asap7sc7p5t_28/techlef_misc/asap7_tech_1x_201209.lef=libs/asap7sc7p5t_28_R/techlef/asap7sc7p5t_28_R__nom.tlef"
  "asap7_pdk_r1p7/cdslib/asap7_TechLib_10/asap7_fromAPR.layermap=klayout/tech/asap7.map"
)
# build_liberty_overlay's manifest before the stager adds to it: the smoke
# flow's two corners, then the core's one. The overlay manifests are the same
# text with the layer map registered as the KLayout asset.
LIBERTY_SSTT='{"schema_version":1,"variant":"asap7","assets":{"libs_ref":"libs"},
 "liberty":{"asap7sc7p5t_28_R":{"SS":"lib/asap7sc7p5t_28_R_SS.lib","TT":"lib/asap7sc7p5t_28_R_TT.lib"}}}
'
LIBERTY_SS='{"schema_version":1,"variant":"asap7","assets":{"libs_ref":"libs"},
 "liberty":{"asap7sc7p5t_28_R":{"SS":"lib/asap7sc7p5t_28_R_SS.lib"}}}
'
OVERLAY_SSTT='{
 "schema_version": 1,
 "variant": "asap7",
 "assets": {
  "libs_ref": "libs",
  "klayout": "klayout"
 },
 "liberty": {
  "asap7sc7p5t_28_R": {
   "SS": "lib/asap7sc7p5t_28_R_SS.lib",
   "TT": "lib/asap7sc7p5t_28_R_TT.lib"
  }
 }
}
'
OVERLAY_SS='{
 "schema_version": 1,
 "variant": "asap7",
 "assets": {
  "libs_ref": "libs",
  "klayout": "klayout"
 },
 "liberty": {
  "asap7sc7p5t_28_R": {
   "SS": "lib/asap7sc7p5t_28_R_SS.lib"
  }
 }
}
'

# stage_overlay <checkout> <root> <starting-manifest>: the shared stager over
# a root holding the manifest build_liberty_overlay wrote, called the way both
# flow drivers call it -- a plain command in a set -euo pipefail shell, which
# is what stops it when a copy fails. The status is the stager's.
stage_overlay() {  # checkout root manifest
  mkdir -p "$2"
  printf '%s' "$3" >"$2/klt-pdk.json"
  bash -c 'set -euo pipefail; REPO="$1"; source "$REPO_LIB"; stage_physical_overlay "$2" "$3" asap7sc7p5t_28_R' \
    _ "$SELF_REPO" "$1" "$2" >/dev/null
}

# check_overlay <label> <root> <overlay-manifest>: every staged input is a
# regular file holding its source's bytes, the root holds the five files both
# drivers always staged and not one symlink, and the manifest is the starting
# one plus the KLayout asset, byte for byte.
check_overlay() {  # label root want-manifest
  local label="$1" root="$2" pair dst
  for pair in "${PHYSICAL_INPUTS[@]}"; do
    dst="${pair#*=}"
    if [[ -f "$root/$dst" && ! -L "$root/$dst" ]] && cmp -s "$PA/${pair%%=*}" "$root/$dst"; then
      ok "$label: $dst is a regular file with the source bytes"
    else
      no "$label: $dst is a regular file with the source bytes"
    fi
  done
  eq "$label: the root holds exactly the five files both drivers always staged" \
    "$(printf '%s\n' klt-pdk.json "${PHYSICAL_INPUTS[@]#*=}" | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//')" \
    "$(cd "$root" && find . -type f | sed 's|^\./||' | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//')"
  if [[ -z "$(find "$root" -type l | head -1)" ]]; then
    ok "$label: the overlay holds no symlink (OpenROAD rejects a symlinked LEF, ORD-0001)"
  else
    no "$label: the overlay holds no symlink (OpenROAD rejects a symlinked LEF, ORD-0001)"
  fi
  printf '%s' "$3" >"$root.want"
  if cmp -s "$root/klt-pdk.json" "$root.want"; then
    ok "$label: the manifest gains the KLayout asset and keeps its Liberty entries, byte for byte"
  else
    no "$label: the manifest gains the KLayout asset and keeps its Liberty entries, byte for byte"
  fi
}

OSTT="$(mktemp -d "$SCRATCH/overlay.XXXXXX")"
stage_overlay "$PA" "$OSTT" "$LIBERTY_SSTT"
eq "the smoke flow's overlay (SS and TT Liberty) stages cleanly" 0 "$?"
check_overlay "SS and TT" "$OSTT" "$OVERLAY_SSTT"
OSS="$(mktemp -d "$SCRATCH/overlay.XXXXXX")"
stage_overlay "$PA" "$OSS" "$LIBERTY_SS"
eq "the core's overlay (SS Liberty) stages cleanly" 0 "$?"
check_overlay "SS" "$OSS" "$OVERLAY_SS"

# Both drivers' tool-versions.txt hash the tech LEF and the layer map through
# TECH_SRC and LAYERMAP_SRC, the names their staging blocks set inline.
eq "the stager names the four sources for the calling driver's provenance rows" \
  "$(printf '%s\n' "${PHYSICAL_INPUTS[@]%%=*}" | sed "s|^|$PA/|")" \
  "$(bash -c 'set -euo pipefail; REPO="$1"; source "$REPO_LIB"
      stage_physical_overlay "$2" "$3" asap7sc7p5t_28_R
      printf "%s\n" "$CELL_LEF_SRC" "$CELL_GDS_SRC" "$TECH_SRC" "$LAYERMAP_SRC"' _ "$SELF_REPO" "$PA" "$OSS")"

# Fails closed: a source the checkout does not have stops the driver before
# the stager touches the manifest, so a half-staged overlay is never
# registered as a PDK.
PM="$(mktemp -d "$SCRATCH/asap7.XXXXXX")"
mkdir -p "$PM/asap7sc7p5t_28/LEF" "$PM/asap7sc7p5t_28/techlef_misc" "$PM/asap7_pdk_r1p7/cdslib/asap7_TechLib_10"
cp "$PA/asap7sc7p5t_28/LEF/asap7sc7p5t_28_R_1x_220121a.lef" "$PM/asap7sc7p5t_28/LEF/"
cp "$PA/asap7sc7p5t_28/techlef_misc/asap7_tech_1x_201209.lef" "$PM/asap7sc7p5t_28/techlef_misc/"
cp "$PA/asap7_pdk_r1p7/cdslib/asap7_TechLib_10/asap7_fromAPR.layermap" "$PM/asap7_pdk_r1p7/cdslib/asap7_TechLib_10/"
OM="$(mktemp -d "$SCRATCH/overlay.XXXXXX")"
printf '%s' "$LIBERTY_SS" >"$OM.want"
rc=0
stage_overlay "$PM" "$OM" "$LIBERTY_SS" 2>"$SCRATCH/missing.err" || rc=$?
if [[ $rc -ne 0 ]] && grep -q 'asap7sc7p5t_28_R_220121a.gds' "$SCRATCH/missing.err"; then
  ok "a checkout without the cell GDS refuses to stage, naming the missing source"
else
  no "a checkout without the cell GDS refuses to stage, naming the missing source: rc=$rc"
fi
if cmp -s "$OM/klt-pdk.json" "$OM.want"; then
  ok "a refused staging leaves the manifest as build_liberty_overlay wrote it"
else
  no "a refused staging leaves the manifest as build_liberty_overlay wrote it"
fi

# One edit site: the destination layout and the manifest registration are
# spelled in flow/lib.sh alone, and each driver keeps its own Liberty corners
# and stages the physical half through the shared stager, after the Liberty
# builder whose manifest the stager adds to.
eq "the physical staging is spelled in flow/lib.sh alone" "flow/lib.sh" \
  "$(grep -l --exclude='*_test.sh' -e '__nom\.tlef' -e 'klayout/tech' -e 'assets.\["klayout"\]' \
      "$SELF_REPO"/flow/*.sh "$SELF_REPO"/flow/*/*.sh | sed "s|^$SELF_REPO/||" | sort | tr '\n' ' ' | sed 's/ $//')"
for driver in "flow/core/par.sh|SS" "flow/smoke/run.sh|SS TT"; do
  drv="${driver%%|*}"; corners="${driver#*|}"
  eq "$drv still builds its Liberty overlay for $corners" \
    "build_liberty_overlay \"\$ASAP7\" \"\$ROOT\" \"\$CELL_LIB\" $corners" \
    "$(grep -F "build_liberty_overlay \"\$ASAP7\" \"\$ROOT\" \"\$CELL_LIB\" $corners" "$SELF_REPO/$drv" | sed 's/^ *//')"
  eq "$drv stages the physical overlay through the shared stager" \
    'stage_physical_overlay "$ASAP7" "$ROOT" "$CELL_LIB"' \
    "$(grep -F 'stage_physical_overlay "$ASAP7" "$ROOT" "$CELL_LIB"' "$SELF_REPO/$drv" | sed 's/^ *//')"
  first="$(grep -n -e 'build_liberty_overlay "\$ASAP7"' -e 'stage_physical_overlay "\$ASAP7"' "$SELF_REPO/$drv" | head -1)"
  if [[ "$first" == *'build_liberty_overlay '* ]]; then
    ok "$drv builds the Liberty overlay before staging the physical half"
  else
    no "$drv builds the Liberty overlay before staging the physical half"
  fi
done

echo
echo "flow/lib_test.sh: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
