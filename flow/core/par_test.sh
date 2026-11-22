#!/usr/bin/env bash
# Self-test for flow/core/par.sh, the core place-and-route driver.
#
# Needs no PDK, no klt, no network and no netlist: it checks the driver's
# refusal contract (usage, non-checkout, a checkout at the wrong pin -- the
# gate that fires before anything is written) and the request template's
# invariants: the decision 0004 floorplan values, the grid settings
# inherited from the verified smoke run of PR #234 (floorplan.tracks offsets
# at the deck grid origin, the explicit on-grid PDN strap recipe with no
# power.preset -- klayout-tools #7001 -- and connects[].ongrid), the
# wrapper's clock port, and the fixed seed the reproducibility claim
# rests on.
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
grep -q "not a git checkout" "$W/notgit.err" \
  && ok "non-checkout refusal names the git check" \
  || no "non-checkout refusal names the git check"

git init -q "$W/wrongpin"
git -C "$W/wrongpin" -c user.email=t@t -c user.name=t commit -q --allow-empty -m x
out="$W/wrongpin.err"; rc=0
( env -u ASAP7_DIR bash "$PAR" "$W/wrongpin" ) >"$out" 2>&1 || rc=$?
eq "a checkout at the wrong pin refuses (exit 2)" 2 "$rc"
grep -q "spec/pdk-bringup.md pins" "$W/wrongpin.err" \
  && ok "wrong-pin refusal names the spec pin" \
  || no "wrong-pin refusal names the spec pin"

# ---- the request template's invariants --------------------------------------
# Extract the request heredoc (the one unquoted <<EOF block), render it with
# the values the script assigns, and load it as JSON.
req="$W/par.req.rendered.json"
sed -n '/cat >"\$W\/par.req.json" <<EOF/,/^EOF$/p' "$PAR" | sed '1d;$d' \
  | sed -e 's/\${TOP}/cve2_rv32imc_wrapper/g' -e 's/\$TOP/cve2_rv32imc_wrapper/g' \
        -e 's/\${CELL_LIB}/asap7sc7p5t_28_R/g' -e 's/\$CELL_LIB/asap7sc7p5t_28_R/g' \
  >"$req"
python3 -I -c 'import json,sys; json.load(open(sys.argv[1]))' "$req" 2>/dev/null \
  && ok "request template renders to valid JSON" \
  || { no "request template renders to valid JSON"; echo "1..$((NPASS + NBAD)) pass=$NPASS fail=$NBAD"; exit 1; }

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

echo "1..$((NPASS + NBAD)) pass=$NPASS fail=$NBAD"
[[ "$NBAD" -eq 0 ]]
