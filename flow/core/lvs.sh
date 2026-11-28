#!/usr/bin/env bash
# Core LVS flow (T1 item 4): runs `klt lvs --engine klayout` on the
# committed routed GDS (HEAD:layout/cve2_top.gds, read from Git, never from
# the working tree) against the routed gate-level netlist of the same route,
# on the pinned ASAP7 extraction deck (deck `asap7`, sha256 5c58a50e...ee76;
# spec/core.md "DRC / LVS acceptance", decisions 0005 and 0013), and writes a
# dated record under flow/core/records/<date>/.
#
# The reference is the routed netlist, not the item-1 netlist: place-and-route
# resizes, re-buffers and inserts tie cells, so the routed layout instantiates
# a different cell population than the synthesized netlist and no compare
# against that netlist can match. The routed netlist reaches this script as
# the bundle `flow/core/par.sh <asap7-checkout> --check --export <dir>`
# publishes once the regenerated GDS compared byte-identical with the
# committed one; its manifest.json binds the netlist to the committed GDS
# and to the input netlist the committed par record pins, and this script
# refuses a bundle that does not name both.
#
# options.finfet_bulk {nmos: VSS, pmos: VDD} is the recorded bulk policy
# (decision 0005: the cells draw no taps, and the tie is a disclosed
# assumption, reported by the tool as device.finfet_bulk_tied). Nothing else
# is relaxed: the script records what the pinned tool reports and never
# filters, patches or re-runs to a prettier status. A mismatch report is a
# recorded, valid outcome.
#
# ASAP7 is a predictive PDK; nothing here is fabricated or measured, and no
# LVS verdict is a silicon claim.
#
# usage: flow/core/lvs.sh <asap7-checkout> <routed-export-dir>
#
# <asap7-checkout> is The-OpenROAD-Project/asap7 at the pins in
# spec/pdk-bringup.md section 1, with the asap7_pdk_r1p7 and asap7sc7p5t_28
# submodules initialised; its cell CDL is the reference pin-order source. The
# script refuses any other checkout.
#
# Prerequisites: `uvx` and network egress (the pinned klt is resolved
# automatically), or KLT_CMD to run a pre-resolved klt. Record publication
# uses GNU `ln -T` to link each record file into place without replacement
# (flow/core/record_publish.sh).
#
# Environment:
#   RECORD_DATE     record directory name (default: today, UTC). The script
#                  refuses to write into a directory that already has records.
#   KLT_CMD         klt to run (default: the release pinned in spec/core.md,
#                  via uvx)
#   KEEP_SCRATCH=1  keep the scratch directory
#
# Exit status: 0 a report was recorded (match or mismatch); 1 a step failed,
# the report names a deck other than the pin, does not echo the recorded
# bulk policy, carries no verdict, or names a layout or reference other than
# the checked inputs, an input is not the one the newest committed par.json
# pins, or a staged record leaked a host path; 2 a refused invocation (no
# committed GDS to check, a bundle that does not describe that GDS and route,
# a checkout or CDL that is not at the pin, or records already exist for the
# date).
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=flow/lib.sh
source "$REPO/flow/lib.sh"
# shellcheck source=flow/core/record_publish.sh
source "$REPO/flow/core/record_publish.sh"
TOP=cve2_rv32imc_wrapper
GDS_PATH=layout/cve2_top.gds
CELL_LIB=asap7sc7p5t_28
CDL_PATH="$CELL_LIB/CDL/LVS/asap7sc7p5t_28_R.cdl"

