#!/usr/bin/env bash
# Self-test for flow/core/drc.sh, the core DRC driver (T1 item 3).
#
# Needs no PDK, no klt, no network and no GDS: it checks the driver's
# refusal contract (no committed GDS, no committed par record, a moved GDS
# the par pin does not name, a deck file that is not the pin, records
# already existing for the date), the klt invocation's invariants (engine
# klayout, the pinned deck by file, the decision 0012 category count, JSON
# output), and the staging + publication invariants in a scratch fixture
# repository with a stubbed klt (record published with the input pins
# written, redaction of host paths before anything is published, the
# append-only refusal on a second run, and nothing of a failed publication
# left behind when a record copy fails partway or another writer holds a
# record pathname).
#
# ASAP7 is a predictive PDK; nothing here is fabricated or measured, and
# this script makes no claim about any design.
#
# usage: flow/core/drc_test.sh
# Exit status: 0 every case passed; 1 a case failed.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
NPASS=0
NBAD=0

ok() { NPASS=$((NPASS + 1)); echo "ok   - $1"; }
no() { NBAD=$((NBAD + 1)); echo "not ok - $1"; }

eq() {  # label want got
  if [[ "$2" == "$3" ]]; then ok "$1"; else no "$1: want '$2', got '$3'"; fi
}

W="$(mktemp -d "${TMPDIR:-/tmp}/asap7-drctest.XXXXXX")"
cleanup() { rm -rf "$W"; }
trap cleanup EXIT

DRC="$REPO/flow/core/drc.sh"

# ---- the klt invocation's invariants (read from the driver) -----------------
if grep -q -- '--engine klayout' "$DRC"; then
  ok "the drc run names engine klayout"
else
  no "the drc run names engine klayout"
fi
if grep -q -- '--expect-rule-categories "$EXPECT_CATEGORIES"' "$DRC"; then
  ok "the category count is a named constant, not a magic number inline"
else
  no "the category count is a named constant, not a magic number inline"
fi
eq "the expected category count is decision 0012's 267" \
  "EXPECT_CATEGORIES=267" "$(grep -o 'EXPECT_CATEGORIES=267' "$DRC" | head -1)"
if grep -q -- '--deck-file' "$DRC" && grep -q -- '--format json' "$DRC"; then
  ok "the deck is passed by file and the report asked for as JSON"
else
  no "the deck is passed by file and the report asked for as JSON"
fi

# ---- fixture repository ------------------------------------------------------
BIN="$W/bin"; mkdir -p "$BIN"
cat >"$BIN/uvx" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
case "$*" in
  *--version*) echo "uvx 0.0-stub" ;;
  *py7zr.__version__*) echo "1.0-stub" ;;
  *) cat >/dev/null ;;
esac
STUB
cat >"$BIN/yosys" <<'STUB'
#!/usr/bin/env bash
echo "Yosys 0.67-stub"
STUB
cat >"$BIN/stub-klt" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "version" ]]; then
  echo "klt 0.9.0"
  exit 0
fi
if [[ "${1:-}" == "drc" ]]; then
  if [[ -n "${STUB_SQUAT_FILE:-}" ]]; then
    mkdir -p -- "$(dirname -- "$STUB_SQUAT_FILE")"
    printf '%s' "${STUB_SQUAT_CONTENT:-}" >"$STUB_SQUAT_FILE"
  fi
  printf '%s\n' "${STUB_REPORT_JSON:-}"
  exit "${STUB_KLT_RC:-0}"
fi
exit 2
STUB
chmod +x "$BIN/uvx" "$BIN/yosys" "$BIN/stub-klt"

FA="$W/asap7"
mkdir -p "$FA/asap7sc7p5t_28" "$FA/asap7_pdk_r1p7"
for sub in "$FA/asap7sc7p5t_28" "$FA/asap7_pdk_r1p7" "$FA"; do
  git init -q "$sub"
  git -C "$sub" -c user.email=t@t -c user.name=t commit -q --allow-empty -m pin
done
SHA_UP="$(git -C "$FA" rev-parse HEAD)"
SHA_CELLS="$(git -C "$FA/asap7sc7p5t_28" rev-parse HEAD)"
SHA_PDK="$(git -C "$FA/asap7_pdk_r1p7" rev-parse HEAD)"

