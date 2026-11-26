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
# validation in both modes, staging + leak-guarding records before publishing
# outputs, record publication that leaves nothing of the run behind when a
# copy fails partway or another writer holds a record pathname, and the
# --check --export bundle: routed DEF and routed Verilog published with a
# provenance manifest only on the byte-identical path, with every failure
# leaving the requested destination free for a retry).
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
  [[ -z "${STUB_MKDIR_AT:-}" ]] || mkdir -p "$STUB_MKDIR_AT"
  if [[ -n "${STUB_SQUAT_FILE:-}" ]]; then
    mkdir -p -- "$(dirname -- "$STUB_SQUAT_FILE")"
    printf '%s' "${STUB_SQUAT_CONTENT:-}" >"$STUB_SQUAT_FILE"
  fi
  printf '%s' "${STUB_GDS_CONTENT:-committed-gds-v1}" > .klt/place-and-route/cve2_rv32imc_wrapper.gds
  # The routed Verilog carries different bytes from the synthesis input, so a
  # test can tell an exported routed netlist from an exported input netlist.
  [[ -n "${STUB_OMIT_DEF:-}" ]] || printf 'VERSION 5.8 ;\nEND DESIGN\n' > .klt/place-and-route/cve2_rv32imc_wrapper.def
  [[ -n "${STUB_OMIT_V:-}" ]] || printf 'module cve2_rv32imc_wrapper(input clk_i);\n  wire stub_routed_w;\nendmodule\n' > .klt/place-and-route/cve2_rv32imc_wrapper.v
  [[ -z "${STUB_ODB_CONTENT:-}" ]] || printf '%s' "${STUB_ODB_CONTENT}" > .klt/place-and-route/cve2_rv32imc_wrapper.odb
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
cp "$PAR" "$REPO/flow/core/record_publish.sh" "$FX/flow/core/"
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

# 9b. A record copy that fails partway, or a record pathname another writer
# holds (issue #286). Each record is copied to completion under a private
# name in the dated directory and linked to its final pathname only then,
# without replacement: a partial copy never occupies a record pathname (a
# truncated par.json would read as an existing record and refuse the retry),
# and a rollback removes what this run installed and nothing else, leaving
# whatever another writer put there byte-for-byte. The stubbed `cat` writes
# four bytes of one staged record and exits 1, recording the pathname it was
# writing, so each case can see the partial copy was made inside the dated
# directory and then removed.
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
REC="$FX/flow/core/records"
cp "$FX/layout/cve2_top.gds" "$W/prev.gds"
: >"$W/refmode"
dated() {  # <date>: every entry of the dated directory, hidden names included
  ls -A "$REC/$1" 2>/dev/null | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//'
}
after_failure() {  # <date> <expected entries> <label>
  eq "$3: the dated directory holds exactly those entries, hidden names included" \
    "$2" "$(dated "$1")"
  if cmp -s "$W/prev.gds" "$FX/layout/cve2_top.gds"; then
    ok "$3: the previous layout is byte-identical"
  else
    no "$3: the previous layout is byte-identical"
  fi
  if compgen -G "$FX/layout/*.tmp.*" >/dev/null; then
    no "$3: no temporary layout remains"
  else
    ok "$3: no temporary layout remains"
  fi
}
partial_copy() {  # <label> <date> <record>: run with that record's copy failing partway
  local seen="$W/catseen.$2"
  rc=0
  RECORD_DATE="$2" STUB_GDS_CONTENT="partial-$2-gds" STUB_RESPONSE_JSON="$VALID_RESP" \
    STUB_CAT_FAIL="$3" STUB_CAT_SEEN="$seen" \
    run_par bash "$FX/flow/core/par.sh" "$FA" >"$W/partial_$2.err" 2>&1 || rc=$?
  eq "$1: record mode exits 1" 1 "$rc"
  eq "$1: the partial copy was written inside the dated directory" \
    "$REC/$2" "$(dirname "$(cat "$seen")")"
  [[ ! -e "$(cat "$seen")" ]] && ok "$1: the partial copy is removed" || no "$1: the partial copy is removed"
  [[ ! -e "$REC/$2" ]] && ok "$1: the dated directory the run created is removed" || no "$1: the dated directory the run created is removed"
  after_failure "$2" "" "$1"
}
partial_copy "a par.json copy that fails partway" 2026-12-10 par.json
partial_copy "a tool-versions.txt copy that fails partway" 2026-12-11 tool-versions.txt
[[ ! -e "$REC/2026-12-11/par.json" ]] \
  && ok "a failed tool-versions.txt copy rolls back the completed par.json with it" \
  || no "a failed tool-versions.txt copy rolls back the completed par.json with it"