[[ $# -eq 2 ]] || die "usage: flow/core/lvs.sh <asap7-checkout> <routed-export-dir>" 2
[[ -d "$1" ]] || die "not a directory: $1" 2
ASAP7="$(cd "$1" && pwd)"
[[ -d "$2" ]] || die "not a directory: $2 (the bundle flow/core/par.sh --check --export publishes)" 2
EXPORT="$(cd "$2" && pwd)"

# ---- pins, read from the spec -------------------------------------------
# Label-anchored and fail-closed (flow/lib.sh); the same reads the smoke
# flow and flow/core/drc.sh make, so the drivers cannot drift onto different
# pins. PIN_LVS_DECK is the deck `asap7` hash the spec pins for LVS.
PIN_UPSTREAM="$(spec_sha 'Upstream repo')" || exit 1
PIN_CELLS="$(spec_sha 'Cell library')" || exit 1
PIN_PDK="$(spec_sha 'PDK (DRM')" || exit 1
PIN_KLT="$(spec_klt_pin)" || exit 1
PIN_LVS_DECK="$(spec_pin 'pinned LVS deck hash' 'sha256:[0-9a-f]\{64\}' 1)" || exit 1

# spec_file_sha <pinned-file-path>: first 64-hex sha256 on the first
# spec/pdk-bringup.md row naming that file. Label-anchored and fail-closed
# like the reads in flow/lib.sh, and defined here because flow/lib.sh is an
# attested path (attest/item9.json) this driver has no change for.
spec_file_sha() {
  local v
  v="$(grep -F -m1 -e "$1" "$REPO/spec/pdk-bringup.md" 2>/dev/null \
       | grep -o '[0-9a-f]\{64\}' | head -1 || true)"
  [[ -n "$v" ]] || die "spec/pdk-bringup.md: no 64-hex sha256 on a row naming \"$1\"" 1
  printf '%s\n' "$v"
}
PIN_CDL="$(spec_file_sha "$CDL_PATH")" || exit 1

# ---- the checkout must be at the pins -----------------------------------
check_pin "$ASAP7" "$PIN_UPSTREAM" "upstream asap7"
check_pin "$ASAP7/asap7sc7p5t_28" "$PIN_CELLS" "submodule asap7sc7p5t_28"
check_pin "$ASAP7/asap7_pdk_r1p7" "$PIN_PDK" "submodule asap7_pdk_r1p7"
CDL="$ASAP7/$CDL_PATH"
[[ -f "$CDL" ]] || die "no cell CDL at $CDL_PATH in the checkout" 2
CDL_SHA="$(sha "$CDL")"
[[ "$CDL_SHA" == "$PIN_CDL" ]] \
  || die "$CDL_PATH in the checkout is sha256:$CDL_SHA, not the pin $PIN_CDL (spec/pdk-bringup.md)" 2

# ---- mode gate: append-only records, one pinned date ---------------------
RECORD_DATE="${RECORD_DATE:-$(date -u +%Y-%m-%d)}"
DATE="$RECORD_DATE"
OUT="$REPO/flow/core/records/$DATE"
if compgen -G "$OUT/*.json" >/dev/null; then
  die "records already exist in flow/core/records/$DATE; set RECORD_DATE to a new label (records are append-only evidence)" 2
fi

klt_cmd "$PIN_KLT"

setup_scratch corelvs

# ---- input: the committed routed GDS, byte-bound -------------------------
# Captured once from one Git revision, as flow/core/drc.sh does: the GDS at
# HEAD, read as a blob, so the bytes hashed for the record are the bytes the
# deck extracts, and neither read can pick up a layout from a later commit
# than the routing record below.
INPUT_REV="$(git -C "$REPO" rev-parse --verify 'HEAD^{commit}')" \
  || die "cannot resolve HEAD to select the committed GDS" 2
GDS_REF="$INPUT_REV:$GDS_PATH"
git -C "$REPO" cat-file -e "$GDS_REF" 2>/dev/null \
  || die "no committed HEAD:$GDS_PATH to check (T1 item 2 has not landed)" 2
W="$SCRATCH/work"; mkdir -p "$W"
GDS_IN="$W/$TOP.gds"
git -C "$REPO" cat-file blob "$GDS_REF" >"$GDS_IN" \
  || die "cannot read $GDS_PATH at $INPUT_REV" 1
[[ -s "$GDS_IN" ]] || die "committed $GDS_PATH is empty" 1
GDS_SHA="$(sha "$GDS_IN")"

# ---- input pin: the route the newest committed par.json records ----------
# The record must bind to the GDS the committed place-and-route record pins
# in core_flow.gds.sha256, and the reference must be routed from the netlist
# that record pins in core_flow.input_netlist: a re-route (a new par record
# and a new GDS) cannot leave this LVS record describing a superseded layout,
# and a netlist from any other route cannot serve as its reference.
PIN_PAR="$(git -C "$REPO" ls-tree -r --name-only "$INPUT_REV" -- flow/core/records/ \
  | grep -E '^flow/core/records/[^/]+/par\.json$' | LC_ALL=C sort | tail -n 1)" || true
[[ -n "$PIN_PAR" ]] || die "no committed flow/core/records/<date>/par.json at HEAD: nothing pins the GDS this run would check" 2
if ! IFS=$'\t' read -r PIN_GDS_SHA PIN_NL_PATH PIN_NL_SHA <<<"$(git -C "$REPO" cat-file blob "$INPUT_REV:$PIN_PAR" \
  | python3 -I -c 'import json,sys; c=json.load(sys.stdin)["core_flow"]; print(c["gds"]["sha256"], c["input_netlist"]["path"], c["input_netlist"]["sha256"], sep="\t")' 2>/dev/null)"; then
  die "cannot read core_flow.gds.sha256 and core_flow.input_netlist from $PIN_PAR at ${INPUT_REV:0:12} (a committed par.json without them is a broken record)" 1
fi
[[ -n "$PIN_GDS_SHA" && -n "$PIN_NL_PATH" && -n "$PIN_NL_SHA" ]] \
  || die "cannot read core_flow.gds.sha256 and core_flow.input_netlist from $PIN_PAR at ${INPUT_REV:0:12} (a committed par.json without them is a broken record)" 1
if [[ "$PIN_GDS_SHA" != "$GDS_SHA" ]]; then
  die "input pin mismatch: HEAD:$GDS_PATH is sha256:$GDS_SHA but the newest committed record $PIN_PAR pins sha256:$PIN_GDS_SHA; land the new par record first (run flow/core/par.sh), then rerun this script" 1
fi

# ---- reference: the routed netlist of that route, through its manifest ---
# The bundle's manifest names the GDS it was exported against and the input
# netlist it was routed from; both must equal the pins read above, and the
# netlist on disk must hash to the manifest's digest. The verified bytes are
# then copied into scratch and hashed again, so the reference hash in the
# record is the hash of the bytes the tool compared.
if ! REF_JSON="$(python3 -I - "$EXPORT/manifest.json" "$EXPORT" "$TOP" "$GDS_SHA" "$PIN_NL_PATH" "$PIN_NL_SHA" <<'PY'
import hashlib, json, os, sys

manifest, export, top, gds_sha, nl_path, nl_sha = sys.argv[1:7]
# The committed layout path, as the par.sh export manifest names it.
gds_path = "layout/cve2_top.gds"

def fail(msg):
    print("lvs.sh: " + msg, file=sys.stderr)
    sys.exit(2)

try:
    m = json.load(open(manifest, encoding="utf-8"))
except Exception as e:
    fail(f"cannot read the export bundle's manifest {manifest}: {e}")
if m.get("top_cell") != top:
    fail(f"the export bundle's top_cell is {m.get('top_cell')!r}, not {top}")
if (m.get("gds") or {}).get("sha256") != gds_sha:
    fail(f"the export bundle was exported against GDS sha256:{(m.get('gds') or {}).get('sha256')}, "
         f"but HEAD:{gds_path} is sha256:{gds_sha}: export the bundle from this route "
         "(flow/core/par.sh --check --export) and rerun")
nl = m.get("input_netlist") or {}
if nl.get("sha256") != nl_sha or nl.get("path") != nl_path:
    fail(f"the export bundle was routed from {nl.get('path')} (sha256:{nl.get('sha256')}), "
         f"but the par record pins {nl_path} (sha256:{nl_sha})")
want = None
for a in m.get("artifacts") or []:
    if a.get("filename") == top + ".v":
        want = a.get("sha256")
if not want:
    fail(f"the export bundle's manifest lists no {top}.v artifact")
path = os.path.join(export, top + ".v")
h = hashlib.sha256()
try:
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
except OSError as e:
    fail(f"cannot read the routed netlist {path}: {e}")
if h.hexdigest() != want:
    fail(f"the routed netlist {top}.v is sha256:{h.hexdigest()}, not the manifest's sha256:{want}")
print(json.dumps({"netlist": top + ".v", "sha256": want, "input_rev": m.get("input_rev")}))
PY
)"; then
  exit 2
fi
REF_NAME="$(python3 -I -c 'import json,sys; print(json.loads(sys.argv[1])["netlist"])' "$REF_JSON")"
REF_SHA="$(python3 -I -c 'import json,sys; print(json.loads(sys.argv[1])["sha256"])' "$REF_JSON")"
EXPORT_REV="$(python3 -I -c 'import json,sys; print(json.loads(sys.argv[1])["input_rev"])' "$REF_JSON")"
cp "$EXPORT/$REF_NAME" "$W/$REF_NAME" || die "cannot copy the routed netlist into scratch" 1
[[ "$(sha "$W/$REF_NAME")" == "$REF_SHA" ]] \
  || die "the routed netlist changed while it was being copied: rerun flow/core/par.sh --check --export" 1

# ---- run the pinned klt ---------------------------------------------------
# The smoke flow's request shape (flow/smoke/run.sh, step lvs): the cells of
# the gate-level reference expand to their CDL bodies, flatten_layout makes
# the layout side as flat as that reference (flatten_reference is the tool's
# default on this route), and finfet_bulk is the recorded bulk policy. A
# match and a mismatch are both successful runs of the step: usability is
# judged on the report (flow/record_lib.py usable), not on the exit status.
# The compare has no deadline: an expired options.compare_timeout_s yields
# status "inconclusive", which is no verdict and is refused below.
echo "lvs.sh: comparing $GDS_PATH (sha256:$GDS_SHA) against the routed netlist $REF_NAME (sha256:$REF_SHA)" >&2
cat >"$W/lvs.req.json" <<EOF
{"schema":"klt.lvs.request/1","engine":"klayout",
  "layout":{"file":"$GDS_IN","deck":"asap7","top":"$TOP"},
  "reference":{"netlist":"$W/$REF_NAME","form":"gate-level-verilog","top":"$TOP","pin_order_files":["$CDL"]},
  "options":{"finfet_bulk":{"nmos":"VSS","pmos":"VDD"},"flatten_layout":true}}
EOF
rc=0
"${KLT[@]}" lvs "$W/lvs.req.json" --format json >"$SCRATCH/lvs.out" 2>"$SCRATCH/lvs.err" || rc=$?
if ! python3 -I "$REPO/flow/record_lib.py" usable "$SCRATCH/lvs.out"; then
  echo "lvs.sh: klt lvs failed (exit $rc)" >&2
  head -c 2000 "$SCRATCH/lvs.out" "$SCRATCH/lvs.err" >&2
  exit 1
fi

# ---- validate the report --------------------------------------------------
# The report must name the pinned deck, the checked layout and reference
# bytes, the gate-level reference form and the recorded bulk policy, and
# carry a verdict with its disclosure, before anything is recorded: a report
# from any other deck, or about any other inputs, is not the acceptance
# check, and "inconclusive" is no verdict.
if ! LVS_ERR="$(python3 -I - "$SCRATCH/lvs.out" "$PIN_LVS_DECK" "$GDS_SHA" "$REF_SHA" <<'PY'
import json, sys

src, want_deck, gds_sha, ref_sha = sys.argv[1:5]
d = json.load(open(src, encoding="utf-8"))

def fail(msg):
    print(msg)
    sys.exit(1)

deck = d.get("provenance", {}).get("deck", {}).get("content_hash")
if deck != want_deck:
    fail(f"provenance.deck.content_hash is {deck!r}, expected the pin {want_deck!r}")
env = d.get("environment") or {}
if env.get("layout_sha256") != "sha256:" + gds_sha:
    fail(f"environment.layout_sha256 is {env.get('layout_sha256')!r}, expected sha256:{gds_sha} (the checked GDS blob)")
if env.get("reference_sha256") != "sha256:" + ref_sha:
    fail(f"environment.reference_sha256 is {env.get('reference_sha256')!r}, expected sha256:{ref_sha} (the routed netlist)")
if (d.get("reference_conversion") or {}).get("form") != "gate-level-verilog":
    fail(f"reference_conversion.form is {(d.get('reference_conversion') or {}).get('form')!r}, expected 'gate-level-verilog'")
if d.get("options", {}).get("finfet_bulk") != {"nmos": "VSS", "pmos": "VDD"}:
    fail(f"options.finfet_bulk is {d.get('options', {}).get('finfet_bulk')!r}, expected the recorded policy nmos=VSS pmos=VDD")
if d.get("status") not in ("match", "mismatch"):
    fail(f"status is {d.get('status')!r}, expected 'match' or 'mismatch' (no verdict was reached)")
if (d.get("category_counts") or {}).get("device.finfet_bulk_tied", 0) < 1:
    fail("the report carries no device.finfet_bulk_tied entry: the bulk tie is not disclosed")
PY
)"; then
  die "$LVS_ERR" 1
