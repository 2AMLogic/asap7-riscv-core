#!/usr/bin/env bash
# Core place-and-route flow (T1 item 2): runs `klt place-and-route` of the
# committed gate-level netlist (the newest flow/core/records/<date>/netlist.v
# at HEAD, read from Git, never from the working tree)
# with the decision 0004 floorplan (60 % utilisation, aspect 1.0, single
# block, no macro) and the pinned PDK inputs, and writes the routed GDS to
# layout/cve2_top.gds plus a par record under flow/core/records/<date>/, or,
# with --check, refuse unless the netlist selected at HEAD is the one the
# newest committed flow/core/records/<date>/par.json pins in
# core_flow.input_netlist (a moved input fails the regeneration claim before
# anything is routed), then regenerate the GDS, validate the response, and
# byte-compare it with the committed HEAD:layout/cve2_top.gds.
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
# --check --export <dir>: once the regenerated GDS has compared byte-identical
# with HEAD:layout/cve2_top.gds, publish the routed DEF and the matching routed
# Verilog (plus the ODB, when the pinned run produced one) together at <dir>,
# with a manifest.json naming the top cell, the captured INPUT_REV, the input
# netlist's path and sha256, the compared GDS's sha256 and every exported
# artifact's filename and sha256 -- one bundle a Spot worker copies as a unit
# (#284) and verifies against the committed reference before accepting. The
# bundle is staged beside <dir> and made visible in a single rename; a failed
# run publishes nothing and leaves <dir> free for a retry, and an existing
# <dir> is a refusal before anything runs.
#
# <asap7-checkout> is The-OpenROAD-Project/asap7 at the pins in
# spec/pdk-bringup.md section 1, with the asap7_pdk_r1p7 and asap7sc7p5t_28
# submodules initialised. The script refuses any other checkout.
#
# Prerequisites on $PATH: `openroad` (required by `klt place-and-route`; build
# `26Q3-1510-g6cb3f2b704` produced the committed layout, recorded in
# flow/core/records/2026-11-22/tool-versions.txt), `uvx` and `python3`;
# writing a new record also queries `yosys -V` for tool-versions.txt.
# --export uses Linux renameat2(RENAME_NOREPLACE) on the destination filesystem.
#
# Environment:
#   RECORD_DATE     record directory name (default: today, UTC). The script
#                  refuses to write into a directory that already has records.
#   KLT_CMD         klt to run (default: the release pinned in spec/core.md,
#                  via uvx)
#   KEEP_SCRATCH=1  keep the scratch directory
#
# Exit status: 0 ok (and, with --check, byte-identical to
# HEAD:layout/cve2_top.gds, with any --export bundle published); 1 a step
# failed, the response failed validation, a staged record leaked a host path,
# an export could not be published, or --check found a difference -- a GDS
# byte difference, or the selected netlist not being the one the newest
# committed par.json pins, or that record having no readable input pin; 2
# refused invocation -- including --check finding no committed
# HEAD:layout/cve2_top.gds to compare against at all (a refusal, not a
# difference), --export without --check, and an --export destination that
# already exists.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=flow/lib.sh
source "$REPO/flow/lib.sh"
TOP=cve2_rv32imc_wrapper
CELL_LIB=asap7sc7p5t_28_R
GDS_OUT="$REPO/layout/cve2_top.gds"

CHECK=0
EXPORT_DEST=""
EXPORT_GIVEN=0
ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --check) CHECK=1; shift ;;
    --export)
      [[ $# -ge 2 ]] || die "usage: flow/core/par.sh <asap7-checkout> --check --export <dir>: --export needs a directory argument"
      EXPORT_DEST="$2"; EXPORT_GIVEN=1; shift 2 ;;
    -*) die "unknown option: $1" ;;
    *) ARGS+=("$1"); shift ;;
  esac