rm "$BIN/cat"

# Another writer creates the second record's pathname after preflight (the
# router stub does, well past the gate): the run fails, its completed
# par.json is rolled back and the other writer's file is untouched.
SQUAT="$REC/2026-12-12/tool-versions.txt"
printf '%s' 'competitor-tool-versions' >"$W/competitor.want"
rc=0
RECORD_DATE=2026-12-12 STUB_GDS_CONTENT="competed-gds" STUB_RESPONSE_JSON="$VALID_RESP" \
  STUB_SQUAT_FILE="$SQUAT" STUB_SQUAT_CONTENT="competitor-tool-versions" \
  run_par bash "$FX/flow/core/par.sh" "$FA" >"$W/competed.err" 2>&1 || rc=$?
eq "a competing tool-versions.txt: record mode exits 1" 1 "$rc"
if cmp -s "$W/competitor.want" "$SQUAT"; then
  ok "a competing tool-versions.txt: the other writer's bytes survive"
else
  no "a competing tool-versions.txt: the other writer's bytes survive"
fi
after_failure 2026-12-12 "tool-versions.txt" "a competing tool-versions.txt"

# A directory at the second record's pathname fails the publication without
# gaining a file, and keeps its own contents.
mkdir -p "$REC/2026-12-13/tool-versions.txt"
printf 'keep-me\n' >"$REC/2026-12-13/tool-versions.txt/inner"
rc=0
RECORD_DATE=2026-12-13 STUB_GDS_CONTENT="dir-squat-gds" STUB_RESPONSE_JSON="$VALID_RESP" \
  run_par bash "$FX/flow/core/par.sh" "$FA" >"$W/dirsquat.err" 2>&1 || rc=$?
eq "a directory at tool-versions.txt: record mode exits 1" 1 "$rc"
eq "a directory at tool-versions.txt: it gains no file" "inner" \
  "$(ls -A "$REC/2026-12-13/tool-versions.txt" | tr '\n' ' ' | sed 's/ $//')"
eq "a directory at tool-versions.txt: its own file is untouched" "keep-me" \
  "$(cat "$REC/2026-12-13/tool-versions.txt/inner")"
after_failure 2026-12-13 "tool-versions.txt" "a directory at tool-versions.txt"

# Both records installed, then the published-record leak check fails on a
# JSON another writer left in the dated directory: the run's two records
# are rolled back and the other writer's file is not.
LEAKER="$REC/2026-12-14/competitor.json"
printf '%s' '{"path":"/tmp/competitor"}' >"$W/leaker.want"
rc=0
RECORD_DATE=2026-12-14 STUB_GDS_CONTENT="leaked-dir-gds" STUB_RESPONSE_JSON="$VALID_RESP" \
  STUB_SQUAT_FILE="$LEAKER" STUB_SQUAT_CONTENT='{"path":"/tmp/competitor"}' \
  run_par bash "$FX/flow/core/par.sh" "$FA" >"$W/leaked_dir.err" 2>&1 || rc=$?
eq "a leaking competing record: record mode exits 1" 1 "$rc"
if grep -q "leaks an absolute host path" "$W/leaked_dir.err"; then
  ok "a leaking competing record: the published-record leak check fails the run"
else
  no "a leaking competing record: the published-record leak check fails the run"
fi
if cmp -s "$W/leaker.want" "$LEAKER"; then
  ok "a leaking competing record: the other writer's bytes survive"
