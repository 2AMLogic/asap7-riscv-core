#!/usr/bin/env bash
# Self-test for flow/core/par.sh, the core place-and-route driver.
#
# Needs no PDK, no klt, no OpenROAD, no network and no netlist: it checks the
# driver's refusal contract (usage, non-checkout, a checkout at the wrong pin
# -- the gate that fires before anything is written), the request template's
# invariants (the decision 0004 floorplan values, the grid settings inherited
# from the verified smoke run of PR #234, the wrapper's clock port, and the
# fixed seed), and the driver's verification and publication invariants in a
# scratch fixture repository with stubbed router/provenance tools (--check
# against HEAD:layout/cve2_top.gds even on a dirty working tree, response
# validation in both modes, and staging + leak-guarding records before
# publishing outputs).
#
# The template is extracted from the script and rendered with the same
# values the script assigns, so a drifted setting fails here instead of in
# a 30-minute place-and-route run.
#
# ASAP7 is a predictive PDK; nothing here is fabricated or measured, and
# this script makes no claim about any design.
#
# usage: flow/core/par_test.sh
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

W="$(mktemp -d "${TMPDIR:-/tmp}/asap7-partest.XXXXXX")"
cleanup() { rm -rf "$W"; }
trap cleanup EXIT

PAR="$REPO/flow/core/par.sh"

# ---- refusals (nothing written before the checkout gate) -------------------
out="$W/usage.err"; rc=0
( env -u ASAP7_DIR bash "$PAR" ) >"$out" 2>&1 || rc=$?
eq "no argument and no ASAP7_DIR refuses (exit 2)" 2 "$rc"

out="$W/notgit.err"; rc=0
( env -u ASAP7_DIR bash "$PAR" "$W" ) >"$out" 2>&1 || rc=$?
eq "a directory that is not a git checkout refuses (exit 2)" 2 "$rc"
if grep -q "not a git checkout" "$W/notgit.err"; then
  ok "non-checkout refusal names the git check"
else
  no "non-checkout refusal names the git check"
fi

git init -q "$W/wrongpin"
git -C "$W/wrongpin" -c user.email=t@t -c user.name=t commit -q --allow-empty -m x
out="$W/wrongpin.err"; rc=0
( env -u ASAP7_DIR bash "$PAR" "$W/wrongpin" ) >"$out" 2>&1 || rc=$?
eq "a checkout at the wrong pin refuses (exit 2)" 2 "$rc"
if grep -q "spec/pdk-bringup.md pins" "$W/wrongpin.err"; then
  ok "wrong-pin refusal names the spec pin"
else
  no "wrong-pin refusal names the spec pin"
fi

# ---- the request template's invariants --------------------------------------
# Extract the request heredoc (the one unquoted <<EOF block), render it with
# the values the script assigns, and load it as JSON.
req="$W/par.req.rendered.json"
# shellcheck disable=SC2016  # literal match/replace of unexpanded $W, $TOP, $CELL_LIB
sed -n '/cat >"\$W\/par.req.json" <<EOF/,/^EOF$/p' "$PAR" | sed '1d;$d' \
  | sed -e 's/\${TOP}/cve2_rv32imc_wrapper/g' -e 's/\$TOP/cve2_rv32imc_wrapper/g' \
        -e 's/\${CELL_LIB}/asap7sc7p5t_28_R/g' -e 's/\$CELL_LIB/asap7sc7p5t_28_R/g' \
  >"$req"
if python3 -I -c 'import json,sys; json.load(open(sys.argv[1]))' "$req" 2>/dev/null; then
  ok "request template renders to valid JSON"
else
  no "request template renders to valid JSON"
  echo "1..$((NPASS + NBAD)) pass=$NPASS fail=$NBAD"
  exit 1
fi

j() {  # jq-style extraction via python: j <py-expr over d>
  python3 -I -c "import json,sys; d=json.load(open(sys.argv[1])); print($1)" "$req"
}

