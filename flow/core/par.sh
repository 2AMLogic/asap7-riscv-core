#!/usr/bin/env bash
# Core place-and-route flow (T1 item 2): runs `klt place-and-route` of the
# committed gate-level netlist (the newest flow/core/records/<date>/netlist.v)
# with the decision 0004 floorplan (60 % utilisation, aspect 1.0, single
# block, no macro) and the pinned PDK inputs, and writes the routed GDS to
# layout/cve2_top.gds plus a par record under flow/core/records/<date>/, or,
# with --check, regenerates the GDS, validates the response, and byte-compares
# it with the committed HEAD:layout/cve2_top.gds.
#
# ASAP7 is a predictive PDK; nothing here is fabricated or measured. The
# flow claims no timing: the clock constraint is passed to the tool and any
# timing figure in the response is a predicted tool result, never a design
# claim (STA is issue #34's own flow).
#
# The request inherits the smoke flow's verified grid settings (PR #234's
# flow/smoke/records/2026-11-21): floorplan.tracks offsets at the deck grid
# origin (M4/M5 0.012, M6/M7 0.016; klayout-tools #4493) and the explicit
# on-grid PDN strap recipe instead of power.preset (the pinned klt's
# asap7sc7p5t preset is keyed to the unflavoured asap7sc7p5t_28 library and
# rejects this flow's RVT overlay key asap7sc7p5t_28_R, klayout-tools
# #7001): M5 0.216 um wide so the tech LEF's wide-V4 bar
# (VIARULE M5_M4widePWR0p864) applies, pitches that are multiples of the
# layer pitch (0.048 M5 / 0.064 M6), strap centres on the deck's edge grid
# (12 nm mod 24 for M5, 16 nm mod 32 for M6, measured against the core
# origin) and connects[].ongrid snapping the M3/M4 via stubs onto the
# tracks.
#
# usage: flow/core/par.sh <asap7-checkout> --check    regenerate and compare
#        flow/core/par.sh <asap7-checkout>            write a new dated record
#        (the checkout may be given as $ASAP7_DIR instead of an argument)
#
# <asap7-checkout> is The-OpenROAD-Project/asap7 at the pins in
# spec/pdk-bringup.md section 1, with the asap7_pdk_r1p7 and asap7sc7p5t_28
# submodules initialised. The script refuses any other checkout.
#
# Prerequisites on $PATH: `openroad` (required by `klt place-and-route`; build
# `26Q3-1510-g6cb3f2b704` produced the committed layout, recorded in
# flow/core/records/2026-11-22/tool-versions.txt), `uvx` and `python3`;
# writing a new record also queries `yosys -V` for tool-versions.txt.
#
# Environment:
#   RECORD_DATE     record directory name (default: today, UTC). The script
#                  refuses to write into a directory that already has records.
#   KLT_CMD         klt to run (default: the release pinned in spec/core.md,
#                  via uvx)
#   KEEP_SCRATCH=1  keep the scratch directory
#
# Exit status: 0 ok (and, with --check, byte-identical to
# HEAD:layout/cve2_top.gds); 1 a step failed, the response failed validation,
# a staged record leaked a host path, or --check found a difference; 2 refused
# invocation -- including --check finding no committed HEAD:layout/cve2_top.gds
# to compare against at all (a refusal, not a difference).
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=flow/lib.sh
source "$REPO/flow/lib.sh"
TOP=cve2_rv32imc_wrapper
CELL_LIB=asap7sc7p5t_28_R
GDS_OUT="$REPO/layout/cve2_top.gds"

CHECK=0
ARGS=()
for a in "$@"; do
  case "$a" in
    --check) CHECK=1 ;;
    -*) die "unknown option: $a" ;;
    *) ARGS+=("$a") ;;
  esac