else
  no "a leaking competing record: the other writer's bytes survive"
fi
after_failure 2026-12-14 "competitor.json" "a leaking competing record"

# Clearing each fault leaves the same date retryable.
retry_date() {  # <label> <date>
  rc=0
  RECORD_DATE="$2" STUB_GDS_CONTENT="retry-$2-gds" STUB_RESPONSE_JSON="$VALID_RESP" \
    run_par bash "$FX/flow/core/par.sh" "$FA" >"$W/retry_$2.err" 2>&1 || rc=$?
  eq "$1: the same date retries cleanly" 0 "$rc"
}
retry_date "a failed par.json copy" 2026-12-10
retry_date "a failed tool-versions.txt copy" 2026-12-11
eq "the retried date holds exactly the two records" "par.json tool-versions.txt" "$(dated 2026-12-11)"
eq "a published par.json has the mode of a plain redirect, not the private copy's 0600" \
  "$(stat -c %a "$W/refmode")" "$(stat -c %a "$REC/2026-12-11/par.json")"
eq "a published tool-versions.txt has the mode of a plain redirect" \
  "$(stat -c %a "$W/refmode")" "$(stat -c %a "$REC/2026-12-11/tool-versions.txt")"
rm "$SQUAT"
retry_date "a competing file" 2026-12-12
rm "$REC/2026-12-13/tool-versions.txt/inner"
rmdir "$REC/2026-12-13/tool-versions.txt"
retry_date "a directory at a record pathname" 2026-12-13
rm "$LEAKER"
retry_date "a leaking competing record" 2026-12-14

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

# 11. --export (issue #283): --check --export <dir> publishes the routed DEF,
# the matching routed Verilog and a provenance manifest as one directory, only
# on the byte-identical comparison path; every failure leaves the requested
# destination free for a retry. --check must first be passable again: the
# newest committed par.json is currently the broken 2026-12-02 record, so
# commit a good one pinning the netlist HEAD selects.
mkdir -p "$FX/flow/core/records/2026-12-03"
printf '{"core_flow":{"input_netlist":{"path":"flow/core/records/2026-11-24/netlist.v","sha256":"%s"}}}\n' "$NEW_NL_SHA" \
  >"$FX/flow/core/records/2026-12-03/par.json"
git -C "$FX" add flow/core/records/2026-12-03/par.json
git -C "$FX" -c user.email=t@t -c user.name=t commit -q -m "commit good pin record"
FX_HEAD="$(git -C "$FX" rev-parse HEAD)"

mj() {  # mj <export-dir> <py-expr over m>: one value from a bundle's manifest.json
  python3 -I -c "import json,sys; m=json.load(open(sys.argv[1]+'/manifest.json',encoding='utf-8')); print($2)" "$1"
}
bundle_consistent() {  # <dir>: every artifacts row matches the bytes on disk, and vice versa
  python3 -I - "$1" <<'PY'
import hashlib, json, os, sys
d = sys.argv[1]
m = json.load(open(os.path.join(d, "manifest.json"), encoding="utf-8"))
listed = set()
for a in m["artifacts"]:
    p = os.path.join(d, a["filename"])
    assert os.path.isfile(p), "manifest lists a missing file: " + a["filename"]
    assert hashlib.sha256(open(p, "rb").read()).hexdigest() == a["sha256"], "digest mismatch for " + a["filename"]
    listed.add(a["filename"])
on_disk = set(os.listdir(d)) - {"manifest.json"}
assert listed == on_disk, "manifest and directory disagree: %r vs %r" % (sorted(listed), sorted(on_disk))
PY
}

# Refusals: --export without --check, without a value, and onto an existing
# destination are all exit 2; the existing-destination one fires before routing.
rc=0
run_par bash "$FX/flow/core/par.sh" "$FA" --export "$W/exp-nocheck" >"$W/exp_nocheck.err" 2>&1 || rc=$?
eq "--export without --check refuses (exit 2)" 2 "$rc"
if grep -q "rerun with --check" "$W/exp_nocheck.err"; then
  ok "no-check export refusal names --check"
else
  no "no-check export refusal names --check"