fi

# ---- stage & validate record before publishing ----------------------------
# Assemble lvs.json and tool-versions.txt in scratch and run
# record_leak_guard before creating flow/core/records/$DATE, so a redaction
# miss or tool error never leaves published outputs behind.
STAGE="$SCRATCH/record"; mkdir -p "$STAGE"
record_subs "$SCRATCH/subs.json" "$SCRATCH=<scratch>" "$ASAP7=<asap7-checkout>" "$EXPORT=<routed-export>" "$REPO=<repo>" "$HOME=<home>"
python3 -I - "$SCRATCH/lvs.out" "$GDS_SHA" "$PIN_PAR" "$INPUT_REV" "$REF_NAME" "$REF_SHA" "$EXPORT_REV" "$CDL_PATH" "$PIN_CDL" <<'PY' | python3 -I "$REPO/flow/record_lib.py" write "$STAGE/lvs.json" "$SCRATCH/subs.json"
import json, sys

src, gds_sha, pin_par, input_rev = sys.argv[1:5]
ref_name, ref_sha, export_rev, cdl_path, cdl_sha = sys.argv[5:10]
d = json.load(open(src, encoding="utf-8"))
d["core_flow"] = {
    "note": "klt lvs of the committed routed GDS against the routed gate-level "
            "netlist of the same route (reference.form gate-level-verilog, "
            "cells expanded to the pinned cell CDL) on the pinned ASAP7 "
            "extraction deck, with options.finfet_bulk nmos=VSS pmos=VDD "
            "(decision 0005) and flatten_layout; predictive PDK, a tool result "
            "never a silicon claim. A mismatch report is a recorded outcome: "
            "nothing is filtered, relaxed or suppressed.",
    "predicted": True,
    "input_gds": {"path": "layout/cve2_top.gds", "sha256": gds_sha,
                  "top_cell": "cve2_rv32imc_wrapper"},
    "input_pin": {"record": pin_par, "at_commit": input_rev[:12]},
    "reference": {
        "form": "gate-level-verilog",
        "netlist": ref_name,
        "sha256": ref_sha,
        "note": "Routed netlist of the committed route, taken from the bundle "
                "flow/core/par.sh --check --export publishes; its manifest "
                "names the committed GDS digest and the input netlist the "
                "par record pins.",
        "routed_export": {"input_rev": export_rev, "gds_sha256": gds_sha},
    },
    "pin_order_source": {"path": cdl_path, "sha256": cdl_sha},
}
print(json.dumps(d))
PY

