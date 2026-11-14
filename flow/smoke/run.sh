#!/usr/bin/env bash
# ASAP7 smoke flow: runs the placeholder DUT (verification/smoke/counter.sv)
# through klt synthesize, place-and-route, drc, lvs, erc and sta, and writes
# one JSON record per step under flow/smoke/records/<date>/.
#
# ASAP7 is a predictive PDK; nothing here is fabricated or measured, and no
# number from the counter DUT is a design claim.
#
# usage: flow/smoke/run.sh <asap7-checkout>
#
# <asap7-checkout> is The-OpenROAD-Project/asap7 at the pins in
# spec/pdk-bringup.md section 1, with the asap7_pdk_r1p7 and asap7sc7p5t_28
# submodules initialised. The script refuses any other checkout.
#
# Environment:
#   RECORD_DATE      record directory name (default: today, UTC). The script
#                    refuses to write into a directory that already has records.
#   KLT_CMD          pinned klt (default: the pin read from spec/core.md, via uvx)
#   KLT_DECK_FILE    asap7.drc of the pinned build (default: looked up through
#                    the pinned build's own Python; required if KLT_CMD is set)
#   KEEP_SCRATCH=1   keep the scratch directory (extracted Liberty, run trees)
#
# Exit status: 0 when every step has a record (a step klt cannot perform gets
# status "not_run" and the klayout-tools issue for the gap); 2 for a refused
# invocation (bad checkout, existing records); 1 when a record is missing, the
# pinned deck hash does not match, or a record leaks a host path.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=flow/lib.sh
source "$REPO/flow/lib.sh"
DUT=counter
DUT_SRC="$REPO/verification/smoke/counter.sv"
STANDIN_CELL=INVx1_ASAP7_75t_R
# The library key klt resolves tie cells under (klayout-tools #4273); the cells are the RVT flavour.
CELL_LIB=asap7sc7p5t_28_R