eq "floorplan utilisation is decision 0004's 60%" "60" "$(j 'd["floorplan"]["utilization_pct"]')"
eq "floorplan aspect ratio is decision 0004's 1.0" "1.0" "$(j 'd["floorplan"]["aspect_ratio"]')"
eq "floorplan site is asap7sc7p5t" "asap7sc7p5t" "$(j 'd["floorplan"]["site"]')"
eq "M4 x offset is the deck grid origin 0.012" "0.012" "$(j 'd["floorplan"]["tracks"][3]["x_offset_um"]')"
eq "M5 y offset is the deck grid origin 0.012" "0.012" "$(j 'd["floorplan"]["tracks"][4]["y_offset_um"]')"
eq "M6 x offset is the deck grid origin 0.016" "0.016" "$(j 'd["floorplan"]["tracks"][5]["x_offset_um"]')"
eq "M7 y offset is the deck grid origin 0.016" "0.016" "$(j 'd["floorplan"]["tracks"][6]["y_offset_um"]')"
eq "M5 strap width is 0.216 (wide-V4 bar applies)" "0.216" "$(j 'd["power"]["straps"][2]["width_um"]')"
eq "M5 strap pitch is a multiple of 0.048" "1.152" "$(j 'd["power"]["straps"][2]["pitch_um"]')"
eq "M6 strap pitch is a multiple of 0.064" "1.152" "$(j 'd["power"]["straps"][3]["pitch_um"]')"
eq "connects[0] snaps the M3/M4 via stubs on-grid" "['M3', 'M4']" "$(j 'd["power"]["connects"][0]["ongrid"]')"
eq "no power.preset (rejected with the RVT overlay key)" "None" "$(j 'd["power"].get("preset")')"
eq "clock port is the wrapper's clk_i" "clk_i" "$(j 'd["constraints"]["clock_port"]')"
eq "hdl toplevel is the wrapper" "cve2_rv32imc_wrapper" "$(j 'd["hdl_toplevel"]')"
eq "seed is fixed at 1 (reproducibility claim)" "1" "$(j 'd["seed"]')"
eq "output_dbu_um is 0.00025 (deck measures at 0.25 nm)" "0.00025" "$(j 'd["output_dbu_um"]')"
eq "target stage is route" "route" "$(j 'd["target_stage"]')"
eq "tapcell master is named" "TAPCELL_ASAP7_75t_R" "$(j 'd["library"]["tapcell"]["master"]')"

# ---- verification & publication invariants (PDK-free fixture repo) ----------
BIN="$W/bin"; mkdir -p "$BIN"
cat >"$BIN/uvx" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
case "$*" in
  *--version*) echo "uvx 0.0-stub" ;;
  *py7zr.__version__*) echo "1.0-stub" ;;
  *)
    cat >/dev/null
    dest="${*: -2:1}"
    mkdir -p "$dest"
    for g in AO INVBUF OA SEQ SIMPLE; do
      printf 'library (stub_%s) {\n  cell (C_%s) {}\n}\n' "$g" "$g" \
        >"$dest/asap7sc7p5t_${g}_RVT_SS_nldm_stub.lib"
    done
    ;;
esac
STUB
cat >"$BIN/yosys" <<'STUB'
#!/usr/bin/env bash
echo "Yosys 0.67-stub"
STUB
cat >"$BIN/openroad" <<'STUB'
#!/usr/bin/env bash
echo "${STUB_OPENROAD_VERSION:-26Q3-1510-g6cb3f2b704}"
STUB
cat >"$BIN/stub-klt" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "version" ]]; then
  echo "klt 0.9.0"
  exit 0
fi
if [[ "${1:-}" == "place-and-route" ]]; then
  mkdir -p .klt/place-and-route
  sha256sum cve2_rv32imc_wrapper_synth.v | cut -d' ' -f1 >"${STUB_NETLIST_SEEN:-/dev/null}"
  [[ -z "${STUB_EDIT_SRC:-}" ]] || printf 'edited-during-route\n' >"$STUB_EDIT_SRC"
  printf '%s' "${STUB_GDS_CONTENT:-committed-gds-v1}" > .klt/place-and-route/cve2_rv32imc_wrapper.gds
  printf 'VERSION 5.8 ;\nEND DESIGN\n' > .klt/place-and-route/cve2_rv32imc_wrapper.def
  printf 'module cve2_rv32imc_wrapper(input clk_i);\nendmodule\n' > .klt/place-and-route/cve2_rv32imc_wrapper.v
  printf '%s\n' "${STUB_RESPONSE_JSON:-}"
  exit "${STUB_KLT_RC:-0}"
