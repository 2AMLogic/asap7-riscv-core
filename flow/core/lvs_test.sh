#!/usr/bin/env bash
# Self-test for flow/core/lvs.sh, the core LVS driver (T1 item 4).
#
# Needs no PDK, no klt, no network and no GDS: it checks the driver's
# refusal contract (usage, a missing bundle, a checkout or cell CDL that is
# not at the pin, no committed GDS, no committed par record, a moved GDS the
# par pin does not name, a bundle that was not exported against the committed
# GDS, routed from the pinned netlist, or does not hash to its own manifest,
# records already existing for the date), the klt invocation's invariants
# (engine klayout, deck asap7, the committed GDS blob as the layout, the
# bundle's routed netlist as a gate-level-verilog reference, the pinned CDL
# as pin-order source, decision 0005's bulk policy and flatten_layout), the
# report validation (deck pin, layout and reference hashes, reference form,
# echoed bulk policy and its disclosure, a verdict), and the staging +
# publication invariants in a scratch fixture repository with a stubbed klt
# (record published with the input pins written, redaction of host paths
# before anything is published, nothing published by a failed or refused
# run, the append-only refusal on a second run).
#
# ASAP7 is a predictive PDK; nothing here is fabricated or measured, and
# this script makes no claim about any design.
#
# usage: flow/core/lvs_test.sh
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

has() {  # label pattern file
  if grep -q -- "$2" "$3" 2>/dev/null; then ok "$1"; else no "$1: '$2' not in $3"; fi
}

TOP=cve2_rv32imc_wrapper
W="$(mktemp -d "${TMPDIR:-/tmp}/asap7-lvstest.XXXXXX")" || exit 1
cleanup() { rm -rf "$W"; }
trap cleanup EXIT

# ---- fixture tools ------------------------------------------------------------
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
# The stub answers `version`, and for `lvs <request> --format json` it
# copies the request to $STUB_REQ_COPY, writes a report whose layout,
# reference, pin-order and option fields echo the request and whose hashes
# are the hashes of the files the request names, and exits $STUB_KLT_RC.
# The STUB_* knobs below bend one field each, to exercise the validation.
cat >"$BIN/stub-klt" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "version" ]]; then
  echo "klt 0.9.0"
  exit 0
fi
if [[ "${1:-}" == "lvs" ]]; then
  if [[ -n "${STUB_REQ_COPY:-}" ]]; then cp -- "$2" "$STUB_REQ_COPY"; fi
  if [[ -n "${STUB_SQUAT_FILE:-}" ]]; then
    mkdir -p -- "$(dirname -- "$STUB_SQUAT_FILE")"
    printf '%s' "${STUB_SQUAT_CONTENT:-}" >"$STUB_SQUAT_FILE"
  fi
  python3 -I - "$@" <<'PY'
import hashlib, json, os, sys

assert sys.argv[3:] == ["--format", "json"], sys.argv
req = json.load(open(sys.argv[2]))
env = os.environ


def sha(path):
    return hashlib.sha256(open(path, "rb").read()).hexdigest()


if env.get("STUB_ERROR"):
    print(json.dumps({"schema_version": 1,
                      "error": {"command": "lvs", "message": "stub failure"}}))
    sys.exit(0)