[[ $# -eq 1 ]] || die "usage: flow/smoke/run.sh <asap7-checkout>"
[[ -d "$1" ]] || die "not a directory: $1"
ASAP7="$(cd "$1" && pwd)"

# ---- pins, read from the spec -------------------------------------------
PIN_UPSTREAM="$(spec_sha 'Upstream repo')"
PIN_CELLS="$(spec_sha 'Cell library')"
PIN_PDK="$(spec_sha 'PDK (DRM')"
PIN_KLT="$(grep -o 'klayout-tools==[0-9][0-9.]*' "$REPO/spec/core.md" | head -1)"
PIN_DECK="$(grep -o 'sha256:[0-9a-f]\{64\}' "$REPO/spec/core.md" | head -1)"
PIN_LVS_DECK="$(grep -A1 'pinned LVS deck hash' "$REPO/spec/core.md" | grep -o 'sha256:[0-9a-f]\{64\}' | head -1)"
for v in PIN_UPSTREAM PIN_CELLS PIN_PDK PIN_KLT PIN_DECK PIN_LVS_DECK; do
  [[ -n "${!v}" ]] || die "could not read $v from spec/" 1
done

# ---- the checkout must be at the pins -----------------------------------
check_pin "$ASAP7" "$PIN_UPSTREAM" "upstream asap7"
check_pin "$ASAP7/asap7sc7p5t_28" "$PIN_CELLS" "submodule asap7sc7p5t_28"
check_pin "$ASAP7/asap7_pdk_r1p7" "$PIN_PDK" "submodule asap7_pdk_r1p7"

# ---- output directory (never overwrite) ---------------------------------
new_record_dir smoke

# ---- klt commands --------------------------------------------------------
read -r -a KLT <<<"${KLT_CMD:-uvx --from $PIN_KLT klt}"

setup_scratch smoke
W="$SCRATCH/work"; ROOT="$SCRATCH/pdk"; mkdir -p "$W" "$ROOT"
echo "run.sh: records -> flow/smoke/records/$DATE" >&2

# ---- helper: assemble a record ------------------------------------------
cat >"$SCRATCH/mkrecord.py" <<'PY'
import json, sys

dest, step, run_state, role, version, ref, note, issues, input_kind, rc_out = sys.argv[1:11]
extras = json.loads(sys.argv[11]) if len(sys.argv) > 11 else {}
subs = [tuple(p.split("=", 1)) for p in json.loads(open(extras.pop("_subs")).read())]


def scrub(o):
    if isinstance(o, str):
        for src, dst in subs:
            o = o.replace(src, dst)
        return o
    if isinstance(o, list):
        return [scrub(x) for x in o]
    if isinstance(o, dict):
        return {k: scrub(v) for k, v in o.items()}
    return o


report = {}
if rc_out != "-":
    report = json.load(open(rc_out))
rec = dict(report)
if run_state == "not_run":
    rec = {"status": "not_run"}
rec["smoke"] = {
    "step": step,
    "run_state": run_state,
    "klt_build": {"role": role, "version": version, "ref": ref},
    "input": input_kind,
    "note": note,
    "klayout_tools_issues": [i for i in issues.split(",") if i],
    **extras,
}
json.dump(scrub(rec), open(dest, "w"), indent=2, sort_keys=True)
open(dest, "a").write("\n")
PY
printf '%s' "[\"$SCRATCH=<scratch>\",\"$ASAP7=<asap7-checkout>\",\"$REPO=<repo>\",\"$HOME=<home>\"]" >"$SCRATCH/subs.json"

klt_version() { "$@" version 2>/dev/null | head -1; }
V_PIN="$("${KLT[@]}" version 2>&1 | head -1 || true)"

# A klt run "worked" when stdout is a JSON object without a top-level "error"
# (drc/lvs/erc/sta exit non-zero for violations or not_checked and still report).
usable() { python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if isinstance(d,dict) and "error" not in d else 1)' "$1" 2>/dev/null; }
errmsg() {  # first error message from stdout JSON, else stderr, else rc
  python3 -I - "$1" "$2" "$3" <<'PY'
import json, sys
out, err, rc = sys.argv[1:4]
try:
    d = json.load(open(out))
    print(d["error"]["message"] if "error" in d else f"no error field (exit {rc})")
except Exception:
    print((open(err).read().strip() or f"no output (exit {rc})")[:1500])
PY
}

# step <name> <input-label> <note-on-success> <issues-on-gap> <klt args...>
# Runs the pinned klt. Sets STEP_OK=1 when a report exists; a step the pinned build
# cannot perform gets a not_run record carrying that build's error in failed_attempts.
step() {
  local name="$1" input="$2" note="$3" issues="$4"; shift 4
  local out="$SCRATCH/$name.out" err="$SCRATCH/$name.err" rc=0 attempts="[]" extra
  STEP_OK=0
  ( cd "$W" && "${KLT[@]}" "$@" ) >"$out" 2>"$err" || rc=$?
  if usable "$out"; then
    STEP_OK=1
    extra="$(python3 -I -c 'import json,sys; print(json.dumps({"exit_code":int(sys.argv[1]),"_subs":sys.argv[2],**json.loads(sys.argv[3])}))' "$rc" "$SCRATCH/subs.json" "${STEP_EXTRA:-{\}}")"
    python3 -I "$SCRATCH/mkrecord.py" "$OUT/$name.json" "$name" ran pinned "$V_PIN" "$PIN_KLT" "$note" "${RAN_ISSUES:-}" "$input" "$out" "$extra"
    return
  fi
  local pin_err; pin_err="$(errmsg "$out" "$err" "$rc")"
  attempts="$(python3 -I -c 'import json,sys; print(json.dumps([{"build":"pinned","version":sys.argv[1],"error":sys.argv[2]}]))' "$V_PIN" "$pin_err")"
  not_run "$name" "$input" "$issues" "$attempts" "Step failed on the pinned build."
}

# not_run <name> <input> <issues> <attempts-json> <why>
not_run() {
  local extra
  extra="$(python3 -I -c 'import json,sys; print(json.dumps({"_subs":sys.argv[1],"failed_attempts":json.loads(sys.argv[2]),**json.loads(sys.argv[3])}))' "$SCRATCH/subs.json" "$4" "${STEP_EXTRA:-{\}}")"
  python3 -I "$SCRATCH/mkrecord.py" "$OUT/$1.json" "$1" not_run none "" "" "$5" "$3" "$2" - "$extra"
  STEP_OK=0
  if [[ -z "$3" ]]; then
    echo "run.sh: WARNING: $1 is not_run with no klayout-tools issue recorded: file one for this gap" >&2
  fi
  echo "run.sh: $1 not_run: $5" >&2
}

# ---- PDK overlay in scratch (the checkout is read only) ------------------
LIBDIR="$ASAP7/asap7sc7p5t_28/LIB/NLDM"
mkdir -p "$ROOT/libs/$CELL_LIB/lef" "$ROOT/libs/$CELL_LIB/techlef" "$ROOT/libs/$CELL_LIB/gds"
build_liberty_overlay "$ASAP7" "$ROOT" "$CELL_LIB" SS TT
LIBJSON="$SCRATCH/liberty.json"
python3 -I - "$ROOT/lib" "$LIBDIR" "$CELL_LIB" >"$LIBJSON" <<'PY2'
import glob, hashlib, json, os, sys
root, libdir, cell_lib = sys.argv[1:4]
sha = lambda p: "sha256:" + hashlib.sha256(open(p, "rb").read()).hexdigest()
out = {}
for c in ("SS", "TT"):
    files = sorted(glob.glob(f"{root}/7z/*_RVT_{c}_nldm_*.lib"))
    out[c] = {
        "source_files": [{"name": os.path.basename(f), "extracted_sha256": sha(f),
                          "archive_sha256": sha(f.replace(root + "/7z", libdir) + ".7z")} for f in files],
        "merged_sha256": sha(f"{root}/{cell_lib}_{c}.lib"),
    }
print(json.dumps(out, indent=1))
PY2
# Copied, not symlinked: OpenROAD rejects a symlinked LEF (ORD-0001). The tech LEF is
# used unmodified; klayout-tools #4088 (negative M2 OFFSET) is fixed in the pinned release.
cp "$ASAP7/asap7sc7p5t_28/LEF/asap7sc7p5t_28_R_1x_220121a.lef" "$ROOT/libs/$CELL_LIB/lef/$CELL_LIB.lef"
cp "$ASAP7/asap7sc7p5t_28/GDS/asap7sc7p5t_28_R_220121a.gds" "$ROOT/libs/$CELL_LIB/gds/$CELL_LIB.gds"
TECH_SRC="$ASAP7/asap7sc7p5t_28/techlef_misc/asap7_tech_1x_201209.lef"
cp "$TECH_SRC" "$ROOT/libs/$CELL_LIB/techlef/${CELL_LIB}__nom.tlef"
# KLayout LEF/DEF layer map for the DEF->GDS merge (klt looks for <assets.klayout>/tech/<variant>.map). Without
# one, routing shapes land on KLayout's sequential default layers and overwrite device layers. The map is the
# pinned PDK's own asap7_fromAPR.layermap, copied unmodified.
LAYERMAP_SRC="$ASAP7/asap7_pdk_r1p7/cdslib/asap7_TechLib_10/asap7_fromAPR.layermap"
mkdir -p "$ROOT/klayout/tech"
cp "$LAYERMAP_SRC" "$ROOT/klayout/tech/asap7.map"
python3 -I - "$ROOT/klt-pdk.json" <<'PY3'
import json, sys
d = json.load(open(sys.argv[1])); d["assets"]["klayout"] = "klayout"
json.dump(d, open(sys.argv[1], "w"), indent=1); open(sys.argv[1], "a").write("\n")
PY3
PDKARGS=(--pdk asap7 --pdk-root "$ROOT")

# ---- tool-versions.txt ----------------------------------------------------
{
  echo "# Tool and input versions for flow/smoke/run.sh (predictive PDK; nothing here is fabricated)"
  echo "klt_pinned:   $V_PIN  ($PIN_KLT)"
  echo "yosys:        $(yosys -V 2>&1 | head -1)"
  echo "openroad:     $(openroad -version 2>&1 | head -1)"
  echo "python:       $(python3 --version 2>&1)"
  echo "uv:           $(uvx --version 2>&1 | head -1)"
  echo "py7zr:        $(uvx --quiet --from py7zr python -I -c 'import py7zr; print(py7zr.__version__)')"
  echo "asap7:        $PIN_UPSTREAM"
  echo "asap7sc7p5t_28: $PIN_CELLS"
  echo "asap7_pdk_r1p7: $PIN_PDK"
  echo "pinned_drc_deck: $PIN_DECK"
  echo "tech_lef_source:  sha256:$(sha256sum "$TECH_SRC" | cut -d' ' -f1)"
  echo "layer_map:    sha256:$(sha256sum "$LAYERMAP_SRC" | cut -d' ' -f1)  (asap7_pdk_r1p7 cdslib/asap7_TechLib_10/asap7_fromAPR.layermap)"
  echo "cell_lef:     sha256:$(sha256sum "$ASAP7/asap7sc7p5t_28/LEF/asap7sc7p5t_28_R_1x_220121a.lef" | cut -d' ' -f1)"
  echo "cell_gds:     sha256:$(sha256sum "$ASAP7/asap7sc7p5t_28/GDS/asap7sc7p5t_28_R_220121a.gds" | cut -d' ' -f1)"
  echo "cell_cdl:     sha256:$(sha256sum "$ASAP7/asap7sc7p5t_28/CDL/LVS/asap7sc7p5t_28_R.cdl" | cut -d' ' -f1)"
  echo "counter.sv:   sha256:$(sha256sum "$DUT_SRC" | cut -d' ' -f1)"
} >"$OUT/tool-versions.txt"

cp "$DUT_SRC" "$W/$DUT.sv"
LIB_SUMMARY="$(python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1])); print(json.dumps({c:{"source_files":[f["name"] for f in v["source_files"]],"merged_sha256":v["merged_sha256"]} for c,v in d.items()}))' "$LIBJSON")"

# ---- 1. synth ---------------------------------------------------------------
cat >"$W/synth.req.json" <<EOF
{"schema":"klt.synthesize.request/1","engine":"yosys","sources":["$DUT.sv"],"hdl_toplevel":"$DUT",
 "pdk":{"cell_library":"$CELL_LIB","corner":"SS"},"constraints":{"clock_period_ns":1.0}}
EOF
STEP_EXTRA="{\"liberty\":$LIB_SUMMARY,\"predicted\":true}" \
step synth "counter.sv (placeholder DUT), RVT, SS Liberty; not a design claim" \
  "Synthesized against the merged RVT SS Liberty." "" \
  synthesize "$W/synth.req.json" "${PDKARGS[@]}" --format json
SYNTH_NETLIST=""
if [[ $STEP_OK == 1 ]]; then
  SYNTH_NETLIST="$(ls -t "$W"/.klt/synthesize/*/${DUT}_synth.v 2>/dev/null | head -1 || true)"
  [[ -n "$SYNTH_NETLIST" ]] && cp "$SYNTH_NETLIST" "$W/${DUT}_synth.v"
fi

# output_dbu_um 0.00025: the ASAP7 deck measures FinFET geometry at 0.25 nm; the merged GDS defaults to 1 nm and
# klt lvs refuses it (klayout-tools #4482 added the knob).
# ---- 2. par -----------------------------------------------------------------
# request.library values (klayout-tools #4086). Sources: cell names and pins from the pinned cell LEF;
# route layers M2-M7 and the signal wire RC from The-OpenROAD-Project/OpenROAD-flow-scripts
# 11aa833a11488c3a540a1d8eb4caa23fd22df703 flow/platforms/asap7/{config.mk,setRC.tcl} (the pinned ASAP7
# checkout carries no RC table). The RC is 0.0265684 kohm/um and 0.16579 fF/um in the Liberty units;
# klt emits the numbers unconverted under set_cmd_units -capacitance pF, so capacitance is given in
# pF/um (1.6579e-4) and resistance in the Liberty resistance unit (kohm), not ohm as the field is named.
# ASAP7 ships no antenna diode cell, hence null. The power grid is the ORFS M1/M2 followpin plus
# M5/M6 stripe scheme at a pitch that fits the counter's ~2.8 um core.
# floorplan.tracks (klayout-tools #4088): the tech LEF gives M2 OFFSET -0.27, which OpenROAD's
# automatic make_tracks rejects. Each entry is the LEF pitch and the LEF OFFSET reduced modulo that
# pitch to be >= 0 (M2: x -0.27 mod 0.045 = 0.0, y -0.27 mod 0.036 = 0.018); the track grid is the same.
PAR_ISSUES="4086,4087,4088"
if [[ -n "$SYNTH_NETLIST" ]]; then
  cat >"$W/par.req.json" <<EOF
{"schema":"klt.place_and_route.request/1","engine":"openroad","netlist":"${DUT}_synth.v","hdl_toplevel":"$DUT",
 "pdk":{"cell_library":"$CELL_LIB","corner":"SS"},
 "floorplan":{"method":"utilization","utilization_pct":60,"aspect_ratio":1.0,"core_margin_um":1.0,"site":"asap7sc7p5t",
   "tracks":[
   {"layer":"M1","x_offset_um":0.0,"x_pitch_um":0.036,"y_offset_um":0.0,"y_pitch_um":0.036},
   {"layer":"M2","x_offset_um":0.0,"x_pitch_um":0.045,"y_offset_um":0.018,"y_pitch_um":0.036},
   {"layer":"M3","x_offset_um":0.0,"x_pitch_um":0.036,"y_offset_um":0.0,"y_pitch_um":0.036},
   {"layer":"M4","x_offset_um":0.003,"x_pitch_um":0.048,"y_offset_um":0.003,"y_pitch_um":0.048},
   {"layer":"M5","x_offset_um":0.0,"x_pitch_um":0.048,"y_offset_um":0.0,"y_pitch_um":0.048},
   {"layer":"M6","x_offset_um":0.0,"x_pitch_um":0.064,"y_offset_um":0.0,"y_pitch_um":0.064},
   {"layer":"M7","x_offset_um":0.0,"x_pitch_um":0.064,"y_offset_um":0.0,"y_pitch_um":0.064}]},
 "library":{"cts_buffer":"BUFx4_ASAP7_75t_R",
   "power_pins":[{"net_role":"power","pattern":"VDD","primary":true},{"net_role":"ground","pattern":"VSS","primary":true}],
   "wire_rc":{"resistance_ohm_per_um":2.65684E-02,"capacitance_pf_per_um":1.65790E-04},
   "route_layers":{"low":"M2","high":"M7"},
   "antenna_diode":null,
   "tapcell":{"master":"TAPCELL_ASAP7_75t_R","endcap":"TAPCELL_ASAP7_75t_R","distance_um":25},
   "filler":["FILLERxp5_ASAP7_75t_R","FILLER_ASAP7_75t_R"]},
 "io":{"layer_h":"M4","layer_v":"M5"},
 "power":{"power_net":"VDD","ground_net":"VSS","straps":[
   {"layer":"M1","width_um":0.018,"pitch_um":0.54,"followpins":true},
   {"layer":"M2","width_um":0.018,"pitch_um":0.54,"followpins":true},
   {"layer":"M5","width_um":0.12,"pitch_um":1.08,"offset_um":0.3},
   {"layer":"M6","width_um":0.288,"pitch_um":1.08,"offset_um":0.513}]},
 "constraints":{"clock_port":"clk","clock_period_ns":1.0},
 "output_dbu_um":0.00025,
 "seed":1,"target_stage":"route"}
EOF
  STEP_EXTRA="{}" step par "$DUT synthesized netlist; target_stage route with a power grid" \
    "" "$PAR_ISSUES" place-and-route "$W/par.req.json" "${PDKARGS[@]}" --format json
else
  STEP_EXTRA="{}" not_run par "$DUT synthesized netlist" "" "[]" "no synthesized netlist: the synth step did not produce one"
fi

# ---- layout for drc / lvs / erc ------------------------------------------------
# When place-and-route ran, drc, lvs and erc run on the counter's own routed GDS, and the DEF, GDS and
# as-built netlist are kept next to the records. When it did not, they fall back to one library cell
# (a stand-in that checks the tool chain and the deck and says nothing about the counter).
LAYOUT_OK=0; PAR_RAN=0
if python3 -I -c 'import json,sys; sys.exit(0 if json.load(open(sys.argv[1]))["smoke"]["run_state"]=="ran" else 1)' "$OUT/par.json" 2>/dev/null; then
  PR="$W/.klt/place-and-route"
  if [[ -s "$PR/$DUT.gds" && -s "$PR/$DUT.def" && -s "$PR/$DUT.v" ]]; then
    mkdir -p "$OUT/layout"
    cp "$PR/$DUT.gds" "$PR/$DUT.def" "$OUT/layout/"
    cp "$PR/$DUT.v" "$OUT/layout/${DUT}_asbuilt.v"
    PAR_RAN=1; LAYOUT_OK=1; LAYOUT="$OUT/layout/$DUT.gds"
    LAYOUT_LABEL="$DUT routed layout (layout/$DUT.gds from the par step of this run)"
    LVS_TOP="$DUT"
    LVS_REF="{\"netlist\":\"$OUT/layout/${DUT}_asbuilt.v\",\"form\":\"gate-level-verilog\",\"top\":\"$DUT\",\"pin_order_files\":[\"$ASAP7/asap7sc7p5t_28/CDL/LVS/asap7sc7p5t_28_R.cdl\"]}"
    LVS_INPUT_NOTE="$LAYOUT_LABEL, against the as-built gate-level netlist written by place-and-route (cells expanded to the pinned cell CDL)"
  fi
fi
if [[ $PAR_RAN == 0 ]]; then
  LAYOUT="$W/standin.gds"
  CELL_GDS="$ASAP7/asap7sc7p5t_28/GDS/asap7sc7p5t_28_R_220121a.gds"
  if ( cd "$W" && "${KLT[@]}" clip --cell "$STANDIN_CELL" -o "$LAYOUT" --format json "$CELL_GDS" ) >/dev/null 2>"$SCRATCH/clip.err"; then
    LAYOUT_OK=1
  fi
  LAYOUT_LABEL="library cell $STANDIN_CELL clipped from the pinned cell GDS (stand-in: the counter has no layout because place-and-route is not_run)"
  LVS_TOP="$STANDIN_CELL"
  LVS_REF="{\"netlist\":\"$ASAP7/asap7sc7p5t_28/CDL/LVS/asap7sc7p5t_28_R.cdl\",\"top\":\"$STANDIN_CELL\"}"
  LVS_INPUT_NOTE="$LAYOUT_LABEL, against its subckt in the pinned cell CDL"
fi
standin_missing() { STEP_EXTRA="{}" not_run "$1" "$LAYOUT_LABEL" "" "[]" "layout could not be produced: $(head -c 400 "$SCRATCH/clip.err" 2>/dev/null)"; }

# ---- 3. drc ------------------------------------------------------------------
DECK_FILE="${KLT_DECK_FILE:-}"
if [[ -z "$DECK_FILE" && -z "${KLT_CMD:-}" ]]; then
  DECK_FILE="$(uvx --quiet --from "$PIN_KLT" python -I -c 'from klayout_tools.decks import asap7_rules as r; print(r.DECK_PATH)')"
fi
[[ -f "$DECK_FILE" ]] || die "cannot locate the pinned asap7.drc: set KLT_DECK_FILE" 1
mkdir -p "$SCRATCH/deck"; cp "$DECK_FILE" "$SCRATCH/deck/asap7.drc"
if [[ $LAYOUT_OK == 1 ]]; then
  STEP_EXTRA='{"unchecked":"Rules needing track/net/corner/grid predicates, FEOL/MOL increments and PAD are not checked (spec/pdk-bringup.md section 3; spec/core.md DRC acceptance)."}' \
  step drc "$LAYOUT_LABEL" \
    "Pinned klt, --engine klayout with the packaged ASAP7 deck, --expect-rule-categories 267." "" \
    drc --engine klayout --deck-file "$SCRATCH/deck/asap7.drc" --expect-rule-categories 267 --format json "$LAYOUT"
else standin_missing drc; fi

# ---- 4. lvs ------------------------------------------------------------------
if [[ $LAYOUT_OK == 1 ]]; then
  cat >"$W/lvs.req.json" <<EOF
{"schema":"klt.lvs.request/1","engine":"klayout",
 "layout":{"file":"$LAYOUT","deck":"asap7","top":"$LVS_TOP"},
 "reference":$LVS_REF,
 "options":{"finfet_bulk":{"nmos":"VSS","pmos":"VDD"}}}
EOF
  STEP_EXTRA='{"bulk_policy":"options.finfet_bulk nmos=VSS pmos=VDD (decision 0005); disclosed by the tool as device.finfet_bulk_tied"}' \
  step lvs "$LVS_INPUT_NOTE" \
    "Pinned klt; layout, reference and deck hashes are in environment and provenance." "" \
    lvs "$W/lvs.req.json" --format json
else standin_missing lvs; fi

# ---- 5. erc ------------------------------------------------------------------
if [[ $LAYOUT_OK == 1 ]]; then
  cat >"$W/erc.spec.json" <<'EOF'
{"stackup":[
 {"name":"gate","layer":"7/0","role":"gate","active_layer":"11/0"},
 {"name":"lig","layer":"16/0"},
 {"name":"m1","layer":"19/0"},
 {"name":"m2","layer":"20/0"}],
 "vias":[
 {"name":"gate_lig","layer":"16/0","between":["gate","lig"]},
 {"name":"v0","layer":"18/0","between":["lig","m1"]},
 {"name":"v1","layer":"21/0","between":["m1","m2"]}]}
EOF
  RAN_ISSUES=4090 STEP_EXTRA='{"antenna":"No ASAP7 antenna-ratio table exists (klayout-tools #4090): every antenna level is skipped and the verdict is not_checked, never clean."}' \
  step erc "$LAYOUT_LABEL" \
    "Pinned klt, --deck asap7, stackup spec generated by run.sh (gate 7/0 with active 11/0, LIG 16/0, M1 19/0, M2 20/0, V0 18/0, V1 21/0)." "4090" \
    erc --deck asap7 --format json "$LAYOUT" "$W/erc.spec.json"
else standin_missing erc; fi

# ---- 6. sta ------------------------------------------------------------------
if [[ -n "$SYNTH_NETLIST" ]]; then
  cat >"$W/sta.req.json" <<EOF
{"schema":"klt.sta.request/1","verilog":"${DUT}_synth.v","hdl_toplevel":"$DUT",
 "pdk":{"cell_library":"$CELL_LIB","corners":["SS","TT"]},
 "constraints":{"clock_port":"clk","clock_period_ns":1.0,"input_delay_ns":0,"output_delay_ns":0}}
EOF
  RAN_ISSUES=4089 STEP_EXTRA="{\"predicted\":true,\"corners\":{\"SS\":\"setup corner, 0.63 V / 100 C\",\"TT\":\"reference, 0.7 V / 25 C\"},\"liberty\":$LIB_SUMMARY,\"geometry\":\"netlist_estimate: the synthesized netlist with an ideal clock and no placement, routing or wire load. This is NOT a post-route figure.\",\"unit_caveat\":\"Liberty time_unit is 1ps: the aggregate worst_slack_ns, worst_hold_slack_ns and fmax_mhz fields are 1000x off from worst_setup_path.slack_ns (klayout-tools #4089). Read the worst-path slack. FF is not run (decision 0002).\"}" \
  step sta "$DUT synthesized netlist, RVT, SS and TT; predicted, not a design claim" \
    "Two corners from one request; the file lists name every Liberty source." "4089" \
    sta "$W/sta.req.json" "${PDKARGS[@]}" --format json
else
  STEP_EXTRA="{}" not_run sta "$DUT synthesized netlist" "" "[]" "no synthesized netlist: the synth step did not produce one"
fi

# ---- final checks ------------------------------------------------------------
for s in synth par drc lvs erc sta; do
  [[ -s "$OUT/$s.json" ]] || die "no record for step $s: a step must never disappear" 1
done
LINT_RC=0
"${KLT[@]}" env-provenance lint-envelope "$OUT"/*.json >"$SCRATCH/lint.txt" 2>&1 || LINT_RC=$?
if [[ $LINT_RC == 3 ]] || grep -lE '(/home/|/tmp/|/Users/|/root/)' "$OUT"/*.json "$OUT"/tool-versions.txt >"$SCRATCH/leak.txt"; then
  cat "$SCRATCH/lint.txt" "$SCRATCH/leak.txt" >&2
  die "a record leaks an absolute host path" 1
elif [[ $LINT_RC != 0 ]]; then
  echo "run.sh: WARNING: klt env-provenance lint could not run (exit $LINT_RC); the grep check passed" >&2
fi
if [[ -f "$OUT/drc.json" ]] && python3 -I -c 'import json,sys; sys.exit(0 if json.load(open(sys.argv[1]))["smoke"]["run_state"]=="ran" else 1)' "$OUT/drc.json"; then
  GOT="$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["provenance"]["deck"]["content_hash"])' "$OUT/drc.json")"
  [[ "$GOT" == "$PIN_DECK" ]] || die "drc.json deck hash $GOT is not the pin $PIN_DECK" 1
fi
if [[ -f "$OUT/lvs.json" ]] && python3 -I -c 'import json,sys; sys.exit(0 if json.load(open(sys.argv[1]))["smoke"]["run_state"]=="ran" else 1)' "$OUT/lvs.json"; then
  GOT="$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["provenance"]["deck"]["content_hash"])' "$OUT/lvs.json")"
  [[ "$GOT" == "$PIN_LVS_DECK" ]] || die "lvs.json deck hash $GOT is not the pin $PIN_LVS_DECK" 1
fi
echo "run.sh: records written to flow/smoke/records/$DATE:" >&2
python3 -I - "$OUT" <<'PY' >&2
import glob, json, os, sys
for p in sorted(glob.glob(sys.argv[1] + "/*.json")):
    d = json.load(open(p)); s = d["smoke"]
    print(f"  {os.path.basename(p):10} {d.get('status', '?'):12} {s['run_state']:8} build={s['klt_build']['role']:7} issues={s['klayout_tools_issues']}")
PY