fi
exit 2
STUB
chmod +x "$BIN/uvx" "$BIN/yosys" "$BIN/openroad" "$BIN/stub-klt"

# Minimal pinned ASAP7 checkout + submodules matching the fixture spec.
FA="$W/asap7"
mkdir -p "$FA/asap7sc7p5t_28/LIB/NLDM" \
         "$FA/asap7sc7p5t_28/LEF" \
         "$FA/asap7sc7p5t_28/GDS" \
         "$FA/asap7sc7p5t_28/techlef_misc" \
         "$FA/asap7_pdk_r1p7/cdslib/asap7_TechLib_10"
for g in AO INVBUF OA SEQ SIMPLE; do
  printf 'stub7z' >"$FA/asap7sc7p5t_28/LIB/NLDM/asap7sc7p5t_${g}_RVT_SS_nldm_stub.lib.7z"
done
printf 'VERSION 5.8 ;\n' >"$FA/asap7sc7p5t_28/LEF/asap7sc7p5t_28_R_1x_220121a.lef"
printf 'stubcellgds' >"$FA/asap7sc7p5t_28/GDS/asap7sc7p5t_28_R_220121a.gds"
printf 'VERSION 5.8 ;\n' >"$FA/asap7sc7p5t_28/techlef_misc/asap7_tech_1x_201209.lef"
printf '# layermap\n' >"$FA/asap7_pdk_r1p7/cdslib/asap7_TechLib_10/asap7_fromAPR.layermap"

for sub in "$FA/asap7sc7p5t_28" "$FA/asap7_pdk_r1p7" "$FA"; do
  git init -q "$sub"
  git -C "$sub" -c user.email=t@t -c user.name=t commit -q --allow-empty -m pin
done
SHA_UP="$(git -C "$FA" rev-parse HEAD)"
SHA_CELLS="$(git -C "$FA/asap7sc7p5t_28" rev-parse HEAD)"
SHA_PDK="$(git -C "$FA/asap7_pdk_r1p7" rev-parse HEAD)"