done
[[ ${#ARGS[@]} -le 1 ]] || die "usage: flow/core/par.sh [<asap7-checkout>] [--check]"
ASAP7_ARG="${ARGS[0]:-${ASAP7_DIR:-}}"
[[ -n "$ASAP7_ARG" ]] || die "usage: flow/core/par.sh <asap7-checkout> [--check] (or set ASAP7_DIR)"
[[ -d "$ASAP7_ARG" ]] || die "not a directory: $ASAP7_ARG"
ASAP7="$(cd "$ASAP7_ARG" && pwd)"

# ---- pins, read from the spec -------------------------------------------
# Label-anchored and fail-closed (flow/lib.sh); the same reads the smoke flow
# makes, so the two drivers cannot drift onto different pins. The PDK pin is
# read too: place-and-route consumes the layer map asap7_fromAPR.layermap
# from asap7_pdk_r1p7 for the DEF->GDS merge.
PIN_UPSTREAM="$(spec_sha 'Upstream repo')" || exit 1
PIN_CELLS="$(spec_sha 'Cell library')" || exit 1
PIN_PDK="$(spec_sha 'PDK (DRM')" || exit 1
PIN_KLT="$(spec_klt_pin)" || exit 1

check_pin "$ASAP7" "$PIN_UPSTREAM" "upstream asap7"
check_pin "$ASAP7/asap7sc7p5t_28" "$PIN_CELLS" "submodule asap7sc7p5t_28"
check_pin "$ASAP7/asap7_pdk_r1p7" "$PIN_PDK" "submodule asap7_pdk_r1p7"

klt_cmd "$PIN_KLT"
setup_scratch corepar

# ---- mode gate: immutable --check baseline or append-only precheck ----------
# Pin RECORD_DATE once so a run crossing UTC midnight checks and writes the
# same directory, and defer creating $OUT until the staged record passes every
# check so a rejected run leaves neither a partial record dir nor a replaced
# layout behind. In --check mode, snapshot the immutable GDS blob at HEAD now
# so working-tree edits (including a preceding non-check run) cannot self-compare.
RECORD_DATE="${RECORD_DATE:-$(date -u +%Y-%m-%d)}"
DATE="$RECORD_DATE"
OUT="$REPO/flow/core/records/$DATE"
if [[ $CHECK == 1 ]]; then
  git -C "$REPO" cat-file -e HEAD:layout/cve2_top.gds 2>/dev/null \
    || die "no committed HEAD:layout/cve2_top.gds to compare against" 2
  COMMITTED_GDS="$SCRATCH/committed.gds"
  git -C "$REPO" cat-file blob HEAD:layout/cve2_top.gds >"$COMMITTED_GDS"
  [[ -s "$COMMITTED_GDS" ]] \
    || die "committed HEAD:layout/cve2_top.gds is empty" 2
else
  if compgen -G "$OUT/*.json" >/dev/null; then
    die "records already exist in flow/core/records/$DATE; set RECORD_DATE to a new label (records are append-only evidence)"
  fi
fi

# ---- input: the committed gate-level netlist -----------------------------
NETREC="$(newest_record_with "$REPO/flow/core/records" netlist.v)" \
  || die "no committed netlist to place: nothing under flow/core/records/ holds a netlist.v"
NETLIST_SRC="${NETREC}netlist.v"
W="$SCRATCH/work"; mkdir -p "$W"
cp "$NETLIST_SRC" "$W/${TOP}_synth.v"

# ---- PDK overlay in scratch (the checkout is read only) ------------------
# The same overlay the smoke flow builds (flow/smoke/run.sh): merged RVT SS
# Liberty, the cell LEF/GDS and tech LEF copied unmodified (OpenROAD rejects
# a symlinked LEF, ORD-0001), and the pinned PDK's own asap7_fromAPR.layermap
# as the KLayout layer map for the DEF->GDS merge.
ROOT="$SCRATCH/pdk"; mkdir -p "$ROOT"
build_liberty_overlay "$ASAP7" "$ROOT" "$CELL_LIB" SS
mkdir -p "$ROOT/libs/$CELL_LIB/lef" "$ROOT/libs/$CELL_LIB/techlef" "$ROOT/libs/$CELL_LIB/gds"
cp "$ASAP7/asap7sc7p5t_28/LEF/asap7sc7p5t_28_R_1x_220121a.lef" "$ROOT/libs/$CELL_LIB/lef/$CELL_LIB.lef"
cp "$ASAP7/asap7sc7p5t_28/GDS/asap7sc7p5t_28_R_220121a.gds" "$ROOT/libs/$CELL_LIB/gds/$CELL_LIB.gds"
TECH_SRC="$ASAP7/asap7sc7p5t_28/techlef_misc/asap7_tech_1x_201209.lef"
cp "$TECH_SRC" "$ROOT/libs/$CELL_LIB/techlef/${CELL_LIB}__nom.tlef"
LAYERMAP_SRC="$ASAP7/asap7_pdk_r1p7/cdslib/asap7_TechLib_10/asap7_fromAPR.layermap"
mkdir -p "$ROOT/klayout/tech"
cp "$LAYERMAP_SRC" "$ROOT/klayout/tech/asap7.map"
python3 -I - "$ROOT/klt-pdk.json" <<'PY3'
import json, sys
d = json.load(open(sys.argv[1])); d["assets"]["klayout"] = "klayout"
json.dump(d, open(sys.argv[1], "w"), indent=1); open(sys.argv[1], "a").write("\n")
PY3
PDKARGS=(--pdk asap7 --pdk-root "$ROOT")

# ---- the request ----------------------------------------------------------
# request.library values (klayout-tools #4086), as in the smoke flow: cell
# names and pins from the pinned cell LEF, route layers M2-M7 and the signal
# wire RC from The-OpenROAD-Project/OpenROAD-flow-scripts
# 11aa833a11488c3a540a1d8eb4caa23fd22df703 flow/platforms/asap7/{config.mk,
# setRC.tcl}. ASAP7 ships no antenna diode cell, hence null. seed is fixed:
# the flow's reproducibility claim (byte-identical GDS on re-run, verified by
# --check) rests on it. The clock port is the wrapper's clk_i.
cat >"$W/par.req.json" <<EOF
{"schema":"klt.place_and_route.request/1","engine":"openroad","netlist":"${TOP}_synth.v","hdl_toplevel":"$TOP",
 "pdk":{"cell_library":"$CELL_LIB","corner":"SS"},
 "floorplan":{"method":"utilization","utilization_pct":60,"aspect_ratio":1.0,"core_margin_um":1.0,"site":"asap7sc7p5t",
   "tracks":[
   {"layer":"M1","x_offset_um":0.0,"x_pitch_um":0.036,"y_offset_um":0.0,"y_pitch_um":0.036},
   {"layer":"M2","x_offset_um":0.0,"x_pitch_um":0.045,"y_offset_um":0.018,"y_pitch_um":0.036},
   {"layer":"M3","x_offset_um":0.0,"x_pitch_um":0.036,"y_offset_um":0.0,"y_pitch_um":0.036},
   {"layer":"M4","x_offset_um":0.012,"x_pitch_um":0.048,"y_offset_um":0.012,"y_pitch_um":0.048},
   {"layer":"M5","x_offset_um":0.012,"x_pitch_um":0.048,"y_offset_um":0.012,"y_pitch_um":0.048},
   {"layer":"M6","x_offset_um":0.016,"x_pitch_um":0.064,"y_offset_um":0.016,"y_pitch_um":0.064},
   {"layer":"M7","x_offset_um":0.016,"x_pitch_um":0.064,"y_offset_um":0.016,"y_pitch_um":0.064}]},
 "library":{"cts_buffer":"BUFx4_ASAP7_75t_R",
   "power_pins":[{"net_role":"power","pattern":"VDD","primary":true},{"net_role":"ground","pattern":"VSS","primary":true}],
   "wire_rc":{"resistance_ohm_per_um":2.65684E-02,"capacitance_pf_per_um":1.65790E-04},
   "route_layers":{"low":"M2","high":"M7"},
   "antenna_diode":null,
   "tapcell":{"master":"TAPCELL_ASAP7_75t_R","endcap":"TAPCELL_ASAP7_75t_R","distance_um":25},
   "filler":["FILLERxp5_ASAP7_75t_R","FILLER_ASAP7_75t_R"]},
 "io":{"layer_h":"M4","layer_v":"M5"},
 "power":{"power_net":"VDD","ground_net":"VSS",
   "straps":[
   {"layer":"M1","width_um":0.018,"pitch_um":0.54,"followpins":true},
   {"layer":"M2","width_um":0.018,"pitch_um":0.54,"followpins":true},
   {"layer":"M5","width_um":0.216,"pitch_um":1.152,"offset_um":0.474},
   {"layer":"M6","width_um":0.288,"pitch_um":1.152,"offset_um":0.152}],
   "connects":[
   {"layers":["M2","M5"],"max_columns":1,"ongrid":["M3","M4"]},
   {"layers":["M5","M6"],"max_columns":1}]},
 "constraints":{"clock_port":"clk_i","clock_period_ns":1.0},
 "output_dbu_um":0.00025,
 "seed":1,"target_stage":"route"}
EOF

# ---- run the pinned klt ----------------------------------------------------
# output_dbu_um 0.00025: the ASAP7 deck measures FinFET geometry at 0.25 nm;
# the merged GDS defaults to 1 nm and klt lvs would refuse it
# (klayout-tools #4482 added the knob).
echo "par.sh: placing and routing ${TOP} from ${NETLIST_SRC#"$REPO"/}" >&2
rc=0
( cd "$W" && "${KLT[@]}" place-and-route par.req.json "${PDKARGS[@]}" --format json ) \
  >"$SCRATCH/par.out" 2>"$SCRATCH/par.err" || rc=$?
if [[ $rc -ne 0 ]] || ! python3 -I "$REPO/flow/record_lib.py" usable "$SCRATCH/par.out"; then
  echo "par.sh: klt place-and-route failed (exit $rc)" >&2
  head -c 2000 "$SCRATCH/par.out" "$SCRATCH/par.err" >&2
  exit 1
fi

# ---- outputs & response validation (both modes) -----------------------------
PR="$W/.klt/place-and-route"
for f in "$TOP.gds" "$TOP.def" "$TOP.v"; do
  [[ -s "$PR/$f" ]] || die "klt place-and-route produced no $f in its run tree" 1
done

# Validate the response before --check compares or record mode publishes:
# the run must report status "ok" at stage "route", and the item 2 acceptance
# edge cases require an actual power grid (power.pdn true) and a named
# tapcell master. A response failing any check is a failed run in both modes.
if ! RESP_ERR="$(python3 -I - "$SCRATCH/par.out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
if d.get("status", "ok") != "ok":
    print(f"status is {d.get('status')!r}, expected 'ok'")
    sys.exit(1)
if d.get("stage_reached", "route") != "route":
    print(f"stage_reached is {d.get('stage_reached')!r}, expected 'route'")
    sys.exit(1)
power = d.get("power")
if not isinstance(power, dict) or power.get("pdn") is not True:
    print("power.pdn is not true in the place-and-route response")
    sys.exit(1)
tap = power.get("tapcell_master")
if not isinstance(tap, str) or not tap.strip():
    print("no power.tapcell_master in the place-and-route response")
    sys.exit(1)
PY
)"; then
  die "$RESP_ERR" 1
fi

# ---- compare (--check) against HEAD:layout/cve2_top.gds ---------------------
if [[ $CHECK == 1 ]]; then
  if cmp -s "$PR/$TOP.gds" "$COMMITTED_GDS"; then
    echo "par.sh: regenerated GDS is byte-identical to HEAD:layout/cve2_top.gds" \
         "(sha256:$(sha "$COMMITTED_GDS"))" >&2
    exit 0
  fi
  echo "par.sh: regenerated GDS DIFFERS from HEAD:layout/cve2_top.gds" \
       "(got sha256:$(sha "$PR/$TOP.gds"), committed sha256:$(sha "$COMMITTED_GDS"))" >&2
  exit 1
fi

# ---- stage & validate record before publishing ------------------------------
# Assemble par.json and tool-versions.txt in scratch and run record_leak_guard
# before creating flow/core/records/$DATE or replacing layout/cve2_top.gds, so
# a redaction miss or tool error never leaves published outputs behind.
STAGE="$SCRATCH/record"; mkdir -p "$STAGE"
GDS_SHA="$(sha "$PR/$TOP.gds")"
record_subs "$SCRATCH/subs.json" "$SCRATCH=<scratch>" "$ASAP7=<asap7-checkout>" "$REPO=<repo>" "$HOME=<home>"
python3 -I - "$SCRATCH/par.out" "$GDS_SHA" "${NETLIST_SRC#"$REPO"/}" "$(sha "$NETLIST_SRC")" <<'PY' | python3 -I "$REPO/flow/record_lib.py" write "$STAGE/par.json" "$SCRATCH/subs.json"
import json, sys
src, gds_sha, netlist_path, netlist_sha = sys.argv[1:5]
d = json.load(open(src, encoding="utf-8"))
d["core_flow"] = {
    "note": "Place-and-route of the RV32IMC wrapper's gate-level netlist on ASAP7; "
            "predictive PDK, no timing claimed (STA is a separate flow). Floorplan "
            "per decision 0004 (60% utilisation, aspect 1.0, single block, no macro); "
            "grid settings inherited from the verified smoke run of PR #234.",
    "predicted": True,
    "input_netlist": {"path": netlist_path, "sha256": netlist_sha},
    "gds": {"path": "layout/cve2_top.gds", "sha256": gds_sha,
            "top_cell": "cve2_rv32imc_wrapper"},
}
print(json.dumps(d))
PY

# One `klt version` ask, the spelling the shared provenance rows record; klt
# has already run successfully by this point, so this only echoes a version.
KLT_V="$("${KLT[@]}" version 2>&1 | head -1 || true)"
# Shared head rows from flow/lib.sh (one provenance vocabulary, shared with
# flow/core/synth.sh), then this driver's own rows.
{
  provenance_rows flow/core/par.sh "$KLT_V"
  echo "openroad:     $(openroad -version 2>&1 | head -1)"
  echo "asap7_pdk_r1p7: $PIN_PDK"
  echo "tech_lef_source:  sha256:$(sha "$TECH_SRC")"
  echo "layer_map:    sha256:$(sha "$LAYERMAP_SRC")  (asap7_pdk_r1p7 cdslib/asap7_TechLib_10/asap7_fromAPR.layermap)"
  echo "cell_lef:     sha256:$(sha "$ASAP7/asap7sc7p5t_28/LEF/asap7sc7p5t_28_R_1x_220121a.lef")"
  echo "cell_gds:     sha256:$(sha "$ASAP7/asap7sc7p5t_28/GDS/asap7sc7p5t_28_R_220121a.gds")"
  echo "liberty_corner: RVT SS (merged)  sha256:$(sha "$ROOT/lib/${CELL_LIB}_SS.lib")"
  echo "input_netlist: ${NETLIST_SRC#"$REPO"/}  sha256:$(sha "$NETLIST_SRC")"
  echo "gds:          layout/cve2_top.gds  sha256:$GDS_SHA"
} >"$STAGE/tool-versions.txt"

record_leak_guard "$STAGE"

# ---- publish layout and dated record ----------------------------------------
new_record_dir core
mkdir -p "$(dirname "$GDS_OUT")"
GDS_TMP="$GDS_OUT.tmp.$$"
cp "$PR/$TOP.gds" "$GDS_TMP" || { rm -f "$GDS_TMP"; rmdir "$OUT" 2>/dev/null || true; exit 1; }
mv -f "$GDS_TMP" "$GDS_OUT"
cp "$STAGE/par.json" "$STAGE/tool-versions.txt" "$OUT/"
record_leak_guard "$OUT"
echo "par.sh: records -> flow/core/records/$DATE; layout -> layout/cve2_top.gds" >&2