fi
[[ ! -e "$W/exp-nocheck" ]] && ok "no-check export refusal publishes nothing" || no "no-check export refusal publishes nothing"

rc=0
run_par bash "$FX/flow/core/par.sh" "$FA" --check --export >"$W/exp_noval.err" 2>&1 || rc=$?
eq "--export without a directory argument refuses (exit 2)" 2 "$rc"

mkdir -p "$W/exp-taken"
rm -f "$W/seen11r.sha"
rc=0
STUB_GDS_CONTENT="router-gds-v4" STUB_RESPONSE_JSON="$VALID_RESP" STUB_NETLIST_SEEN="$W/seen11r.sha" \
  run_par bash "$FX/flow/core/par.sh" "$FA" --check --export "$W/exp-taken" >"$W/exp_taken.err" 2>&1 || rc=$?
eq "--export to an existing destination refuses (exit 2)" 2 "$rc"
if grep -q "already exists" "$W/exp_taken.err"; then
  ok "existing-destination refusal names the destination"
else
  no "existing-destination refusal names the destination"
fi
if [[ ! -e "$W/seen11r.sha" ]]; then
  ok "existing-destination refusal fires before routing"
else
  no "existing-destination refusal fires before routing"
fi

# Successful export after normal scratch cleanup: the run's TMPDIR is a
# dedicated directory asserted empty afterwards, so the bundle cannot be
# leftover scratch and must have been copied out before cleanup.
EXP="$W/exp-bundle"; ETMP="$W/exp-tmp"; mkdir -p "$ETMP"
rm -f "$W/seen11s.sha"
rc=0
TMPDIR="$ETMP" STUB_GDS_CONTENT="router-gds-v4" STUB_RESPONSE_JSON="$VALID_RESP" \
  STUB_NETLIST_SEEN="$W/seen11s.sha" \
  run_par bash "$FX/flow/core/par.sh" "$FA" --check --export "$EXP" >"$W/exp_ok.err" 2>&1 || rc=$?
eq "--check --export exits 0 when the GDS matches HEAD" 0 "$rc"
eq "export run routes the committed netlist" "$NEW_NL_SHA" "$(cat "$W/seen11s.sha" 2>/dev/null)"
if compgen -G "$ETMP/asap7-*" >/dev/null; then
  no "export run cleans its scratch directory"
else
  ok "export run cleans its scratch directory"
fi
if grep -q "export ->" "$W/exp_ok.err"; then
  ok "successful export announces the destination"
else
  no "successful export announces the destination"
fi
printf 'VERSION 5.8 ;\nEND DESIGN\n' >"$W/exp.def.want"
printf 'module cve2_rv32imc_wrapper(input clk_i);\n  wire stub_routed_w;\nendmodule\n' >"$W/exp.v.want"
if cmp -s "$EXP/cve2_rv32imc_wrapper.def" "$W/exp.def.want"; then
  ok "exported DEF carries the router's DEF bytes"
else
  no "exported DEF carries the router's DEF bytes"
fi
if cmp -s "$EXP/cve2_rv32imc_wrapper.v" "$W/exp.v.want"; then
  ok "exported Verilog carries the routed netlist bytes"
else
  no "exported Verilog carries the routed netlist bytes"
fi
if cmp -s "$EXP/cve2_rv32imc_wrapper.v" "$FX/flow/core/records/2026-11-24/netlist.v"; then
  no "exported Verilog is the routed netlist, not the synthesis input"
else
  ok "exported Verilog is the routed netlist, not the synthesis input"
fi
eq "export holds exactly the DEF, the routed Verilog and the manifest" \
   "cve2_rv32imc_wrapper.def cve2_rv32imc_wrapper.v manifest.json" \
   "$(ls "$EXP" | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//')"