FX="$W/repo"
mkdir -p "$FX/flow/core/records/2026-11-20" "$FX/spec" "$FX/layout"
cp "$REPO/flow/lib.sh" "$REPO/flow/record_lib.py" "$REPO/flow/merge_lib.py" "$FX/flow/"
cp "$PAR" "$FX/flow/core/par.sh"
chmod +x "$FX/flow/core/par.sh"
cat >"$FX/spec/pdk-bringup.md" <<EOF
| Upstream repo | $SHA_UP |
| Cell library | $SHA_CELLS |
| PDK (DRM | $SHA_PDK |
EOF
cat >"$FX/spec/core.md" <<'EOF'
- `klt`: release `klayout-tools==0.9.0` is the pinned release for DRC, LVS and the smoke flow.
EOF
printf 'module cve2_rv32imc_wrapper(input clk_i);\nendmodule\n' \
  >"$FX/flow/core/records/2026-11-20/netlist.v"

git init -q "$FX"
git -C "$FX" add .
git -C "$FX" -c user.email=t@t -c user.name=t commit -q -m "fixture without committed layout"

VALID_RESP='{"status":"ok","stage_reached":"route","power":{"pdn":true,"tapcell_master":"TAPCELL_ASAP7_75t_R"}}'

run_par() {  # extra env/args: runs $FX/flow/core/par.sh with stubbed tools
  PATH="$BIN:$PATH" KLT_CMD="$BIN/stub-klt" env -u ASAP7_DIR "$@"
}

# 1. --check refuses (exit 2) when HEAD has no committed layout, even if an
# untracked layout/cve2_top.gds exists in the working tree.
printf 'untracked-only' >"$FX/layout/cve2_top.gds"
rc=0
STUB_GDS_CONTENT="untracked-only" STUB_RESPONSE_JSON="$VALID_RESP" \
  run_par bash "$FX/flow/core/par.sh" "$FA" --check >"$W/uncommitted.err" 2>&1 || rc=$?
eq "--check with only an untracked layout/cve2_top.gds refuses (exit 2)" 2 "$rc"
if grep -q "HEAD:layout/cve2_top.gds" "$W/uncommitted.err"; then
  ok "--check refusal names HEAD:layout/cve2_top.gds"
else
  no "--check refusal names HEAD:layout/cve2_top.gds"
fi

# Commit the baseline layout at HEAD.
printf 'committed-gds-v1' >"$FX/layout/cve2_top.gds"
git -C "$FX" add layout/cve2_top.gds
git -C "$FX" -c user.email=t@t -c user.name=t commit -q -m "commit baseline layout"

# 2. Clean baseline: --check passes when regenerated GDS matches HEAD and response is valid.
rc=0
STUB_GDS_CONTENT="committed-gds-v1" STUB_RESPONSE_JSON="$VALID_RESP" \
  run_par bash "$FX/flow/core/par.sh" "$FA" --check >"$W/cleancheck.err" 2>&1 || rc=$?
eq "--check exits 0 when GDS matches HEAD and response is valid" 0 "$rc"

# 3. Dirty-baseline regression: router emits different GDS; running record mode
# overwrites working-tree layout/cve2_top.gds, and a subsequent --check must
# still exit 1 against HEAD:layout/cve2_top.gds instead of self-comparing.
rc=0
STUB_GDS_CONTENT="router-gds-v2" STUB_RESPONSE_JSON="$VALID_RESP" \
  run_par bash "$FX/flow/core/par.sh" "$FA" --check >"$W/diff1.err" 2>&1 || rc=$?
eq "--check on clean tree exits 1 when router emits different GDS" 1 "$rc"

rc=0
RECORD_DATE=2026-11-22 STUB_GDS_CONTENT="router-gds-v2" STUB_RESPONSE_JSON="$VALID_RESP" \
  run_par bash "$FX/flow/core/par.sh" "$FA" >"$W/recok.err" 2>&1 || rc=$?
eq "valid record run exits 0" 0 "$rc"
eq "valid record run updates working-tree layout/cve2_top.gds" "router-gds-v2" "$(cat "$FX/layout/cve2_top.gds")"
if [[ -f "$FX/flow/core/records/2026-11-22/par.json" && -f "$FX/flow/core/records/2026-11-22/tool-versions.txt" ]]; then
  ok "valid record run writes par.json and tool-versions.txt"
else
  no "valid record run writes par.json and tool-versions.txt"
fi

rc=0
STUB_GDS_CONTENT="router-gds-v2" STUB_RESPONSE_JSON="$VALID_RESP" \
  run_par bash "$FX/flow/core/par.sh" "$FA" --check >"$W/dirtycheck.err" 2>&1 || rc=$?
eq "--check after record overwrite still exits 1 against HEAD:layout/cve2_top.gds" 1 "$rc"

rc=0
STUB_GDS_CONTENT="committed-gds-v1" STUB_RESPONSE_JSON="$VALID_RESP" \
  run_par bash "$FX/flow/core/par.sh" "$FA" --check >"$W/dirtyheadmatch.err" 2>&1 || rc=$?
eq "--check with dirty working tree exits 0 when router matches HEAD" 0 "$rc"
eq "--check leaves dirty working-tree layout untouched" "router-gds-v2" "$(cat "$FX/layout/cve2_top.gds")"

# Restore clean working-tree layout for the rejected-run suite.
git -C "$FX" checkout -q -- layout/cve2_top.gds

# 4. Rejected runs: power.pdn=false fails in BOTH modes and publishes nothing.
BAD_PDN='{"status":"ok","stage_reached":"route","power":{"pdn":false,"tapcell_master":"TAPCELL_ASAP7_75t_R"}}'
rc=0
RECORD_DATE=2026-11-23 STUB_GDS_CONTENT="bad-pdn-gds" STUB_RESPONSE_JSON="$BAD_PDN" \
  run_par bash "$FX/flow/core/par.sh" "$FA" >"$W/badpdn_rec.err" 2>&1 || rc=$?
eq "record mode exits 1 when power.pdn is false" 1 "$rc"
eq "rejected power.pdn run leaves layout/cve2_top.gds untouched" "committed-gds-v1" "$(cat "$FX/layout/cve2_top.gds")"
if [[ ! -e "$FX/flow/core/records/2026-11-23" ]]; then
  ok "rejected power.pdn run creates no record directory"
else
  no "rejected power.pdn run creates no record directory"
fi

rc=0
STUB_GDS_CONTENT="committed-gds-v1" STUB_RESPONSE_JSON="$BAD_PDN" \
  run_par bash "$FX/flow/core/par.sh" "$FA" --check >"$W/badpdn_chk.err" 2>&1 || rc=$?
eq "--check mode also exits 1 when power.pdn is false (even with matching GDS)" 1 "$rc"

# 5. Rejected runs: missing tapcell_master and incomplete stage_reached fail in both modes.
BAD_TAP='{"status":"ok","stage_reached":"route","power":{"pdn":true,"tapcell_master":null}}'
rc=0
RECORD_DATE=2026-11-24 STUB_GDS_CONTENT="bad-tap-gds" STUB_RESPONSE_JSON="$BAD_TAP" \
  run_par bash "$FX/flow/core/par.sh" "$FA" >"$W/badtap_rec.err" 2>&1 || rc=$?
eq "record mode exits 1 when power.tapcell_master is null" 1 "$rc"
eq "rejected tapcell run leaves layout/cve2_top.gds untouched" "committed-gds-v1" "$(cat "$FX/layout/cve2_top.gds")"
if [[ ! -e "$FX/flow/core/records/2026-11-24" ]]; then
  ok "rejected tapcell run creates no record directory"
else
  no "rejected tapcell run creates no record directory"
fi

rc=0
STUB_GDS_CONTENT="committed-gds-v1" STUB_RESPONSE_JSON="$BAD_TAP" \
  run_par bash "$FX/flow/core/par.sh" "$FA" --check >"$W/badtap_chk.err" 2>&1 || rc=$?
eq "--check mode also exits 1 when power.tapcell_master is null" 1 "$rc"

BAD_STAGE='{"status":"ok","stage_reached":"cts","power":{"pdn":true,"tapcell_master":"TAPCELL_ASAP7_75t_R"}}'
rc=0
STUB_GDS_CONTENT="committed-gds-v1" STUB_RESPONSE_JSON="$BAD_STAGE" \
  run_par bash "$FX/flow/core/par.sh" "$FA" --check >"$W/badstage_chk.err" 2>&1 || rc=$?
eq "--check mode exits 1 when stage_reached is not route" 1 "$rc"

# 6. Rejected runs: a host-path leak in the staged record/tool-versions fails
# before layout/cve2_top.gds is replaced or flow/core/records/<date> is created.
rc=0
RECORD_DATE=2026-11-25 STUB_GDS_CONTENT="leaked-run-gds" STUB_RESPONSE_JSON="$VALID_RESP" \
  STUB_OPENROAD_VERSION="/Users/ops/bin/openroad 26Q3" \
  run_par bash "$FX/flow/core/par.sh" "$FA" >"$W/leak_tv.err" 2>&1 || rc=$?
eq "record mode exits 1 when staged tool-versions.txt leaks a host path" 1 "$rc"
if grep -q "leaks an absolute host path" "$W/leak_tv.err"; then
  ok "leaked tool-versions.txt dies in record_leak_guard"
else
  no "leaked tool-versions.txt dies in record_leak_guard"
fi
eq "leaked tool-versions.txt leaves layout/cve2_top.gds untouched" "committed-gds-v1" "$(cat "$FX/layout/cve2_top.gds")"
if [[ ! -e "$FX/flow/core/records/2026-11-25" ]]; then
  ok "leaked tool-versions.txt creates no record directory"
else
  no "leaked tool-versions.txt creates no record directory"
fi

LEAK_RESP='{"status":"ok","stage_reached":"route","leaked":"/Users/ops/secret","power":{"pdn":true,"tapcell_master":"TAPCELL_ASAP7_75t_R"}}'
rc=0
RECORD_DATE=2026-11-26 STUB_GDS_CONTENT="leaked-json-gds" STUB_RESPONSE_JSON="$LEAK_RESP" \
  run_par bash "$FX/flow/core/par.sh" "$FA" >"$W/leak_json.err" 2>&1 || rc=$?
eq "record mode exits 1 when staged par.json leaks a host path" 1 "$rc"
eq "leaked par.json leaves layout/cve2_top.gds untouched" "committed-gds-v1" "$(cat "$FX/layout/cve2_top.gds")"
if [[ ! -e "$FX/flow/core/records/2026-11-26" ]]; then
  ok "leaked par.json creates no record directory"
else
  no "leaked par.json creates no record directory"
fi

# 7. Response must confirm success: each omitted key fails in BOTH modes.
for omit in status stage_reached; do
  RESP="$(python3 -I -c 'import json,sys; d=json.loads(sys.argv[1]); d.pop(sys.argv[2]); print(json.dumps(d))' "$VALID_RESP" "$omit")"
  rc=0
  RECORD_DATE=2026-11-27 STUB_GDS_CONTENT="omit-$omit-gds" STUB_RESPONSE_JSON="$RESP" \
    run_par bash "$FX/flow/core/par.sh" "$FA" >"$W/omit_$omit.rec.err" 2>&1 || rc=$?
  eq "record mode exits 1 when response omits $omit" 1 "$rc"
  eq "omitted $omit leaves layout/cve2_top.gds untouched" "committed-gds-v1" "$(cat "$FX/layout/cve2_top.gds")"
  [[ ! -e "$FX/flow/core/records/2026-11-27" ]] && ok "omitted $omit creates no record directory" || no "omitted $omit creates no record directory"
  rc=0
  STUB_GDS_CONTENT="committed-gds-v1" STUB_RESPONSE_JSON="$RESP" \
    run_par bash "$FX/flow/core/par.sh" "$FA" --check >"$W/omit_$omit.chk.err" 2>&1 || rc=$?
  eq "--check exits 1 when response omits $omit" 1 "$rc"
done

# 8. The routed input is the committed netlist: a newer untracked netlist and an
# edit made while the router runs change neither the input nor the records.
mkdir -p "$FX/flow/core/records/2026-11-30"
printf 'module untracked_newer;\nendmodule\n' >"$FX/flow/core/records/2026-11-30/netlist.v"
COMMITTED_NL_SHA="$(git -C "$FX" show HEAD:flow/core/records/2026-11-20/netlist.v | sha256sum | cut -d' ' -f1)"
rc=0
RECORD_DATE=2026-11-28 STUB_GDS_CONTENT="router-gds-v3" STUB_RESPONSE_JSON="$VALID_RESP" \
  STUB_NETLIST_SEEN="$W/seen.sha" STUB_EDIT_SRC="$FX/flow/core/records/2026-11-20/netlist.v" \
  run_par bash "$FX/flow/core/par.sh" "$FA" >"$W/input.err" 2>&1 || rc=$?
eq "record run with untracked newer netlist and mid-route edit exits 0" 0 "$rc"
eq "router receives the committed netlist, not the untracked/edited one" "$COMMITTED_NL_SHA" "$(cat "$W/seen.sha" 2>/dev/null)"
if grep -q "$COMMITTED_NL_SHA" "$FX/flow/core/records/2026-11-28/par.json" \
   && grep -q "$COMMITTED_NL_SHA" "$FX/flow/core/records/2026-11-28/tool-versions.txt" \
   && grep -q 'flow/core/records/2026-11-20/netlist.v' "$FX/flow/core/records/2026-11-28/par.json"; then
  ok "par.json and tool-versions.txt record the hash and path of the routed input"
else
  no "par.json and tool-versions.txt record the hash and path of the routed input"
fi
git -C "$FX" checkout -q -- layout/cve2_top.gds flow/core/records/2026-11-20/netlist.v
rm -rf "$FX/flow/core/records/2026-11-30" "$FX/flow/core/records/2026-11-28"

# 9. A failure during the final write rolls back: the previous layout stays and
# the record directory is free, so the retry succeeds.
mkdir -p "$FX/flow/core/records/2026-11-29/tool-versions.txt"
rc=0
RECORD_DATE=2026-11-29 STUB_GDS_CONTENT="publish-fail-gds" STUB_RESPONSE_JSON="$VALID_RESP" \
  run_par bash "$FX/flow/core/par.sh" "$FA" >"$W/pubfail.err" 2>&1 || rc=$?
eq "record mode exits 1 when the final record write fails" 1 "$rc"
eq "failed publish leaves the previous layout in place" "committed-gds-v1" "$(cat "$FX/layout/cve2_top.gds")"
[[ ! -e "$FX/flow/core/records/2026-11-29/par.json" ]] && ok "failed publish removes the partial par.json" || no "failed publish removes the partial par.json"
if compgen -G "$FX/layout/*.tmp.*" >/dev/null; then no "failed publish leaves no temporary layout"; else ok "failed publish leaves no temporary layout"; fi
rmdir "$FX/flow/core/records/2026-11-29/tool-versions.txt"
rc=0
RECORD_DATE=2026-11-29 STUB_GDS_CONTENT="publish-retry-gds" STUB_RESPONSE_JSON="$VALID_RESP" \
  run_par bash "$FX/flow/core/par.sh" "$FA" >"$W/pubretry.err" 2>&1 || rc=$?
eq "retry after a failed publish exits 0" 0 "$rc"
eq "retry publishes the new layout" "publish-retry-gds" "$(cat "$FX/layout/cve2_top.gds")"

# 10. --check input pin (issue #266): the byte-compare validates the newest
# committed par.json's regeneration claim, so --check must first refuse unless
# the netlist selected at HEAD is the one that record pins in
# core_flow.input_netlist -- otherwise a newer committed netlist (a
# re-synthesis, #122) would be routed while the evidence pins the older one,
# and the compare would report an unexplained GDS difference instead of the
# moved input. Record mode is untouched: it is how a moved input is re-pinned.
# No par.json is committed yet (the 2026-11-22 one from case 3 and the
# 2026-11-29 one from case 9 are working-tree only, invisible to Git reads),
# so the first case is the first-run edge: no pin to compare against, the
# byte-compare decides, behaviour unchanged.
NL_SHA="$(git -C "$FX" show HEAD:flow/core/records/2026-11-20/netlist.v | sha256sum | cut -d' ' -f1)"
rm -f "$W/seen10a.sha"
rc=0
STUB_GDS_CONTENT="committed-gds-v1" STUB_RESPONSE_JSON="$VALID_RESP" \
  STUB_NETLIST_SEEN="$W/seen10a.sha" \
  run_par bash "$FX/flow/core/par.sh" "$FA" --check >"$W/pin_none.err" 2>&1 || rc=$?
eq "--check with no committed par.json keeps first-run behaviour (exit 0)" 0 "$rc"
eq "no-par.json --check still routes the selected netlist" "$NL_SHA" "$(cat "$W/seen10a.sha" 2>/dev/null)"

# Two committed records: the older pins a stale input, the newest pins the
# netlist HEAD selects. --check must compare against the newest, not the
# older, and pass.
mkdir -p "$FX/flow/core/records/2026-11-21"
printf '{"core_flow":{"input_netlist":{"path":"flow/core/records/2026-11-03/netlist.v","sha256":"%064d"}}}\n' 0 \
  >"$FX/flow/core/records/2026-11-21/par.json"
printf '{"core_flow":{"input_netlist":{"path":"flow/core/records/2026-11-20/netlist.v","sha256":"%s"}}}\n' "$NL_SHA" \
  >"$FX/flow/core/records/2026-11-22/par.json"
git -C "$FX" add flow/core/records/2026-11-21/par.json flow/core/records/2026-11-22/par.json
git -C "$FX" -c user.email=t@t -c user.name=t commit -q -m "commit two par records"
rm -f "$W/seen10b.sha"
rc=0
STUB_GDS_CONTENT="committed-gds-v1" STUB_RESPONSE_JSON="$VALID_RESP" \
  STUB_NETLIST_SEEN="$W/seen10b.sha" \
  run_par bash "$FX/flow/core/par.sh" "$FA" --check >"$W/pin_match.err" 2>&1 || rc=$?
eq "--check exits 0 when the newest par.json pins the selected netlist" 0 "$rc"
eq "pin-match --check routes the selected netlist" "$NL_SHA" "$(cat "$W/seen10b.sha" 2>/dev/null)"

# A newer committed netlist moves the selection off the pinned input: --check
# refuses (exit 1) naming both path+hash pairs, before any routing.
mkdir -p "$FX/flow/core/records/2026-11-24"
printf 'module cve2_rv32imc_wrapper_resynth(input clk_i);\nendmodule\n' \
  >"$FX/flow/core/records/2026-11-24/netlist.v"
NEW_NL_SHA="$(sha256sum "$FX/flow/core/records/2026-11-24/netlist.v" | cut -d' ' -f1)"
git -C "$FX" add flow/core/records/2026-11-24/netlist.v
git -C "$FX" -c user.email=t@t -c user.name=t commit -q -m "commit newer netlist"
rm -f "$W/seen10c.sha"
rc=0
STUB_GDS_CONTENT="committed-gds-v1" STUB_RESPONSE_JSON="$VALID_RESP" \
  STUB_NETLIST_SEEN="$W/seen10c.sha" \
  run_par bash "$FX/flow/core/par.sh" "$FA" --check >"$W/pin_mismatch.err" 2>&1 || rc=$?
eq "--check exits 1 when the selected netlist is not the pinned input" 1 "$rc"
if [[ ! -e "$W/seen10c.sha" ]]; then
  ok "pin mismatch refuses before routing"
else
  no "pin mismatch refuses before routing"
fi
for want in "flow/core/records/2026-11-24/netlist.v" "$NEW_NL_SHA" \
            "flow/core/records/2026-11-22/par.json" \
            "flow/core/records/2026-11-20/netlist.v" "$NL_SHA"; do
  if grep -qF "$want" "$W/pin_mismatch.err"; then
    ok "mismatch message names $want"
  else
    no "mismatch message names $want"
  fi
done

# Record mode is how a moved input is re-pinned: it routes the newest netlist
# and writes the record pinning it; committing that record restores --check.
rm -f "$W/seen10d.sha"
rc=0
RECORD_DATE=2026-12-01 STUB_GDS_CONTENT="router-gds-v4" STUB_RESPONSE_JSON="$VALID_RESP" \
  STUB_NETLIST_SEEN="$W/seen10d.sha" \
  run_par bash "$FX/flow/core/par.sh" "$FA" >"$W/pin_rec.err" 2>&1 || rc=$?
eq "record mode is not gated by the pin (exit 0)" 0 "$rc"
eq "record mode routes the newest netlist" "$NEW_NL_SHA" "$(cat "$W/seen10d.sha" 2>/dev/null)"
if grep -q "$NEW_NL_SHA" "$FX/flow/core/records/2026-12-01/par.json" \
   && grep -q 'flow/core/records/2026-11-24/netlist.v' "$FX/flow/core/records/2026-12-01/par.json"; then
  ok "the refreshed par.json pins the new input"
else
  no "the refreshed par.json pins the new input"
fi
git -C "$FX" add flow/core/records/2026-12-01 layout/cve2_top.gds
git -C "$FX" -c user.email=t@t -c user.name=t commit -q -m "commit refreshed record and layout"
rc=0
STUB_GDS_CONTENT="router-gds-v4" STUB_RESPONSE_JSON="$VALID_RESP" \
  run_par bash "$FX/flow/core/par.sh" "$FA" --check >"$W/pin_rematch.err" 2>&1 || rc=$?
eq "--check exits 0 again once the newest par.json re-pins the input" 0 "$rc"

# A committed par.json without core_flow.input_netlist is a broken record:
# --check fails closed instead of silently skipping the pin comparison.
mkdir -p "$FX/flow/core/records/2026-12-02"
printf '{"note":"not a par record"}\n' >"$FX/flow/core/records/2026-12-02/par.json"
git -C "$FX" add flow/core/records/2026-12-02/par.json
git -C "$FX" -c user.email=t@t -c user.name=t commit -q -m "commit broken par record"
rc=0
STUB_GDS_CONTENT="router-gds-v4" STUB_RESPONSE_JSON="$VALID_RESP" \
  run_par bash "$FX/flow/core/par.sh" "$FA" --check >"$W/pin_broken.err" 2>&1 || rc=$?
eq "--check fails closed on a par.json without core_flow.input_netlist" 1 "$rc"
if grep -q "2026-12-02/par.json" "$W/pin_broken.err"; then
  ok "broken-record refusal names the par.json"
else
  no "broken-record refusal names the par.json"
fi

echo "1..$((NPASS + NBAD)) pass=$NPASS fail=$NBAD"
[[ "$NBAD" -eq 0 ]]