done
[[ ${#ARGS[@]} -le 1 ]] || die "usage: flow/core/par.sh [<asap7-checkout>] [--check] [--export <dir>]"
ASAP7_ARG="${ARGS[0]:-${ASAP7_DIR:-}}"
[[ -n "$ASAP7_ARG" ]] || die "usage: flow/core/par.sh <asap7-checkout> [--check] [--export <dir>] (or set ASAP7_DIR)"
[[ -d "$ASAP7_ARG" ]] || die "not a directory: $ASAP7_ARG"
ASAP7="$(cd "$ASAP7_ARG" && pwd)"

# ---- --export gate -----------------------------------------------------------
# The bundle is published on the --check comparison path only, so an export
# request without --check is a refused invocation, and a destination that
# already exists is refused here -- before the pins, the scratch and the
# route -- so a caller learns immediately that the path is taken and a failed
# run always leaves the requested destination free for a retry. Trailing
# slashes are normalised so the staging directory is a sibling of the
# destination, never a path inside it.
if [[ $EXPORT_GIVEN == 1 ]]; then
  [[ -n "$EXPORT_DEST" ]] || die "--export needs a non-empty directory path"
  while [[ "$EXPORT_DEST" == */ && "$EXPORT_DEST" != "/" ]]; do EXPORT_DEST="${EXPORT_DEST%/}"; done
  [[ $CHECK == 1 ]] \
    || die "--export publishes on the --check comparison path; rerun with --check (usage: flow/core/par.sh <asap7-checkout> --check --export <dir>)"
  [[ ! -e "$EXPORT_DEST" && ! -L "$EXPORT_DEST" ]] \
    || die "export destination already exists: $EXPORT_DEST (a failed run leaves it free for a retry; remove a published bundle or choose another path)"
fi

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
# Captured once from one Git revision: the newest committed
# flow/core/records/<date>/netlist.v at INPUT_REV, read as a blob. The working
# tree is never consulted, so an untracked or edited netlist cannot become the
# routed input, and the bytes hashed for the records are the bytes the router
# receives (a pristine copy is hashed; the router gets a second copy).
INPUT_REV="$(git -C "$REPO" rev-parse --verify 'HEAD^{commit}')" \
  || die "cannot resolve HEAD to select the committed netlist" 2
NETLIST_SRC="$(git -C "$REPO" ls-tree -r --name-only "$INPUT_REV" -- flow/core/records/ \
  | grep -E '^flow/core/records/[^/]+/netlist\.v$' | LC_ALL=C sort | tail -n 1)" || true
[[ -n "$NETLIST_SRC" ]] \
  || die "no committed netlist to place: no flow/core/records/<date>/netlist.v at HEAD"
W="$SCRATCH/work"; mkdir -p "$W"
NETLIST_IN="$SCRATCH/input-netlist.v"
git -C "$REPO" cat-file blob "$INPUT_REV:$NETLIST_SRC" >"$NETLIST_IN" \
  || die "cannot read $NETLIST_SRC at $INPUT_REV" 1
[[ -s "$NETLIST_IN" ]] || die "committed $NETLIST_SRC is empty" 1
NETLIST_SHA="$(sha "$NETLIST_IN")"

# ---- --check input pin ------------------------------------------------------
# The byte-compare validates the newest committed par.json's regeneration
# claim, so --check must refuse unless the netlist just selected is the one
# that record pins in core_flow.input_netlist. Without this gate a newer
# committed netlist (a re-synthesis) would be routed while the evidence pins
# the older one, and the compare would report an unexplained GDS difference
# instead of the moved input. The pin is read from Git at INPUT_REV, like the
# netlist itself, so working-tree records cannot self-verify; with no
# committed par.json at all (first run) there is no pin and behaviour is
# unchanged. Record mode never passes this gate: it is how a moved input is
# re-pinned, routing the newest netlist and writing the record that pins it.
if [[ $CHECK == 1 ]]; then
  PIN_PAR="$(git -C "$REPO" ls-tree -r --name-only "$INPUT_REV" -- flow/core/records/ \
    | grep -E '^flow/core/records/[^/]+/par\.json$' | LC_ALL=C sort | tail -n 1)" || true
  if [[ -n "$PIN_PAR" ]]; then
    if ! PIN_ROW="$(python3 -I - "$REPO" "$INPUT_REV" "$PIN_PAR" <<'PY'
import json, subprocess, sys
repo, rev, path = sys.argv[1:4]
blob = subprocess.run(["git", "-C", repo, "cat-file", "blob", f"{rev}:{path}"],
                      check=True, capture_output=True).stdout
try:
    pin = json.loads(blob)["core_flow"]["input_netlist"]
    print(f"{pin['path']}\t{pin['sha256']}")
except Exception as e:
    sys.exit(f"cannot read core_flow.input_netlist from {path}: {e}")
PY
)"; then
      die "--check cannot read the input pin: $PIN_PAR at ${INPUT_REV:0:12} has no readable core_flow.input_netlist (a committed par.json without it is a broken record)" 1
    fi
    IFS=$'\t' read -r PIN_NL_PATH PIN_NL_SHA <<<"$PIN_ROW"
    if [[ "$PIN_NL_SHA" != "$NETLIST_SHA" ]]; then
      die "--check input pin mismatch: HEAD selects $NETLIST_SRC (sha256:$NETLIST_SHA) but the newest committed record $PIN_PAR pins $PIN_NL_PATH (sha256:$PIN_NL_SHA); rerun without --check to write the record that re-pins the new input" 1
    fi
  fi
fi
cp "$NETLIST_IN" "$W/${TOP}_synth.v"

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
echo "par.sh: placing and routing ${TOP} from $NETLIST_SRC at ${INPUT_REV:0:12}" >&2
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
if d.get("status") != "ok":
    print(f"status is {d.get('status')!r}, expected 'ok'")
    sys.exit(1)
if d.get("stage_reached") != "route":
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

# ---- compare (--check) and export (--check --export <dir>) ------------------
# The export is published only on the byte-identical path, after the response
# validation and the DEF/Verilog existence checks above, so a rejected route,
# a missing output or a GDS difference publishes nothing. The bundle is staged
# beside the destination -- same directory, hence one filesystem, hence one
# rename makes it visible as a unit -- and every failure removes the staging
# directory, leaving the requested destination free for a retry. The manifest
# digests are computed from the staged copies, so they always describe the
# bytes the destination actually receives, and the leak guard runs over the
# staged bundle for the same reason it runs over a staged record: nothing
# published from this flow may name a host path.
export_bundle() (
  local f stage gds_sha
  if ! gds_sha="$(sha "$PR/$TOP.gds")" || [[ ! $gds_sha =~ ^[0-9a-f]{64}$ ]]; then
    echo "par.sh: cannot compute SHA-256 for $TOP.gds" >&2
    return 1
  fi
  mkdir -p -- "$(dirname -- "$EXPORT_DEST")" || return 1
  stage="$(mktemp -d -- "$EXPORT_DEST.export.XXXXXX")" || return 1
  trap 'rm -rf -- "$stage"' EXIT
  for f in "$TOP.def" "$TOP.v"; do
    cp -- "$PR/$f" "$stage/$f" || return 1
  done
  # An ODB accompanies the DEF when the pinned run produced one; it is
  # optional, so its absence is not a failure.
  [[ ! -s "$PR/$TOP.odb" ]] || cp -- "$PR/$TOP.odb" "$stage/$TOP.odb" || return 1
  python3 -I - "$stage" "$TOP" "$INPUT_REV" "$NETLIST_SRC" "$NETLIST_SHA" \
    "$gds_sha" <<'PY' || return 1
import hashlib, json, os, sys
stage, top, rev, nl_path, nl_sha, gds_sha = sys.argv[1:7]
def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()
artifacts = [{"filename": n, "sha256": sha256(os.path.join(stage, n))}
             for n in sorted(os.listdir(stage))]
manifest = {
    "schema_version": 1,
    "note": "Routed export published by flow/core/par.sh --check --export: the "
            "routed DEF and the matching routed Verilog (plus the ODB when the "
            "pinned run produced one) of the top cell below, exported only "
            "after the regenerated GDS compared byte-identical with the "
            "committed HEAD:layout/cve2_top.gds, so gds.sha256 is the digest "
            "of both. Predictive PDK; nothing here is fabricated or measured.",
    "predicted": True,
    "top_cell": top,
    "input_rev": rev,
    "input_netlist": {"path": nl_path, "sha256": nl_sha},
    "gds": {"path": "layout/cve2_top.gds", "sha256": gds_sha},
    "artifacts": artifacts,
}
with open(os.path.join(stage, "manifest.json"), "w", encoding="utf-8") as f:
    json.dump(manifest, f, indent=2, sort_keys=True)
    f.write("\n")
PY
  record_leak_guard "$stage" || return 1
  # The existence check and the rename must be one filesystem operation,
  # including when a competing process creates an empty destination directory.
  python3 -I - "$stage" "$EXPORT_DEST" <<'PY' || return 1
import ctypes, os, sys

libc = ctypes.CDLL(None, use_errno=True)
if not hasattr(libc, "renameat2"):
    sys.exit("par.sh: --export requires renameat2(RENAME_NOREPLACE)")
AT_FDCWD, RENAME_NOREPLACE = -100, 1
stage, dest = map(os.fsencode, sys.argv[1:])
if libc.renameat2(AT_FDCWD, stage, AT_FDCWD, dest, RENAME_NOREPLACE) != 0:
    sys.exit(f"par.sh: cannot publish {sys.argv[2]}: {os.strerror(ctypes.get_errno())}")
PY
  trap - EXIT
)
if [[ $CHECK == 1 ]]; then
  if cmp -s "$PR/$TOP.gds" "$COMMITTED_GDS"; then
    echo "par.sh: regenerated GDS is byte-identical to HEAD:layout/cve2_top.gds" \
         "(sha256:$(sha "$COMMITTED_GDS"))" >&2
    if [[ $EXPORT_GIVEN == 1 ]]; then
      if ! export_bundle; then
        if [[ -e "$EXPORT_DEST" || -L "$EXPORT_DEST" ]]; then
          die "publishing the export to $EXPORT_DEST failed: the destination exists (nothing of this run was published there); remove it or choose another path" 1
        fi
        die "publishing the export to $EXPORT_DEST failed; nothing was left published, retry the run" 1
      fi
      echo "par.sh: export -> $EXPORT_DEST (routed DEF and netlist of $TOP with manifest.json)" >&2
    fi
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
python3 -I - "$SCRATCH/par.out" "$GDS_SHA" "$NETLIST_SRC" "$NETLIST_SHA" <<'PY' | python3 -I "$REPO/flow/record_lib.py" write "$STAGE/par.json" "$SCRATCH/subs.json"
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
  echo "input_netlist: $NETLIST_SRC  sha256:$NETLIST_SHA  (blob at HEAD ${INPUT_REV:0:12})"
  echo "gds:          layout/cve2_top.gds  sha256:$GDS_SHA"
} >"$STAGE/tool-versions.txt"

record_leak_guard "$STAGE"

# ---- publish dated record and layout ----------------------------------------
# Order matters for retryability: the record files are written first (exclusive
# create, so nothing existing is overwritten and a directory squatting on a
# target path is an error), the leak guard runs over the published record, and
# layout/cve2_top.gds is replaced last by one atomic rename. Any failure before
# that rename removes exactly what this run created, leaving the previous
# layout in place and the record directory free for a retry.
CREATED=()
GDS_TMP="$GDS_OUT.tmp.$$"
OUT_MADE=0
[[ -d "$OUT" ]] || OUT_MADE=1
publish_rollback() {
  local f
  rm -f "$GDS_TMP"
  for f in ${CREATED[@]+"${CREATED[@]}"}; do rm -f "$f"; done
  if [[ $OUT_MADE == 1 ]]; then rmdir "$OUT" 2>/dev/null || true; fi
  return 0
}
publish() {
  local f
  mkdir -p "$OUT" "$(dirname "$GDS_OUT")" || return 1
  cp "$PR/$TOP.gds" "$GDS_TMP" || return 1
  for f in par.json tool-versions.txt; do
    ( set -o noclobber; cat "$STAGE/$f" >"$OUT/$f" ) || return 1
    CREATED+=("$OUT/$f")
  done
  ( record_leak_guard "$OUT" ) || return 1
  mv -f "$GDS_TMP" "$GDS_OUT" || return 1
}
if ! publish; then
  publish_rollback
  die "publishing the record and layout failed; nothing was left published (the previous layout is untouched), retry the run" 1
fi
echo "par.sh: records -> flow/core/records/$DATE; layout -> layout/cve2_top.gds" >&2