# One `klt version` ask, the spelling the shared provenance rows record; klt
# has already run successfully by this point, so this only echoes a version.
KLT_V="$("${KLT[@]}" version 2>&1 | head -1 || true)"
{
  provenance_rows flow/core/lvs.sh "$KLT_V"
  echo "pinned_lvs_deck: $PIN_LVS_DECK  (deck asap7, decision 0013)"
  echo "gds:          layout/cve2_top.gds  sha256:$GDS_SHA  (blob at HEAD ${INPUT_REV:0:12})"
  echo "input_pin:    $PIN_PAR  (core_flow.gds.sha256 equals the checked blob)"
  echo "reference:    $REF_NAME  sha256:$REF_SHA  (routed netlist from the par.sh --export bundle at input_rev ${EXPORT_REV:0:12})"
  echo "cell_cdl:     sha256:$PIN_CDL  ($CDL_PATH, reference.pin_order_files)"
} >"$STAGE/tool-versions.txt"

record_leak_guard "$STAGE"

# ---- publish dated record --------------------------------------------------
# Records only: each file is installed exclusively (flow/core/record_publish.sh:
# the copy is finished under a private name and linked to its final pathname
# without replacement, so nothing existing is overwritten and a copy that
# fails partway leaves no record behind), and a failure removes exactly what
# this run created.
CREATED=()
OUT_MADE=0
[[ -d "$OUT" ]] || OUT_MADE=1
publish_rollback() {
  local f
  for f in ${CREATED[@]+"${CREATED[@]}"}; do rm -f "$f"; done
  if [[ $OUT_MADE == 1 ]]; then rmdir "$OUT" 2>/dev/null || true; fi
  return 0
}
publish() {
  mkdir -p "$OUT" || return 1
  record_publish "$STAGE" "$OUT" lvs.json tool-versions.txt || return 1
  ( record_leak_guard "$OUT" ) || return 1
}
if ! publish; then
  publish_rollback
  die "publishing the record failed; nothing was left published, retry the run" 1
fi

# ---- summary ----------------------------------------------------------------
echo "lvs.sh: records -> flow/core/records/$DATE" >&2
python3 -I - "$OUT/lvs.json" <<'PY' >&2
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
counts = d.get("counts") or {}
pc = d.get("power_connectivity") or {}
print(f"lvs.sh: status={d.get('status')} error_count={d.get('error_count')} "
      f"mismatch_count={d.get('mismatch_count')} power_connectivity.status={pc.get('status')}")
print("  pins: layout {} reference {} matched {}".format(
    (counts.get("pins") or {}).get("layout"), (counts.get("pins") or {}).get("reference"),
    (counts.get("pins") or {}).get("matched")))
for cat, n in sorted((d.get("category_counts") or {}).items(), key=lambda kv: -kv[1]):
    print(f"  {cat}: {n}")
PY