eq "manifest schema_version is 1" "1" "$(mj "$EXP" 'm["schema_version"]')"
eq "manifest top_cell is the wrapper" "cve2_rv32imc_wrapper" "$(mj "$EXP" 'm["top_cell"]')"
eq "manifest input_rev is the fixture's HEAD commit" "$FX_HEAD" "$(mj "$EXP" 'm["input_rev"]')"
eq "manifest input_netlist path is the routed input" "flow/core/records/2026-11-24/netlist.v" "$(mj "$EXP" 'm["input_netlist"]["path"]')"
eq "manifest input_netlist sha256 is the routed input" "$NEW_NL_SHA" "$(mj "$EXP" 'm["input_netlist"]["sha256"]')"
eq "manifest gds path is the committed layout" "layout/cve2_top.gds" "$(mj "$EXP" 'm["gds"]["path"]')"
eq "manifest gds sha256 is the byte-compared GDS" "$(printf '%s' 'router-gds-v4' | sha256sum | cut -d' ' -f1)" "$(mj "$EXP" 'm["gds"]["sha256"]')"
if bundle_consistent "$EXP"; then
  ok "manifest artifact rows match the exported bytes, with nothing unlisted"
else
  no "manifest artifact rows match the exported bytes, with nothing unlisted"
fi

# An ODB produced by the pinned run accompanies the DEF; without one, the
# bundle above is DEF + Verilog + manifest only.
EXP2="$W/exp-odb"; ETMP2="$W/exp-tmp2"; mkdir -p "$ETMP2"
rc=0
TMPDIR="$ETMP2" STUB_GDS_CONTENT="router-gds-v4" STUB_RESPONSE_JSON="$VALID_RESP" \
  STUB_ODB_CONTENT="stub-odb-v1" \
  run_par bash "$FX/flow/core/par.sh" "$FA" --check --export "$EXP2" >"$W/exp_odb.err" 2>&1 || rc=$?
eq "--check --export with an ODB in the run tree exits 0" 0 "$rc"
eq "the ODB accompanies the exported DEF" "stub-odb-v1" "$(cat "$EXP2/cve2_rv32imc_wrapper.odb" 2>/dev/null)"
eq "export with an ODB holds DEF, ODB, Verilog and manifest" \
   "cve2_rv32imc_wrapper.def cve2_rv32imc_wrapper.odb cve2_rv32imc_wrapper.v manifest.json" \
   "$(ls "$EXP2" | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//')"
if bundle_consistent "$EXP2"; then
  ok "the ODB's manifest row matches its exported bytes"
else
  no "the ODB's manifest row matches its exported bytes"
fi

# A missing DEF or a missing Verilog fails the run before any export.
EXP3="$W/exp-missing"
rc=0
STUB_GDS_CONTENT="router-gds-v4" STUB_RESPONSE_JSON="$VALID_RESP" STUB_OMIT_DEF=1 \
  run_par bash "$FX/flow/core/par.sh" "$FA" --check --export "$EXP3" >"$W/exp_nodef.err" 2>&1 || rc=$?
eq "--check --export exits 1 when the router produced no DEF" 1 "$rc"
if grep -q "produced no cve2_rv32imc_wrapper.def" "$W/exp_nodef.err"; then
  ok "missing-DEF failure names the DEF"
else
  no "missing-DEF failure names the DEF"
fi
[[ ! -e "$EXP3" ]] && ok "missing DEF publishes no export" || no "missing DEF publishes no export"

rc=0
STUB_GDS_CONTENT="router-gds-v4" STUB_RESPONSE_JSON="$VALID_RESP" STUB_OMIT_V=1 \
  run_par bash "$FX/flow/core/par.sh" "$FA" --check --export "$EXP3" >"$W/exp_nov.err" 2>&1 || rc=$?
eq "--check --export exits 1 when the router produced no Verilog" 1 "$rc"
if grep -q "produced no cve2_rv32imc_wrapper.v" "$W/exp_nov.err"; then
  ok "missing-Verilog failure names the Verilog"
else
  no "missing-Verilog failure names the Verilog"
fi
[[ ! -e "$EXP3" ]] && ok "missing Verilog publishes no export" || no "missing Verilog publishes no export"

