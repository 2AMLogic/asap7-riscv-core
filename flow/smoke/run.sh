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
#   KLT_CURRENT_CMD  comparison klt for steps the pin cannot perform (default:
#                    the dev build below, via uvx). Its results are labelled
#                    "current", never presented as the pin.
#   KEEP_SCRATCH=1   keep the scratch directory (extracted Liberty, run trees)
#
# Exit status: 0 when every step has a record (a step klt cannot perform gets
# status "not_run" and the klayout-tools issue for the gap); 2 for a refused
# invocation (bad checkout, existing records); 1 when a record is missing, the
# pinned deck hash does not match, or a record leaks a host path.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CURRENT_PIN="git+https://github.com/2AMLogic/klayout-tools@6bb7cf233677"
DUT=counter
DUT_SRC="$REPO/verification/smoke/counter.sv"
STANDIN_CELL=INVx1_ASAP7_75t_R
CELL_LIB=asap7sc7p5t_28_RVT

die() { echo "run.sh: $*" >&2; exit "${2:-2}"; }

[[ $# -eq 1 ]] || die "usage: flow/smoke/run.sh <asap7-checkout>"
[[ -d "$1" ]] || die "not a directory: $1"
ASAP7="$(cd "$1" && pwd)"

# ---- pins, read from the spec -------------------------------------------
spec_sha() {  # first 40-hex sha on the first row of pdk-bringup.md starting with "| $1"
  grep -m1 "^| $1" "$REPO/spec/pdk-bringup.md" | grep -o '[0-9a-f]\{40\}' | head -1
}
PIN_UPSTREAM="$(spec_sha 'Upstream repo')"
PIN_CELLS="$(spec_sha 'Cell library')"
PIN_PDK="$(spec_sha 'PDK (DRM')"
PIN_KLT="$(grep -o 'git+https://github.com/2AMLogic/klayout-tools@[0-9a-f]\{12\}' "$REPO/spec/core.md" | head -1)"
PIN_DECK="$(grep -o 'sha256:[0-9a-f]\{64\}' "$REPO/spec/core.md" | head -1)"
for v in PIN_UPSTREAM PIN_CELLS PIN_PDK PIN_KLT PIN_DECK; do
  [[ -n "${!v}" ]] || die "could not read $v from spec/" 1
done

# ---- the checkout must be at the pins -----------------------------------
check_pin() {  # dir want label
  local got
  got="$(git -C "$1" rev-parse HEAD 2>/dev/null)" || die "$3: $1 is not a git checkout"
  [[ "$got" == "$2" ]] || die "$3 is at $got, spec/pdk-bringup.md pins $2"
}
check_pin "$ASAP7" "$PIN_UPSTREAM" "upstream asap7"
check_pin "$ASAP7/asap7sc7p5t_28" "$PIN_CELLS" "submodule asap7sc7p5t_28"
check_pin "$ASAP7/asap7_pdk_r1p7" "$PIN_PDK" "submodule asap7_pdk_r1p7"

# ---- output directory (never overwrite) ---------------------------------
DATE="${RECORD_DATE:-$(date -u +%Y-%m-%d)}"
OUT="$REPO/flow/smoke/records/$DATE"
if compgen -G "$OUT/*.json" >/dev/null; then
  die "records already exist in flow/smoke/records/$DATE; set RECORD_DATE to a new label (records are append-only evidence)"
fi
mkdir -p "$OUT"

# ---- klt commands --------------------------------------------------------
read -r -a KLT <<<"${KLT_CMD:-uvx --from $PIN_KLT klt}"
read -r -a KLT_CUR <<<"${KLT_CURRENT_CMD:-uvx --from $CURRENT_PIN klt}"

SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/asap7-smoke.XXXXXX")"
cleanup() { [[ "${KEEP_SCRATCH:-0}" == 1 ]] || rm -rf "$SCRATCH"; }
trap cleanup EXIT
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
V_CUR="$("${KLT_CUR[@]}" version 2>&1 | head -1 || true)"

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

# step <name> <input-label> <note-on-success> <issues-on-gap> <fallback:0|1> <klt args...>
# Runs the pinned klt; when fallback=1 and the pin cannot, runs the current dev
# build and says so. Sets STEP_OK=1 when a report exists.
step() {
  local name="$1" input="$2" note="$3" issues="$4" fallback="$5"; shift 5
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
  if [[ "$fallback" == 1 ]]; then
    rc=0
    ( cd "$W" && "${KLT_CUR[@]}" "$@" ) >"$out" 2>"$err" || rc=$?
    if usable "$out"; then
      STEP_OK=1
      extra="$(python3 -I -c 'import json,sys; print(json.dumps({"exit_code":int(sys.argv[1]),"_subs":sys.argv[2],"failed_attempts":json.loads(sys.argv[3]),**json.loads(sys.argv[4])}))' "$rc" "$SCRATCH/subs.json" "$attempts" "${STEP_EXTRA:-{\}}")"
      python3 -I "$SCRATCH/mkrecord.py" "$OUT/$name.json" "$name" ran current "$V_CUR" "$CURRENT_PIN" \
        "Not performed by the pinned build (see failed_attempts); performed by the current dev build, which is not the pin. $note" "${RAN_ISSUES:-}" "$input" "$out" "$extra"
      return
    fi
    attempts="$(python3 -I -c 'import json,sys; a=json.loads(sys.argv[1]); a.append({"build":"current","version":sys.argv[2],"error":sys.argv[3]}); print(json.dumps(a))' "$attempts" "$V_CUR" "$(errmsg "$out" "$err" "$rc")")"
  fi
  not_run "$name" "$input" "$issues" "$attempts" "Step failed on every build tried."
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
mkdir -p "$ROOT/lib/7z" "$ROOT/libs/$CELL_LIB/lef" "$ROOT/libs/$CELL_LIB/techlef"
cat >"$SCRATCH/merge_lib.py" <<'PY'
import re, sys
out, name, *files = sys.argv[1:]
header, cells = None, []
for i, f in enumerate(files):
    t = open(f, encoding="utf-8").read()
    m = re.search(r"^\s*cell\s*\(", t, re.M)
    if i == 0:
        header = re.sub(r"library\s*\([^)]*\)", "library (%s)" % name, t[: m.start()], count=1)
    body = t[m.start():].rstrip()
    assert body.endswith("}")
    cells.append(body[:-1].rstrip() + "\n")
open(out, "w", encoding="utf-8").write(header + "".join(cells) + "}\n")
PY
# Liberty ships as .7z only (no 7z on the workers): extract with a throwaway py7zr env.
LIBJSON="$SCRATCH/liberty.json"
uvx --quiet --from py7zr python -I - "$LIBDIR" "$ROOT/lib/7z" <<'PY'
import glob, sys, py7zr
src, dst = sys.argv[1:3]
for f in sorted(glob.glob(src + "/*_RVT_*_nldm_*.lib.7z")):
    if "_RVT_SS_" in f or "_RVT_TT_" in f:
        with py7zr.SevenZipFile(f) as z:
            z.extractall(dst)
PY
for c in SS TT; do
  # shellcheck disable=SC2046
  python3 -I "$SCRATCH/merge_lib.py" "$ROOT/lib/${CELL_LIB}_$c.lib" "${CELL_LIB}_$c" $(ls "$ROOT"/lib/7z/*_RVT_${c}_nldm_*.lib | sort)
done
python3 -I - "$ROOT/lib" "$LIBDIR" >"$LIBJSON" <<'PY'
import glob, hashlib, json, os, sys
root, libdir = sys.argv[1:3]
sha = lambda p: "sha256:" + hashlib.sha256(open(p, "rb").read()).hexdigest()
out = {}
for c in ("SS", "TT"):
    files = sorted(glob.glob(f"{root}/7z/*_RVT_{c}_nldm_*.lib"))
    out[c] = {
        "source_files": [{"name": os.path.basename(f), "extracted_sha256": sha(f),
                          "archive_sha256": sha(f.replace(root + "/7z", libdir) + ".7z")} for f in files],
        "merged_sha256": sha(f"{root}/asap7sc7p5t_28_RVT_{c}.lib"),
    }
print(json.dumps(out, indent=1))
PY
cat >"$ROOT/klt-pdk.json" <<EOF
{"schema_version":1,"variant":"asap7","assets":{"libs_ref":"libs"},
 "liberty":{"$CELL_LIB":{"SS":"lib/${CELL_LIB}_SS.lib","TT":"lib/${CELL_LIB}_TT.lib"}}}
EOF
ln -s "$ASAP7/asap7sc7p5t_28/LEF/asap7sc7p5t_28_R_1x_220121a.lef" "$ROOT/libs/$CELL_LIB/lef/$CELL_LIB.lef"
# Workaround for klayout-tools #4088: M2 declares OFFSET -0.27 and bare make_tracks aborts.
TECH_SRC="$ASAP7/asap7sc7p5t_28/techlef_misc/asap7_tech_1x_201209.lef"
sed 's/^ OFFSET -0\.27 ;/ OFFSET 0.0 ;/' "$TECH_SRC" >"$ROOT/libs/$CELL_LIB/techlef/${CELL_LIB}__nom.tlef"
cmp -s "$TECH_SRC" "$ROOT/libs/$CELL_LIB/techlef/${CELL_LIB}__nom.tlef" && die "tech LEF patch did not apply" 1
PDKARGS=(--pdk asap7 --pdk-root "$ROOT")

# ---- tool-versions.txt ----------------------------------------------------
{
  echo "# Tool and input versions for flow/smoke/run.sh (predictive PDK; nothing here is fabricated)"
  echo "klt_pinned:   $V_PIN  ($PIN_KLT)"
  echo "klt_current:  $V_CUR  ($CURRENT_PIN)  [comparison build, not the pin]"
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
  echo "tech_lef_patched: sha256:$(sha256sum "$ROOT/libs/$CELL_LIB/techlef/${CELL_LIB}__nom.tlef" | cut -d' ' -f1)  (OFFSET -0.27 -> 0.0 on M2; klayout-tools #4088)"
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
  "Synthesized against the merged RVT SS Liberty." "" 1 \
  synthesize "$W/synth.req.json" "${PDKARGS[@]}" --format json
SYNTH_NETLIST=""
if [[ $STEP_OK == 1 ]]; then
  SYNTH_NETLIST="$(ls -t "$W"/.klt/synthesize/*/${DUT}_synth.v 2>/dev/null | head -1 || true)"
  [[ -n "$SYNTH_NETLIST" ]] && cp "$SYNTH_NETLIST" "$W/${DUT}_synth.v"
fi

# ---- 2. par -----------------------------------------------------------------
PAR_ISSUES="4086,4087,4088"
if [[ -n "$SYNTH_NETLIST" ]]; then
  cat >"$W/par.req.json" <<EOF
{"schema":"klt.place_and_route.request/1","engine":"openroad","netlist":"${DUT}_synth.v","hdl_toplevel":"$DUT",
 "pdk":{"cell_library":"$CELL_LIB","corner":"SS"},
 "floorplan":{"method":"utilization","utilization_pct":60,"aspect_ratio":1.0,"core_margin_um":1.0,"site":"asap7sc7p5t"},
 "io":{"layer_h":"M4","layer_v":"M5"},
 "power":{"power_net":"VDD","ground_net":"VSS","straps":[
   {"layer":"M1","width_um":0.018,"pitch_um":0.54,"followpins":true},
   {"layer":"M4","width_um":0.096,"pitch_um":1.152,"offset_um":0.288},
   {"layer":"M5","width_um":0.096,"pitch_um":1.152,"offset_um":0.288}]},
 "constraints":{"clock_port":"clk","clock_period_ns":1.0},
 "seed":1,"target_stage":"route"}
EOF
  STEP_EXTRA="{}" step par "$DUT synthesized netlist; target_stage route with a power grid" \
    "" "$PAR_ISSUES" 1 place-and-route "$W/par.req.json" "${PDKARGS[@]}" --format json
  if [[ $STEP_OK == 0 ]]; then
    # Record how far the current build gets, so the gap is measured and not assumed.
    python3 -I - "$W/par.req.json" "$W/par_fp.req.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); d.pop("power"); d["target_stage"] = "floorplan"
json.dump(d, open(sys.argv[2], "w"))
PY
    FP_RC=0
    ( cd "$W" && "${KLT_CUR[@]}" place-and-route par_fp.req.json "${PDKARGS[@]}" --format json ) >"$SCRATCH/par_fp.out" 2>"$SCRATCH/par_fp.err" || FP_RC=$?
    if usable "$SCRATCH/par_fp.out"; then
      FP_NOTE="With request.power removed and target_stage floorplan, the current dev build reaches stage floorplan (using the scratch tech-LEF OFFSET workaround, klayout-tools #4088). Placement, CTS and routing were not reached; no DEF or GDS was produced."
    else
      FP_NOTE="floorplan-only probe also failed: $(errmsg "$SCRATCH/par_fp.out" "$SCRATCH/par_fp.err" "$FP_RC")"
    fi
    python3 -I - "$OUT/par.json" "$FP_NOTE" "$SCRATCH/subs.json" <<'PY'
import json, sys
p, note, subs = sys.argv[1:4]
d = json.load(open(p))
d["smoke"]["note"] += " " + note
json.dump(d, open(p, "w"), indent=2, sort_keys=True); open(p, "a").write("\n")
PY
  fi
else
  STEP_EXTRA="{}" not_run par "$DUT synthesized netlist" "" "[]" "no synthesized netlist: the synth step did not produce one"
fi

# ---- stand-in layout for drc / lvs / erc -------------------------------------
# place-and-route produced no layout, so these steps run on one library cell.
# That checks the tool chain and the pinned deck, and says nothing about the counter.
STANDIN="$W/standin.gds"; STANDIN_OK=0
CELL_GDS="$ASAP7/asap7sc7p5t_28/GDS/asap7sc7p5t_28_R_220121a.gds"
if ( cd "$W" && "${KLT[@]}" clip --cell "$STANDIN_CELL" -o "$STANDIN" --format json "$CELL_GDS" ) >/dev/null 2>"$SCRATCH/clip.err"; then
  STANDIN_OK=1
fi
STANDIN_LABEL="library cell $STANDIN_CELL clipped from the pinned cell GDS (stand-in: the counter has no layout because place-and-route is not_run)"
standin_missing() { STEP_EXTRA="{}" not_run "$1" "$STANDIN_LABEL" "" "[]" "stand-in layout could not be produced: $(head -c 400 "$SCRATCH/clip.err")"; }

# ---- 3. drc ------------------------------------------------------------------
DECK_FILE="${KLT_DECK_FILE:-}"
if [[ -z "$DECK_FILE" && -z "${KLT_CMD:-}" ]]; then
  DECK_FILE="$(uvx --quiet --from "$PIN_KLT" python -I -c 'from klayout_tools.decks import asap7_rules as r; print(r.DECK_PATH)')"
fi
[[ -f "$DECK_FILE" ]] || die "cannot locate the pinned asap7.drc: set KLT_DECK_FILE" 1
mkdir -p "$SCRATCH/deck"; cp "$DECK_FILE" "$SCRATCH/deck/asap7.drc"
if [[ $STANDIN_OK == 1 ]]; then
  STEP_EXTRA='{"unchecked":"Rules needing track/net/corner/grid predicates, FEOL/MOL increments and PAD are not checked (spec/pdk-bringup.md section 3; spec/core.md DRC acceptance)."}' \
  step drc "$STANDIN_LABEL" \
    "Pinned klt, --engine klayout with the packaged ASAP7 deck, --expect-rule-categories 263." "" 0 \
    drc --engine klayout --deck-file "$SCRATCH/deck/asap7.drc" --expect-rule-categories 263 --format json "$STANDIN"
else standin_missing drc; fi

# ---- 4. lvs ------------------------------------------------------------------
if [[ $STANDIN_OK == 1 ]]; then
  cat >"$W/lvs.req.json" <<EOF
{"schema":"klt.lvs.request/1","engine":"klayout",
 "layout":{"file":"$STANDIN","deck":"asap7","top":"$STANDIN_CELL"},
 "reference":{"netlist":"$ASAP7/asap7sc7p5t_28/CDL/LVS/asap7sc7p5t_28_R.cdl","top":"$STANDIN_CELL"},
 "options":{"finfet_bulk":{"nmos":"VSS","pmos":"VDD"}}}
EOF
  STEP_EXTRA='{"bulk_policy":"options.finfet_bulk nmos=VSS pmos=VDD (decision 0005); disclosed by the tool as device.finfet_bulk_tied"}' \
  step lvs "$STANDIN_LABEL, against its subckt in the pinned cell CDL" \
    "Pinned klt; layout, reference and deck hashes are in environment and provenance." "" 0 \
    lvs "$W/lvs.req.json" --format json
else standin_missing lvs; fi

# ---- 5. erc ------------------------------------------------------------------
if [[ $STANDIN_OK == 1 ]]; then
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
  step erc "$STANDIN_LABEL" \
    "Pinned klt, --deck asap7, stackup spec generated by run.sh (gate 7/0 with active 11/0, LIG 16/0, M1 19/0, M2 20/0, V0 18/0, V1 21/0)." "4090" 0 \
    erc --deck asap7 --format json "$STANDIN" "$W/erc.spec.json"
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
    "Two corners from one request; the file lists name every Liberty source." "4089" 1 \
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
echo "run.sh: records written to flow/smoke/records/$DATE:" >&2
python3 -I - "$OUT" <<'PY' >&2
import glob, json, os, sys
for p in sorted(glob.glob(sys.argv[1] + "/*.json")):
    d = json.load(open(p)); s = d["smoke"]
    print(f"  {os.path.basename(p):10} {d.get('status', '?'):12} {s['run_state']:8} build={s['klt_build']['role']:7} issues={s['klayout_tools_issues']}")
PY