FX="$W/repo"
mkdir -p "$FX/flow/core/records" "$FX/spec" "$FX/layout"
cp "$REPO/flow/lib.sh" "$REPO/flow/record_lib.py" "$FX/flow/"
mkdir -p "$FX/flow/core"
cp "$DRC" "$REPO/flow/core/record_publish.sh" "$FX/flow/core/"
chmod +x "$FX/flow/core/drc.sh"
cat >"$FX/spec/pdk-bringup.md" <<EOF
| Upstream repo | fake $SHA_UP |
| Cell library | fake $SHA_CELLS |
| PDK (DRM | fake $SHA_PDK |
EOF

# The fixture deck file and the spec that pins it by hash.
mkdir -p "$FX/deckdir"
printf '# fixture asap7 deck\n' >"$FX/deckdir/asap7.drc"
DECK_SHA="$(sha256sum "$FX/deckdir/asap7.drc" | cut -d' ' -f1)"
cat >"$FX/spec/core.md" <<EOF
- \`klt\`: release \`klayout-tools==0.9.0\` is the pinned release for DRC, LVS and the smoke flow.
- the report's \`provenance.deck.content_hash\` equal to the pinned hash:
  \`sha256:$DECK_SHA\`
EOF

fx_commit() {  # commit the fixture working tree
  git -C "$FX" add -A
  git -C "$FX" -c user.email=t@t -c user.name=t commit -q -m "$1"
}
git init -q "$FX"
fx_commit "empty fixture"

run_drc() {  # run the fixture driver with the stub klt and fixture deck
  RECORD_DATE="$FXDATE" KLT_CMD="$BIN/stub-klt" KLT_DECK_FILE="$FX/deckdir/asap7.drc" \
    PATH="$BIN:$PATH" bash "$FX/flow/core/drc.sh"
}

# ---- refusals (nothing written) ----------------------------------------------
FXDATE=2026-11-24
out="$W/nogds.err"; rc=0
( run_drc ) >"$out" 2>&1 || rc=$?
eq "no committed GDS refuses (exit 2)" 2 "$rc"
if grep -q "no committed HEAD:layout/cve2_top.gds" "$out"; then
  ok "no-GDS refusal names the missing blob"
else
  no "no-GDS refusal names the missing blob"
fi

printf 'fixture-gds-v1' >"$FX/layout/cve2_top.gds"
fx_commit "GDS but no par record"
out="$W/nopar.err"; rc=0
( run_drc ) >"$out" 2>&1 || rc=$?
eq "no committed par record refuses (exit 2)" 2 "$rc"
if grep -q "nothing pins the GDS" "$out"; then
  ok "no-par refusal names the missing pin"
else
  no "no-par refusal names the missing pin"
fi

GDS_SHA="$(sha256sum "$FX/layout/cve2_top.gds" | cut -d' ' -f1)"
mkdir -p "$FX/flow/core/records/2026-11-22"
cat >"$FX/flow/core/records/2026-11-22/par.json" <<EOF
{"core_flow":{"gds":{"path":"layout/cve2_top.gds","sha256":"not-the-blob-sha"}}}
EOF
fx_commit "par record pinning a different GDS"
out="$W/pinmove.err"; rc=0
( run_drc ) >"$out" 2>&1 || rc=$?
eq "a GDS the par pin does not name refuses (exit 1)" 1 "$rc"
if grep -q "input pin mismatch" "$out"; then
  ok "moved-input refusal names the pin mismatch"
else
  no "moved-input refusal names the pin mismatch"
fi

cat >"$FX/flow/core/records/2026-11-22/par.json" <<EOF
{"core_flow":{"gds":{"path":"layout/cve2_top.gds","sha256":"$GDS_SHA"}}}
EOF
fx_commit "par record pinning the fixture GDS"

out="$W/wrongdeck.err"; rc=0
( RECORD_DATE="$FXDATE" KLT_CMD="$BIN/stub-klt" KLT_DECK_FILE="$FX/spec/core.md" \
    PATH="$BIN:$PATH" bash "$FX/flow/core/drc.sh" ) >"$out" 2>&1 || rc=$?
eq "a deck file that is not the pin refuses (exit 1)" 1 "$rc"
if grep -q "not the pin" "$out"; then
  ok "wrong-deck refusal names the pin"
else
  no "wrong-deck refusal names the pin"
fi

mkdir -p "$FX/flow/core/records/$FXDATE"
printf '{"squat.json": true}\n' >"$FX/flow/core/records/$FXDATE/squat.json"
fx_commit "records already exist for the date"
out="$W/exists.err"; rc=0
( run_drc ) >"$out" 2>&1 || rc=$?
eq "records already existing for the date refuse (exit 2)" 2 "$rc"
rm "$FX/flow/core/records/$FXDATE/squat.json"
fx_commit "date directory free again"

# ---- happy path with the stub klt ---------------------------------------------
VALID_REPORT="$(python3 - "$DECK_SHA" <<'PY'
import json, sys
print(json.dumps({
    "status": "violations",
    "violation_count": 1,
    "violations": [{"rule": "V4.M4.EN.1", "description": "stub marker",
                    "bbox": {"left": 1, "bottom": 2, "right": 3, "top": 4}}],
    "coverage": {"rule_categories": ["R%d" % i for i in range(267)],
                 "layers_in_stream_without_rules": [], "rules_skipped": [],
                 "deck_scope": []},
    "provenance": {"deck": {"content_hash": "sha256:" + sys.argv[1]},
                   "klt_version": "0.9.0"},
}))
PY
)"
out="$W/ok.out"; rc=0
( STUB_REPORT_JSON="$VALID_REPORT" run_drc ) >"$out" 2>&1 || rc=$?
eq "a usable report records cleanly (exit 0)" 0 "$rc"

REC="$FX/flow/core/records/$FXDATE/drc.json"
if [[ -s "$REC" ]] && [[ -s "$FX/flow/core/records/$FXDATE/tool-versions.txt" ]]; then
  ok "the dated record and tool-versions are published"
else
  no "the dated record and tool-versions are published"
fi
j() {  # jq-style extraction via python: j <py-expr over d>
  python3 -I -c "import json,sys; d=json.load(open(sys.argv[1])); print($1)" "$REC"
}
eq "the record pins the checked GDS blob by sha256" "$GDS_SHA" \
  "$(j 'd["core_flow"]["input_gds"]["sha256"]')"
eq "the record names the par record that pins the GDS" \
  "flow/core/records/2026-11-22/par.json" "$(j 'd["core_flow"]["input_pin"]["record"]')"
eq "the report's status is carried through unfiltered" "violations" "$(j 'd["status"]')"
eq "the violation count is carried through unfiltered" "1" "$(j 'd["violation_count"]')"
if grep -q "klt:" "$FX/flow/core/records/$FXDATE/tool-versions.txt" \
  && grep -q "pinned_drc_deck:" "$FX/flow/core/records/$FXDATE/tool-versions.txt"; then
  ok "tool-versions carries the shared klt row and the deck pin row"
else
  no "tool-versions carries the shared klt row and the deck pin row"
fi

# ---- append-only: a second run for the same date refuses ----------------------
out="$W/again.err"; rc=0
( run_drc ) >"$out" 2>&1 || rc=$?
eq "a second run for the same date refuses (exit 2)" 2 "$rc"

# ---- a leaking report publishes nothing ----------------------------------------
LEAK_REPORT="${VALID_REPORT/\"status\": \"violations\"/\"status\": \"violations\", \"file\": \"/home/leak/x.gds\"}"
rm -rf "$FX/flow/core/records/$FXDATE"
fx_commit "date directory free for the leak probe" >/dev/null 2>&1 || true
out="$W/leak.err"; rc=0
( STUB_REPORT_JSON="$LEAK_REPORT" run_drc ) >"$out" 2>&1 || rc=$?
eq "a report leaking a host path refuses (exit 1)" 1 "$rc"
if [[ ! -e "$FX/flow/core/records/$FXDATE/drc.json" ]]; then
  ok "the leaking run published no record"
else
  no "the leaking run published no record"
fi

# ---- a record copy that fails partway, or a record pathname another writer
# holds (issue #286): each record is copied to completion under a private
# name in the dated directory and linked to its final pathname only then,
# without replacement (flow/core/record_publish.sh). A partial copy never
# occupies a record pathname, so it cannot read as an existing record and
# refuse the retry, and a rollback removes what this run installed and
# nothing else. The stubbed `cat` writes four bytes of one staged record and
# exits 1, recording the pathname it was writing.
REAL_CAT="$(command -v cat)"
cat >"$BIN/cat" <<STUB
#!/usr/bin/env bash
if [[ \$# -gt 0 && \${*: -1} == *"/\$STUB_CAT_FAIL" ]]; then
  exec 3>&1
  readlink /proc/self/fd/3 >"\$STUB_CAT_SEEN"
  head -c 4 -- "\${*: -1}"
  exit 1
fi
exec "$REAL_CAT" "\$@"
STUB
chmod +x "$BIN/cat"
: >"$W/refmode"
REC="$FX/flow/core/records/$FXDATE"
dated() {  # every entry of the dated directory, hidden names included
  ls -A "$REC" 2>/dev/null | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//'
}
record_run() {  # <log>: the fixture driver with the valid report; the caller sets the STUB_* knobs
  rc=0
  ( STUB_REPORT_JSON="$VALID_REPORT" run_drc ) >"$1" 2>&1 || rc=$?
}
partial_copy() {  # <label> <record>: run with that record's copy failing partway
  local seen="$W/catseen.$2"
  STUB_CAT_FAIL="$2" STUB_CAT_SEEN="$seen" record_run "$W/partial_$2.out"
  eq "$1: record mode exits 1" 1 "$rc"
  eq "$1: the partial copy was written inside the dated directory" \
    "$REC" "$(dirname "$(cat "$seen")")"
  [[ ! -e "$(cat "$seen")" ]] && ok "$1: the partial copy is removed" || no "$1: the partial copy is removed"
  [[ ! -e "$REC" ]] && ok "$1: the dated directory the run created is removed" || no "$1: the dated directory the run created is removed"
  eq "$1: the dated directory holds nothing, hidden names included" "" "$(dated)"
}
partial_copy "a drc.json copy that fails partway" drc.json
partial_copy "a tool-versions.txt copy that fails partway" tool-versions.txt
[[ ! -e "$REC/drc.json" ]] \
  && ok "a failed tool-versions.txt copy rolls back the completed drc.json with it" \
  || no "a failed tool-versions.txt copy rolls back the completed drc.json with it"
rm "$BIN/cat"
record_run "$W/partial_retry.out"
eq "the same date retries cleanly after a partial copy" 0 "$rc"
eq "the retried date holds exactly the two records" "drc.json tool-versions.txt" "$(dated)"
eq "a published drc.json has the mode of a plain redirect, not the private copy's 0600" \
  "$(stat -c %a "$W/refmode")" "$(stat -c %a "$REC/drc.json")"
eq "a published tool-versions.txt has the mode of a plain redirect" \
  "$(stat -c %a "$W/refmode")" "$(stat -c %a "$REC/tool-versions.txt")"
rm -rf "$REC"

# Another writer creates the second record's pathname after preflight (the
# klt stub does, well past the gate): the run fails, its completed drc.json
# is rolled back and the other writer's file is untouched.
SQUAT="$REC/tool-versions.txt"
printf '%s' 'competitor-tool-versions' >"$W/competitor.want"
STUB_SQUAT_FILE="$SQUAT" STUB_SQUAT_CONTENT="competitor-tool-versions" record_run "$W/competed.out"
eq "a competing tool-versions.txt: record mode exits 1" 1 "$rc"
if cmp -s "$W/competitor.want" "$SQUAT"; then
  ok "a competing tool-versions.txt: the other writer's bytes survive"
else
  no "a competing tool-versions.txt: the other writer's bytes survive"
fi
eq "a competing tool-versions.txt: the dated directory holds only that file, hidden names included" \
  "tool-versions.txt" "$(dated)"
rm "$SQUAT"
record_run "$W/competed_retry.out"
eq "the same date retries cleanly once the competing file is gone" 0 "$rc"
rm -rf "$REC"

# A directory at the second record's pathname fails the publication without
# gaining a file, and keeps its own contents.
mkdir -p "$REC/tool-versions.txt"
printf 'keep-me\n' >"$REC/tool-versions.txt/inner"
record_run "$W/dirsquat.out"
eq "a directory at tool-versions.txt: record mode exits 1" 1 "$rc"
eq "a directory at tool-versions.txt: it gains no file" "inner" \
  "$(ls -A "$REC/tool-versions.txt" | tr '\n' ' ' | sed 's/ $//')"
eq "a directory at tool-versions.txt: its own file is untouched" "keep-me" "$(cat "$REC/tool-versions.txt/inner")"
eq "a directory at tool-versions.txt: the dated directory holds only that directory, hidden names included" \
  "tool-versions.txt" "$(dated)"
rm "$REC/tool-versions.txt/inner"
rmdir "$REC/tool-versions.txt"
record_run "$W/dirsquat_retry.out"
eq "the same date retries cleanly once the directory is gone" 0 "$rc"
rm -rf "$REC"

# Both records installed, then the published-record leak check fails on a
# JSON another writer left in the dated directory: the run's two records
# are rolled back and the other writer's file is not.
LEAKER="$REC/competitor.json"
printf '%s' '{"path":"/tmp/competitor"}' >"$W/leaker.want"
STUB_SQUAT_FILE="$LEAKER" STUB_SQUAT_CONTENT='{"path":"/tmp/competitor"}' record_run "$W/leaked_dir.out"
eq "a leaking competing record: record mode exits 1" 1 "$rc"
if grep -q "leaks an absolute host path" "$W/leaked_dir.out"; then
  ok "a leaking competing record: the published-record leak check fails the run"
else
  no "a leaking competing record: the published-record leak check fails the run"
fi
if cmp -s "$W/leaker.want" "$LEAKER"; then
  ok "a leaking competing record: the other writer's bytes survive"
else
  no "a leaking competing record: the other writer's bytes survive"
fi
eq "a leaking competing record: the dated directory holds only that file, hidden names included" \
  "competitor.json" "$(dated)"
rm "$LEAKER"
record_run "$W/leaked_dir_retry.out"
eq "the same date retries cleanly once the competing record is gone" 0 "$rc"

echo "1..$((NPASS + NBAD)) pass=$NPASS fail=$NBAD"
[[ $NBAD -eq 0 ]]