# A rejected route response fails before the comparison, so no bundle.
rc=0
STUB_GDS_CONTENT="router-gds-v4" STUB_RESPONSE_JSON="$BAD_PDN" \
  run_par bash "$FX/flow/core/par.sh" "$FA" --check --export "$EXP3" >"$W/exp_badresp.err" 2>&1 || rc=$?
eq "--check --export exits 1 on a rejected route response" 1 "$rc"
[[ ! -e "$EXP3" ]] && ok "rejected response publishes no export" || no "rejected response publishes no export"

# A GDS mismatch, against a dirty working-tree layout that must not
# self-compare, fails the byte-compare: no bundle, no layout overwrite.
printf 'dirty-working-layout' >"$FX/layout/cve2_top.gds"
rc=0
STUB_GDS_CONTENT="router-gds-v5" STUB_RESPONSE_JSON="$VALID_RESP" \
  run_par bash "$FX/flow/core/par.sh" "$FA" --check --export "$EXP3" >"$W/exp_mismatch.err" 2>&1 || rc=$?
eq "--check --export exits 1 on a GDS mismatch against HEAD" 1 "$rc"
[[ ! -e "$EXP3" ]] && ok "GDS mismatch publishes no export" || no "GDS mismatch publishes no export"
eq "GDS mismatch leaves the dirty working-tree layout untouched" "dirty-working-layout" "$(cat "$FX/layout/cve2_top.gds")"
git -C "$FX" checkout -q -- layout/cve2_top.gds

# A checksum failure after the byte comparison must leave no export. Only
# fail sha256sum for the routed GDS, so input pinning and comparison succeed.
REAL_SHA256SUM="$(command -v sha256sum)"
cat >"$BIN/sha256sum" <<'STUB'
#!/usr/bin/env bash
if [[ ${1:-} == */place-and-route/cve2_rv32imc_wrapper.gds ]]; then exit 1; fi
exec "$REAL_SHA256SUM" "$@"
STUB
chmod +x "$BIN/sha256sum"
EXP_SHA="$W/exp-checksum"
rc=0
REAL_SHA256SUM="$REAL_SHA256SUM" STUB_GDS_CONTENT="router-gds-v4" STUB_RESPONSE_JSON="$VALID_RESP" \
  run_par bash "$FX/flow/core/par.sh" "$FA" --check --export "$EXP_SHA" >"$W/exp_checksum.err" 2>&1 || rc=$?
eq "an unreadable routed GDS checksum fails the export" 1 "$rc"
[[ ! -e "$EXP_SHA" ]] && ok "checksum failure publishes nothing" || no "checksum failure publishes nothing"
rm "$BIN/sha256sum"
rc=0
STUB_GDS_CONTENT="router-gds-v4" STUB_RESPONSE_JSON="$VALID_RESP" \
  run_par bash "$FX/flow/core/par.sh" "$FA" --check --export "$EXP_SHA" >"$W/exp_checksum_retry.err" 2>&1 || rc=$?
eq "the export can be retried after checksum failure" 0 "$rc"

# A destination that appears mid-run -- after the early refusal, before the
# rename -- fails the export, removes the staging directory and leaves the
# squatter untouched.
EXP4="$W/exp-raced"
rc=0
STUB_GDS_CONTENT="router-gds-v4" STUB_RESPONSE_JSON="$VALID_RESP" STUB_MKDIR_AT="$EXP4" \
  run_par bash "$FX/flow/core/par.sh" "$FA" --check --export "$EXP4" >"$W/exp_raced.err" 2>&1 || rc=$?
eq "--check --export exits 1 when the destination appears mid-run" 1 "$rc"
if grep -q "the destination exists" "$W/exp_raced.err"; then
  ok "mid-run destination failure names the destination"
else
  no "mid-run destination failure names the destination"
fi
if compgen -G "$EXP4.export.*" >/dev/null; then
  no "a failed export leaves no staging directory behind"
else
  ok "a failed export leaves no staging directory behind"
fi
if [[ -d "$EXP4" && -z "$(ls -A "$EXP4")" ]]; then
  ok "the mid-run squatter on the destination is left untouched"
else
  no "the mid-run squatter on the destination is left untouched"
fi