report = {
    "status": env.get("STUB_STATUS", "match"),
    "error_count": 0,
    "mismatch_count": 2,
    "counts": {"devices": {"layout": 4, "reference": 4, "matched": 4},
               "nets": {"layout": 5, "reference": 5, "matched": 5},
               "pins": {"layout": 4, "reference": 4, "matched": 4}},
    "mismatches": [{"category": "device.finfet_bulk_tied", "severity": "warning"}],
    "category_counts": {"device.finfet_bulk_tied": 2},
    "options": {
        "finfet_bulk": json.loads(env.get("STUB_POLICY", '{"nmos":"VSS","pmos":"VDD"}')),
        "flatten_layout": req["options"].get("flatten_layout"),
        "flatten_reference": True,
    },
    "reference_conversion": {
        "form": env.get("STUB_FORM", "gate-level-verilog"),
        "pin_order_files": req["reference"].get("pin_order_files", []),
    },
    "environment": {
        "engine": "klayout",
        "engine_version": "0.30.12",
        "layout_sha256": env.get("STUB_LAYOUT_SHA", "sha256:" + sha(req["layout"]["file"])),
        "reference_sha256": env.get("STUB_REF_SHA", "sha256:" + sha(req["reference"]["netlist"])),
    },
    "power_connectivity": {"status": "unchecked", "finding_count": 0,
                           "findings": [], "reason": "stub"},
    "provenance": {
        "deck": {"content_hash": env.get("STUB_DECK", "sha256:" + env["STUB_DECK_SHA"]),
                 "name": "asap7", "released": True},
        "input": {"content_hash": "sha256:" + sha(req["layout"]["file"]), "role": "layout"},
        "klt_version": "0.9.0",
        "pin_order_sources": [{"path": p, "cells": 208}
                              for p in req["reference"].get("pin_order_files", [])],
    },
    "layout": req["layout"]["file"],
    "reference": req["reference"]["netlist"],
    "top": req["layout"]["top"],
    "reference_top": req["reference"]["top"].upper(),
    "schema_version": 2,
}
if env.get("STUB_NO_BULK"):
    report["category_counts"] = {}
    report["mismatches"] = []
if env.get("STUB_LEAK"):
    report["file"] = "/home/leak/x.gds"
print(json.dumps(report))
PY
  exit "${STUB_KLT_RC:-0}"
fi
exit 2
STUB
chmod +x "$BIN/uvx" "$BIN/yosys" "$BIN/stub-klt"

# ---- fixture checkout at the pins ---------------------------------------------
FA="$W/asap7"
mkdir -p "$FA/asap7sc7p5t_28/CDL/LVS" "$FA/asap7_pdk_r1p7"
printf '.SUBCKT stub cell CDL\n' >"$FA/asap7sc7p5t_28/CDL/LVS/asap7sc7p5t_28_R.cdl"
CDL_SHA="$(sha256sum "$FA/asap7sc7p5t_28/CDL/LVS/asap7sc7p5t_28_R.cdl" | cut -d' ' -f1)"
for sub in "$FA/asap7sc7p5t_28" "$FA/asap7_pdk_r1p7" "$FA"; do
  git init -q "$sub"
  git -C "$sub" -c user.email=t@t -c user.name=t commit -q --allow-empty -m pin
done
SHA_UP="$(git -C "$FA" rev-parse HEAD)"
SHA_CELLS="$(git -C "$FA/asap7sc7p5t_28" rev-parse HEAD)"
SHA_PDK="$(git -C "$FA/asap7_pdk_r1p7" rev-parse HEAD)"