# Both runs reach the final publish command with a complete stage. Hold
# that command at a barrier so a check followed by a plain mv reliably races.
RACE="$W/race"; RACE_DEST="$W/exp-concurrent"; mkdir -p "$RACE/bin"
cat >"$RACE/barrier" <<'STUB'
#!/usr/bin/env bash
if [[ ${*: -1} == "$STUB_RACE_DEST" ]]; then
  touch "$STUB_RACE_DIR/ready-$PUBLISHER"
  # Let one rename first, after both processes have passed any pre-check.
  until [[ -f "$STUB_RACE_DIR/ready-one" && -f "$STUB_RACE_DIR/ready-two" ]] \
     && [[ $PUBLISHER == one || -d "$STUB_RACE_DEST" ]]; do
    (( SECONDS < 15 )) || exit 1
    sleep 0.05
  done
fi
exec "$0.real" "$@"
STUB
chmod +x "$RACE/barrier"
for tool in mv python3; do
  ln -s "$RACE/barrier" "$RACE/bin/$tool"
  ln -s "$(command -v "$tool")" "$RACE/bin/$tool.real"
done
pids=()
for publisher in one two; do
  PATH="$RACE/bin:$PATH" STUB_RACE_DIR="$RACE" STUB_RACE_DEST="$RACE_DEST" PUBLISHER="$publisher" \
    STUB_GDS_CONTENT="router-gds-v4" STUB_RESPONSE_JSON="$VALID_RESP" STUB_ODB_CONTENT="$publisher" \
    run_par bash "$FX/flow/core/par.sh" "$FA" --check --export "$RACE_DEST" >"$RACE/$publisher.log" 2>&1 &
  pids+=("$!")
done
one=0; two=0
wait "${pids[0]}" || one=$?
wait "${pids[1]}" || two=$?
if [[ -f "$RACE/ready-one" && -f "$RACE/ready-two" ]]; then
  ok "both contenders reached publication"
else
  no "both contenders reached publication"
fi
case "$one $two" in
  "0 1") winner=one ;;
  "1 0") winner=two ;;
  *) winner=none ;;
esac
if [[ $winner != none ]] && [[ "$(cat "$RACE_DEST/cve2_rv32imc_wrapper.odb")" == "$winner" ]]; then
  ok "exactly one publisher succeeds and its ODB is at the destination root"
else
  no "expected one winning publisher, got exit statuses $one and $two"
fi
if cmp -s "$RACE_DEST/cve2_rv32imc_wrapper.def" "$W/exp.def.want" \
   && cmp -s "$RACE_DEST/cve2_rv32imc_wrapper.v" "$W/exp.v.want" && bundle_consistent "$RACE_DEST"; then
  ok "concurrent publication leaves one complete bundle with no nested stage"
else
  no "concurrent publication leaves one complete bundle with no nested stage"
fi

# Retry: the failed attempt left the destination free, so the retry at the
# same path publishes the bundle.
EXP5="$W/exp-retry"
rc=0
STUB_GDS_CONTENT="router-gds-mismatch" STUB_RESPONSE_JSON="$VALID_RESP" \
  run_par bash "$FX/flow/core/par.sh" "$FA" --check --export "$EXP5" >"$W/exp_retryfail.err" 2>&1 || rc=$?
eq "a failed export attempt exits 1" 1 "$rc"
[[ ! -e "$EXP5" ]] && ok "the failed attempt leaves the destination free" || no "the failed attempt leaves the destination free"
rc=0
STUB_GDS_CONTENT="router-gds-v4" STUB_RESPONSE_JSON="$VALID_RESP" \
  run_par bash "$FX/flow/core/par.sh" "$FA" --check --export "$EXP5" >"$W/exp_retryok.err" 2>&1 || rc=$?
eq "retrying the export at the same destination exits 0" 0 "$rc"
if cmp -s "$EXP5/cve2_rv32imc_wrapper.v" "$W/exp.v.want"; then
  ok "the retried export carries the routed Verilog bytes"
else
  no "the retried export carries the routed Verilog bytes"