# ---- fixture repository ----------------------------------------------------------
FX="$W/repo"
mkdir -p "$FX/flow/core/records" "$FX/spec" "$FX/layout" "$FX/flow/core"
cp "$REPO/flow/lib.sh" "$REPO/flow/record_lib.py" "$FX/flow/"
cp "$REPO/flow/core/lvs.sh" "$REPO/flow/core/record_publish.sh" "$FX/flow/core/"
chmod +x "$FX/flow/core/lvs.sh"
cat >"$FX/spec/pdk-bringup.md" <<EOF
| Item | Pin |
| Upstream repo | fake $SHA_UP |
| Cell library | fake $SHA_CELLS |
| PDK (DRM | fake $SHA_PDK |

| File | sha256 |
|---|---|
| \`asap7sc7p5t_28/CDL/LVS/asap7sc7p5t_28_R.cdl\` | \`$CDL_SHA\` |
EOF
# The LVS deck is the pinned build's own \`asap7\` deck: the spec pins it by
# hash alone, and the report is validated against that hash.
DECK_SHA="$(printf 'fixture asap7 extraction deck\n' | sha256sum | cut -d' ' -f1)"
cat >"$FX/spec/core.md" <<EOF
- \`klt\`: release \`klayout-tools==0.9.0\` is the pinned release for DRC, LVS and the smoke flow.
- **"LVS clean" means:** \`klt lvs\` status \`match\`, with the layout hash,
  reference hash and deck hash recorded, the report's \`provenance.deck.content_hash\`
  equal to the pinned LVS deck hash:
  \`sha256:$DECK_SHA\`
EOF

fx_commit() {  # commit the fixture working tree
  git -C "$FX" add -A
  git -C "$FX" -c user.email=t@t -c user.name=t commit -q -m "$1"
}
git init -q "$FX"
fx_commit "empty fixture"

# ---- fixture routed export bundle -----------------------------------------------
# What flow/core/par.sh --check --export publishes: the routed netlist beside a
# manifest that names the committed GDS and the input netlist of the route.
EXPORT="$W/export"; mkdir -p "$EXPORT"
printf 'module %s; endmodule\n' "$TOP" >"$EXPORT/$TOP.v"
REF_SHA="$(sha256sum "$EXPORT/$TOP.v" | cut -d' ' -f1)"
printf 'stub def\n' >"$EXPORT/$TOP.def"
BUNDLE_REV="0000000000000000000000000000000000000000"
NL_PATH=flow/core/records/2026-11-20/netlist.v
NL_SHA="$(printf 'stub synthesized netlist\n' | sha256sum | cut -d' ' -f1)"
cat >"$W/manifest.py" <<'PY'
import hashlib, json, os, sys

export, top, gds_sha, nl_path, nl_sha, rev = sys.argv[1:7]
args = sys.argv[7:]
def sha(name):
    return hashlib.sha256(open(os.path.join(export, name), "rb").read()).hexdigest()
m = {
    "schema_version": 1,
    "top_cell": top,
    "input_rev": rev,
    "input_netlist": {"path": nl_path, "sha256": nl_sha},
    "gds": {"path": "layout/cve2_top.gds", "sha256": gds_sha},
    "artifacts": [{"filename": n, "sha256": sha(n)} for n in sorted(os.listdir(export))],
}
for a in args:
    key, value = a.split("=", 1)
    if key == "top_cell":
        m["top_cell"] = value
    elif key == "gds_sha":
        m["gds"]["sha256"] = value
    elif key == "nl_path":
        m["input_netlist"]["path"] = value
    elif key == "nl_sha":
        m["input_netlist"]["sha256"] = value
    elif key == "drop_netlist":
        m["artifacts"] = [x for x in m["artifacts"] if x["filename"] != top + ".v"]
    else:
        sys.exit("unknown manifest knob " + key)
with open(os.path.join(export, "manifest.json"), "w", encoding="utf-8") as f:
    json.dump(m, f, indent=2, sort_keys=True)
    f.write("\n")
PY
manifest() {  # write the bundle's manifest.json for the current GDS pin; knobs key=value
  python3 -I "$W/manifest.py" "$EXPORT" "$TOP" "${GDS_SHA:-}" "$NL_PATH" "$NL_SHA" "$BUNDLE_REV" "$@"
}

FXDATE=2026-11-28
run_lvs() {  # the fixture driver with the stub klt, the bundle and the pinned knobs
  RECORD_DATE="$FXDATE" KLT_CMD="$BIN/stub-klt" STUB_DECK_SHA="$DECK_SHA" \
    PATH="$BIN:$PATH" bash "$FX/flow/core/lvs.sh" "$FA" "$EXPORT"
}
REC="$FX/flow/core/records/$FXDATE"

# ---- refusals (nothing written) --------------------------------------------------
out="$W/usage.err"; rc=0
( RECORD_DATE="$FXDATE" KLT_CMD="$BIN/stub-klt" PATH="$BIN:$PATH" bash "$FX/flow/core/lvs.sh" "$FA" ) >"$out" 2>&1 || rc=$?
eq "a missing export directory refuses (exit 2)" 2 "$rc"
has "the usage refusal names the two arguments" "usage: flow/core/lvs.sh <asap7-checkout> <routed-export-dir>" "$out"

git init -q "$W/othercommit"
git -C "$W/othercommit" -c user.email=t@t -c user.name=t commit -q --allow-empty -m other
out="$W/notapin.err"; rc=0
( RECORD_DATE="$FXDATE" KLT_CMD="$BIN/stub-klt" PATH="$BIN:$PATH" bash "$FX/flow/core/lvs.sh" "$W/othercommit" "$EXPORT" ) >"$out" 2>&1 || rc=$?
eq "a checkout that is not at the pin refuses (exit 2)" 2 "$rc"
has "the not-at-pin refusal names the pin" "spec/pdk-bringup.md pins $SHA_UP" "$out"

cp -r "$FA" "$W/badcdl"
printf '.SUBCKT another cell CDL\n' >"$W/badcdl/asap7sc7p5t_28/CDL/LVS/asap7sc7p5t_28_R.cdl"
out="$W/badcdl.err"; rc=0
( RECORD_DATE="$FXDATE" KLT_CMD="$BIN/stub-klt" PATH="$BIN:$PATH" bash "$FX/flow/core/lvs.sh" "$W/badcdl" "$EXPORT" ) >"$out" 2>&1 || rc=$?
eq "a cell CDL that is not at the pin refuses (exit 2)" 2 "$rc"
has "the CDL refusal names the pin" "not the pin $CDL_SHA" "$out"
rm -rf "$W/badcdl"

out="$W/nogds.err"; rc=0
( run_lvs ) >"$out" 2>&1 || rc=$?
eq "no committed GDS refuses (exit 2)" 2 "$rc"
has "no-GDS refusal names the missing blob" "no committed HEAD:layout/cve2_top.gds" "$out"

printf 'fixture-gds-v1' >"$FX/layout/cve2_top.gds"
fx_commit "GDS but no par record"
GDS_SHA="$(sha256sum "$FX/layout/cve2_top.gds" | cut -d' ' -f1)"
out="$W/nopar.err"; rc=0
( run_lvs ) >"$out" 2>&1 || rc=$?
eq "no committed par record refuses (exit 2)" 2 "$rc"
has "no-par refusal names the missing pin" "nothing pins the GDS" "$out"

mkdir -p "$FX/flow/core/records/2026-11-22"
cat >"$FX/flow/core/records/2026-11-22/par.json" <<EOF
{"core_flow":{"gds":{"path":"layout/cve2_top.gds","sha256":"not-the-blob-sha"},
  "input_netlist":{"path":"$NL_PATH","sha256":"$NL_SHA"}}}
EOF
fx_commit "par record pinning a different GDS"
out="$W/pinmove.err"; rc=0
( run_lvs ) >"$out" 2>&1 || rc=$?
eq "a GDS the par pin does not name refuses (exit 1)" 1 "$rc"
has "moved-input refusal names the pin mismatch" "input pin mismatch" "$out"

cat >"$FX/flow/core/records/2026-11-22/par.json" <<EOF
{"core_flow":{"gds":{"path":"layout/cve2_top.gds","sha256":"$GDS_SHA"},
  "input_netlist":{"path":"$NL_PATH","sha256":"$NL_SHA"}}}
EOF
fx_commit "par record pinning the fixture GDS and netlist"

bundle_refuses() {  # <label> <expected-pattern> <manifest knobs...>: a bundle that does not describe the route
  local label="$1" pattern="$2"; shift 2
  manifest "$@"
  out="$W/bundle.$NBAD.$NPASS.err"; rc=0
  ( run_lvs ) >"$out" 2>&1 || rc=$?
  eq "$label refuse (exit 2)" 2 "$rc"
  has "$label refusal names the cause" "$pattern" "$out"
}
rm -f "$EXPORT/manifest.json"
out="$W/nomanifest.err"; rc=0
( run_lvs ) >"$out" 2>&1 || rc=$?
eq "a bundle without a manifest refuses (exit 2)" 2 "$rc"
has "no-manifest refusal names the manifest" "cannot read the export bundle's manifest" "$out"
bundle_refuses "a bundle exported against another GDS" "exported against GDS" gds_sha=0000000000000000000000000000000000000000000000000000000000000000
bundle_refuses "a bundle routed from another netlist" "routed from" nl_sha=0000000000000000000000000000000000000000000000000000000000000000
bundle_refuses "a bundle routed from another netlist path" "routed from" nl_path=flow/core/records/1999-01-01/netlist.v
bundle_refuses "a bundle with another top cell" "top_cell" top_cell=some_other_top
bundle_refuses "a bundle that lists no routed netlist" "lists no cve2_rv32imc_wrapper.v artifact" drop_netlist=1
manifest
cp "$EXPORT/$TOP.v" "$W/keep.v"
printf 'module tampered; endmodule\n' >"$EXPORT/$TOP.v"
out="$W/tampered.err"; rc=0
( run_lvs ) >"$out" 2>&1 || rc=$?
eq "a routed netlist that is not the manifest's bytes refuses (exit 2)" 2 "$rc"
has "the tampered-netlist refusal names the manifest digest" "not the manifest's sha256:$REF_SHA" "$out"
cp "$W/keep.v" "$EXPORT/$TOP.v"

mkdir -p "$REC"
printf '{"squat.json": true}\n' >"$REC/squat.json"
out="$W/exists.err"; rc=0
( run_lvs ) >"$out" 2>&1 || rc=$?
eq "records already existing for the date refuse (exit 2)" 2 "$rc"
rm "$REC/squat.json"
fx_commit "date directory free again" >/dev/null 2>&1 || true

# ---- happy path with the stub klt ---------------------------------------------
REQ="$W/lvs-request.json"
out="$W/ok.out"; rc=0
( STUB_REQ_COPY="$REQ" run_lvs ) >"$out" 2>&1 || rc=$?
eq "a usable report records cleanly (exit 0)" 0 "$rc"
if [[ -s "$REQ" ]]; then
  r() { python3 -I -c "import json,sys; d=json.load(open(sys.argv[1])); print($1)" "$REQ"; }
  eq "the request names the KLayout engine" klayout "$(r 'd["engine"]')"
  eq "the layout deck is the pinned asap7 extraction deck" asap7 "$(r 'd["layout"]["deck"]')"
  eq "the layout top is the wrapper" "$TOP" "$(r 'd["layout"]["top"]')"
  eq "the layout file is the wrapper GDS copied into the driver's scratch" "$TOP.gds" \
    "$(r 'd["layout"]["file"].rsplit("/", 1)[1]')"
  eq "the reference is a gate-level Verilog netlist" gate-level-verilog "$(r 'd["reference"]["form"]')"
  eq "the reference top is the wrapper" "$TOP" "$(r 'd["reference"]["top"]')"
  eq "the reference file is the wrapper's routed netlist copied into the driver's scratch" "$TOP.v" \
    "$(r 'd["reference"]["netlist"].rsplit("/", 1)[1]')"
  eq "the pin-order source is the pinned cell CDL" "['$FA/asap7sc7p5t_28/CDL/LVS/asap7sc7p5t_28_R.cdl']" "$(r 'd["reference"]["pin_order_files"]')"
  eq "options.finfet_bulk is decision 0005's recorded policy" "{'nmos': 'VSS', 'pmos': 'VDD'}" "$(r 'd["options"]["finfet_bulk"]')"
  eq "options.flatten_layout is set" True "$(r 'd["options"]["flatten_layout"]')"
  eq "the request sets no other option" "['finfet_bulk', 'flatten_layout']" "$(r 'sorted(d["options"])')"
else
  no "the stub captured the request"
fi

if [[ -s "$REC/lvs.json" && -s "$REC/tool-versions.txt" ]]; then
  ok "the dated record and tool-versions are published"
else
  no "the dated record and tool-versions are published"
fi
j() {  # jq-style extraction via python: j <py-expr over d>
  python3 -I -c "import json,sys; d=json.load(open(sys.argv[1])); print($1)" "$REC/lvs.json"
}
eq "the record pins the checked GDS blob by sha256" "$GDS_SHA" "$(j 'd["core_flow"]["input_gds"]["sha256"]')"
eq "the report's layout hash is the committed GDS blob (the stub hashes the file the request names)" \
  "sha256:$GDS_SHA" "$(j 'd["environment"]["layout_sha256"]')"
eq "the report's reference hash is the bundle's routed netlist" "sha256:$REF_SHA" "$(j 'd["environment"]["reference_sha256"]')"
eq "the record names the par record that pins the GDS" "flow/core/records/2026-11-22/par.json" \
  "$(j 'd["core_flow"]["input_pin"]["record"]')"
eq "the record pins the routed netlist by sha256" "$REF_SHA" "$(j 'd["core_flow"]["reference"]["sha256"]')"
eq "the record names the routed netlist's bundle revision" "$BUNDLE_REV" "$(j 'd["core_flow"]["reference"]["routed_export"]["input_rev"]')"
eq "the record pins the CDL by sha256" "$CDL_SHA" "$(j 'd["core_flow"]["pin_order_source"]["sha256"]')"
eq "the report's status is carried through unfiltered" match "$(j 'd["status"]')"
eq "the report's layout path is redacted to the scratch tag" "<scratch>/work/$TOP.gds" "$(j 'd["layout"]')"
eq "the report's pin-order path is redacted to the checkout tag" \
  "<asap7-checkout>/asap7sc7p5t_28/CDL/LVS/asap7sc7p5t_28_R.cdl" "$(j 'd["provenance"]["pin_order_sources"][0]["path"]')"
if grep -qF -- "$W" "$REC/lvs.json" || grep -qF -- "/tmp/" "$REC/lvs.json"; then
  no "the record names no host path"
else
  ok "the record names no host path"
fi
if grep -q "klt:" "$REC/tool-versions.txt" && grep -q "pinned_lvs_deck:" "$REC/tool-versions.txt" \
  && grep -q "reference:    $TOP.v  sha256:$REF_SHA" "$REC/tool-versions.txt"; then
  ok "tool-versions carries the shared klt row, the deck pin row and the reference row"
else
  no "tool-versions carries the shared klt row, the deck pin row and the reference row"
fi
has "the summary names the status and the power-connectivity status" "power_connectivity.status=unchecked" "$out"

# ---- append-only: a second run for the same date refuses ----------------------
out="$W/again.err"; rc=0
( run_lvs ) >"$out" 2>&1 || rc=$?
eq "a second run for the same date refuses (exit 2)" 2 "$rc"
rm -rf "$REC"

# ---- a report that is not the acceptance check publishes nothing -----------------
# Each knob bends one validated field; every one must exit 1, name the field,
# and leave no record behind.
bad_report() {  # <label> <pattern> <STUB_VAR=value>...
  local label="$1" pattern="$2"; shift 2
  out="$W/bad.$NBAD.$NPASS.err"; rc=0
  ( for kv in "$@"; do export "${kv?}"; done; run_lvs ) >"$out" 2>&1 || rc=$?
  eq "$label: refuses (exit 1)" 1 "$rc"
  has "$label: the refusal names the cause" "$pattern" "$out"
  if [[ ! -e "$REC/lvs.json" ]]; then
    ok "$label: no record is published"
  else
    no "$label: no record is published"
  fi
}
bad_report "a report naming another deck" "expected the pin" STUB_DECK=sha256:0000000000000000000000000000000000000000000000000000000000000000
bad_report "an inconclusive compare (no verdict)" "no verdict was reached" STUB_STATUS=inconclusive
bad_report "a report about another layout" "the checked GDS blob" STUB_LAYOUT_SHA=sha256:0000000000000000000000000000000000000000000000000000000000000000
bad_report "a report about another reference" "the routed netlist" STUB_REF_SHA=sha256:0000000000000000000000000000000000000000000000000000000000000000
bad_report "a report whose reference is not gate-level" "expected 'gate-level-verilog'" STUB_FORM=plain-element
bad_report "a report that does not echo the bulk policy" "the recorded policy" STUB_POLICY='{"nmos":"VDD","pmos":"VSS"}'
bad_report "a report that does not disclose the bulk tie" "not disclosed" STUB_NO_BULK=1
out="$W/leak.err"; rc=0
( STUB_LEAK=1 run_lvs ) >"$out" 2>&1 || rc=$?
eq "a report leaking a host path refuses (exit 1)" 1 "$rc"
if [[ ! -e "$REC/lvs.json" ]]; then
  ok "the leaking run published no record"
else
  no "the leaking run published no record"
fi

out="$W/kltfail.err"; rc=0
( STUB_ERROR=1 run_lvs ) >"$out" 2>&1 || rc=$?
eq "a klt lvs application error refuses (exit 1)" 1 "$rc"
has "the klt failure is reported with its message" "klt lvs failed" "$out"
if [[ ! -e "$REC/lvs.json" ]]; then
  ok "the failed klt run published no record"
else
  no "the failed klt run published no record"
fi

# ---- a usable report after the refused ones still records ----------------------
out="$W/retry.out"; rc=0
( run_lvs ) >"$out" 2>&1 || rc=$?
eq "the same date records cleanly once the report is valid (exit 0)" 0 "$rc"
eq "the date holds exactly the two records" "lvs.json tool-versions.txt" \
  "$(ls -A "$REC" | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//')"

echo "$NPASS passed, $NBAD failed"
((NBAD == 0))