fi
if bundle_consistent "$EXP5"; then
  ok "the retried export publishes a manifest-consistent bundle"
else
  no "the retried export publishes a manifest-consistent bundle"
fi

# Keep a sibling at the old PID-derived staging path. exec preserves the
# shell PID, so this also exercises a collision with the old staging scheme.
rc=0
STUB_GDS_CONTENT="router-gds-v4" STUB_RESPONSE_JSON="$VALID_RESP" \
  run_par bash -c '
    mkdir "$3.export.$$" && echo owner >"$3.export.$$/keep" || exit 1
    echo "$3.export.$$" >"$4"
    exec bash "$1" "$2" --check --export "$3/"
  ' _ "$FX/flow/core/par.sh" "$FA" "$W/exp-slash" "$W/foreign-stage" >"$W/exp_slash.err" 2>&1 || rc=$?
eq "--export normalises a trailing slash on the destination (exit 0)" 0 "$rc"
foreign_stage="$(cat "$W/foreign-stage")"
eq "an existing PID-named sibling keeps its contents" owner "$(cat "$foreign_stage/keep" 2>/dev/null)"
if [[ -d "$foreign_stage" ]]; then rm "$foreign_stage/keep" && rmdir "$foreign_stage"; fi
if [[ -f "$W/exp-slash/manifest.json" ]]; then
  ok "the trailing-slash destination receives the bundle"
else
  no "the trailing-slash destination receives the bundle"
fi

# Two commits share the netlist and its pin but have different GDS bytes.
# Advance the checkout after the first revision or GDS blob read. This also
# catches a driver that captures input_rev early but still reads GDS at HEAD.
printf '%s' 'router-gds-v5' >"$FX/layout/cve2_top.gds"
git -C "$FX" -c user.email=t@t -c user.name=t commit -q -m "advance fixture layout" -- layout/cve2_top.gds
NEXT_REV="$(git -C "$FX" rev-parse HEAD)"
git -C "$FX" checkout -q --detach "$FX_HEAD"
cat >"$BIN/git" <<'STUB'
#!/usr/bin/env bash
set -eu
"$REAL_GIT" "$@"
if [[ ${2:-} == "$STUB_REPO" && ! -e "$0.moved" ]]; then
  case "${3:-}:${4:-}:${5:-}" in
    rev-parse:*|cat-file:blob:*:layout/cve2_top.gds)
      "$REAL_GIT" -C "$STUB_REPO" checkout -q --detach "$STUB_NEXT_REV"
      touch "$0.moved" ;;
  esac
fi
STUB
chmod +x "$BIN/git"
EXP_MOVED="$W/exp-head-moved"
rc=0
REAL_GIT="$(command -v git)" STUB_REPO="$FX" STUB_NEXT_REV="$NEXT_REV" \
  STUB_GDS_CONTENT="router-gds-v4" STUB_RESPONSE_JSON="$VALID_RESP" \
  run_par bash "$FX/flow/core/par.sh" "$FA" --check --export "$EXP_MOVED" >"$W/exp_head_moved.err" 2>&1 || rc=$?
eq "fixture HEAD advanced during export" "$NEXT_REV" "$(git -C "$FX" rev-parse HEAD)"
eq "export succeeds with the original reference after HEAD advances" 0 "$rc"
manifest_rev="$(mj "$EXP_MOVED" 'm["input_rev"]')"
eq "export records the commit that supplied the reference GDS" "$FX_HEAD" "$manifest_rev"
eq "export GDS digest matches the blob at the manifest's input_rev" \
  "$(git -C "$FX" show "$manifest_rev:layout/cve2_top.gds" | sha256sum | cut -d' ' -f1)" \
  "$(mj "$EXP_MOVED" 'm["gds"]["sha256"]')"

# No staging directory survives any export path in this section.
if compgen -G "$W/exp*.export.*" >/dev/null; then
  no "no export staging directories are left behind"
else
  ok "no export staging directories are left behind"
fi

echo "1..$((NPASS + NBAD)) pass=$NPASS fail=$NBAD"
[[ "$NBAD" -eq 0 ]]
