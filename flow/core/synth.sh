#!/usr/bin/env bash
# Core synthesis flow: fetch the pinned CVE2 closure (hash-checked), convert it
# with the pinned sv2v, and run `klt synthesize` of the RV32IMC wrapper against
# the ratified RVT-only asap7sc7p5t_28 SS Liberty. Writes the gate-level netlist
# and the synthesis record under flow/core/records/<date>/, or, with --check,
# regenerates the netlist and byte-compares it with the latest committed one.
#
# ASAP7 is a predictive PDK; nothing here is fabricated or measured. Synthesis
# claims no timing: the clock constraint is passed to the tool and the report's
# `timing` field is null.
#
# usage: flow/core/synth.sh <asap7-checkout>            write a new dated record
#        flow/core/synth.sh <asap7-checkout> --check    regenerate and compare
#        (the checkout may be given as $ASAP7_DIR instead of an argument)
#
# <asap7-checkout> is The-OpenROAD-Project/asap7 at the pin in
# spec/pdk-bringup.md section 1; only the asap7sc7p5t_28 submodule is read, at
# its pinned commit. The script refuses any other checkout.
#
# Environment:
#   RECORD_DATE   record directory name (default: today, UTC). The script
#                 refuses to write into a directory that already has records.
#   KLT_CMD       klt to run (default: the release pinned in spec/core.md, via uvx)
#   SV2V          sv2v binary (default: the pinned release, downloaded into
#                 flow/build/sv2v and checked against its pinned sha256)
#   KEEP_SCRATCH=1  keep the scratch directory
#
# Exit status: 0 ok (and, with --check, byte-identical); 1 a step failed or
# --check found a difference; 2 refused invocation.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=flow/lib.sh
source "$REPO/flow/lib.sh"
TOP=cve2_rv32imc_wrapper
WRAPPER="$REPO/rtl/$TOP.sv"
CELL_LIB=asap7sc7p5t_28_RVT
CORNER=SS

CHECK=0
ARGS=()
for a in "$@"; do
  case "$a" in
    --check) CHECK=1 ;;
    -*) die "unknown option: $a" ;;
    *) ARGS+=("$a") ;;
  esac
done
[[ ${#ARGS[@]} -le 1 ]] || die "usage: flow/core/synth.sh [<asap7-checkout>] [--check]"
ASAP7_ARG="${ARGS[0]:-${ASAP7_DIR:-}}"
[[ -n "$ASAP7_ARG" ]] || die "usage: flow/core/synth.sh <asap7-checkout> [--check] (or set ASAP7_DIR)"
[[ -d "$ASAP7_ARG" ]] || die "not a directory: $ASAP7_ARG"
ASAP7="$(cd "$ASAP7_ARG" && pwd)"

# ---- pins, read from the spec -------------------------------------------
PIN_UPSTREAM="$(spec_sha 'Upstream repo')"
PIN_CELLS="$(spec_sha 'Cell library')"
PIN_KLT="$(grep -o 'klayout-tools==[0-9][0-9.]*' "$REPO/spec/core.md" | head -1)"
PIN_SV2V="$(grep -o 'sv2v v[0-9][0-9.]*' "$REPO/spec/core.md" | head -1 | cut -d' ' -f2)"
PIN_SV2V_SHA="$(grep -A2 'zachjs/sv2v' "$REPO/spec/core.md" | grep -o '[0-9a-f]\{64\}' | head -1)"
for v in PIN_UPSTREAM PIN_CELLS PIN_KLT PIN_SV2V PIN_SV2V_SHA; do
  [[ -n "${!v}" ]] || die "could not read $v from spec/" 1
done

check_pin "$ASAP7" "$PIN_UPSTREAM" "upstream asap7"
check_pin "$ASAP7/asap7sc7p5t_28" "$PIN_CELLS" "submodule asap7sc7p5t_28"

read -r -a KLT <<<"${KLT_CMD:-uvx --quiet --from $PIN_KLT klt}"
BUILD="$REPO/flow/build"
setup_scratch core

# ---- output directory (never overwrite) ---------------------------------
if [[ $CHECK == 0 ]]; then
  new_record_dir core
else
  DATE="${RECORD_DATE:-$(date -u +%Y-%m-%d)}"
  OUT="$REPO/flow/core/records/$DATE"
fi

# ---- 1. fetch, hash-checked ----------------------------------------------
UP="$SCRATCH/upstream"
"$REPO/flow/core/fetch.sh" "$UP" >&2

# ---- 2. pinned sv2v ---------------------------------------------------------
if [[ -z "${SV2V:-}" ]]; then
  SV2V="$BUILD/sv2v/$PIN_SV2V/sv2v-Linux/sv2v"
  if [[ ! -x "$SV2V" ]]; then
    mkdir -p "$BUILD/sv2v/$PIN_SV2V"
    zip="$BUILD/sv2v/$PIN_SV2V/sv2v-Linux.zip"
    curl -fsSL --retry 2 -o "$zip" "https://github.com/zachjs/sv2v/releases/download/$PIN_SV2V/sv2v-Linux.zip"
    [[ "$(sha256sum "$zip" | cut -d' ' -f1)" == "$PIN_SV2V_SHA" ]] || { rm -f "$zip"; die "sv2v-Linux.zip sha256 does not match the pin" 1; }
    python3 -I -c 'import sys, zipfile; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])' "$zip" "$BUILD/sv2v/$PIN_SV2V"
    chmod +x "$SV2V"
  fi
fi
SV2V_VERSION="$("$SV2V" --version)"
[[ "$SV2V_VERSION" == "sv2v $PIN_SV2V" ]] || die "sv2v reports '$SV2V_VERSION', spec/core.md pins $PIN_SV2V" 1

# ---- 3. SystemVerilog -> Verilog ------------------------------------------
# Same command as sky130-riscv-soc scripts/convert-cve2.sh, plus the wrapper.
# SYNTHESIS drops the simulation-only DPI export block in cve2_if_stage.sv.
W="$SCRATCH/work"; mkdir -p "$W"
PRIM=vendor/lowrisc_ip/ip/prim/rtl
(
  cd "$UP"
  mapfile -t REST < <(ls rtl/*.sv | grep -v -e cve2_pkg.sv -e cve2_core.sv -e cve2_top.sv | sort)
  "$SV2V" -DSYNTHESIS -I "$PRIM" -I rtl -I vendor/lowrisc_ip/dv/sv/dv_utils \
    "$PRIM/prim_assert.sv" rtl/cve2_pkg.sv "$PRIM/prim_ram_1p_pkg.sv" \
    "${REST[@]}" rtl/cve2_core.sv rtl/cve2_top.sv "$WRAPPER" \
    --top "$TOP" -w "$W/$TOP.v"
)
iverilog -g2012 -s "$TOP" -o "$W/$TOP.vvp" "$W/$TOP.v"
echo "synth.sh: sv2v + Icarus elaboration ok" >&2

# ---- 4. PDK overlay in scratch: merged RVT SS Liberty --------------------
PDK="$SCRATCH/pdk"; mkdir -p "$PDK/libs/$CELL_LIB"
build_liberty_overlay "$ASAP7" "$PDK" "$CELL_LIB" "$CORNER"

# ---- 5. klt synthesize ------------------------------------------------------
cat >"$W/synth.req.json" <<JSON
{"schema":"klt.synthesize.request/1","engine":"yosys","sources":["$TOP.v"],"hdl_toplevel":"$TOP",
 "pdk":{"cell_library":"$CELL_LIB","corner":"$CORNER"},"constraints":{"clock_period_ns":1.0}}
JSON
rc=0
( cd "$W" && "${KLT[@]}" synthesize synth.req.json --pdk asap7 --pdk-root "$PDK" --format json ) >"$SCRATCH/synth.out" 2>"$SCRATCH/synth.err" || rc=$?
python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if isinstance(d,dict) and "error" not in d else 1)' "$SCRATCH/synth.out" \
  || { echo "synth.sh: klt synthesize failed (exit $rc)" >&2; head -c 2000 "$SCRATCH/synth.out" "$SCRATCH/synth.err" >&2; exit 1; }
NETLIST="$(ls -t "$W"/.klt/synthesize/*/"${TOP}"_synth.v 2>/dev/null | head -1 || true)"
[[ -n "$NETLIST" ]] || die "klt synthesize produced no ${TOP}_synth.v" 1
# Yosys embeds the absolute path of the converted Verilog in some internal net
# names (sv2v function casts). Strip the scratch work dir so the committed
# netlist is independent of where the script ran; the name otherwise stays.
sed "s#$W/##g" "$NETLIST" >"$SCRATCH/netlist.v"
NETLIST="$SCRATCH/netlist.v"
! grep -q "$SCRATCH" "$NETLIST" || die "scratch path still present in netlist" 1

# ---- 6. compare (--check) or record ---------------------------------------
if [[ $CHECK == 1 ]]; then
  LATEST="$(ls -d "$REPO"/flow/core/records/*/ 2>/dev/null | sort | tail -1 || true)"
  [[ -n "$LATEST" && -f "$LATEST/netlist.v" ]] || { echo "synth.sh: no committed netlist to compare against" >&2; exit 1; }
  if cmp -s "$NETLIST" "$LATEST/netlist.v"; then
    echo "synth.sh: regenerated netlist is byte-identical to ${LATEST#"$REPO"/}netlist.v" >&2
    exit 0
  fi
  echo "synth.sh: regenerated netlist DIFFERS from ${LATEST#"$REPO"/}netlist.v" >&2
  exit 1
fi

cp "$NETLIST" "$OUT/netlist.v"

python3 -I - "$SCRATCH/synth.out" "$OUT/synth.json" "$(sha256sum "$NETLIST" | cut -d" " -f1)" "$SCRATCH" "$REPO" "$HOME" <<'PY'
import json, sys
src, dest, netlist_sha, *subs = sys.argv[1:]
tags = ["<scratch>", "<repo>", "<home>"]
def scrub(o):
    if isinstance(o, str):
        for s, t in zip(subs, tags):
            o = o.replace(s, t)
        return o
    if isinstance(o, list):
        return [scrub(x) for x in o]
    if isinstance(o, dict):
        return {k: scrub(v) for k, v in o.items()}
    return o
d = json.load(open(src))
d["netlist_sha256_as_emitted_by_klt"] = d.get("netlist_sha256")
d["netlist_sha256"] = netlist_sha
d["core_flow"] = {"note": "Synthesis of the RV32IMC wrapper around unmodified CVE2; predicted PDK, no timing claimed.", "predicted": True}
json.dump(scrub(d), open(dest, "w"), indent=2, sort_keys=True)
open(dest, "a").write("\n")
PY

sha() { sha256sum "$1" | cut -d' ' -f1; }
{
  echo "# Tool and input versions for flow/core/synth.sh (predictive PDK; nothing here is fabricated)"
  echo "klt:          $("${KLT[@]}" --version 2>&1 | head -1)  ($PIN_KLT)"
  echo "yosys:        $(yosys -V 2>&1 | head -1)"
  echo "sv2v:         $SV2V_VERSION  (release asset sha256 $PIN_SV2V_SHA; binary sha256 $(sha "$SV2V"))"
  echo "iverilog:     $(iverilog -V 2>&1 | head -1)"
  echo "py7zr:        $(uvx --quiet --from py7zr python -I -c 'import py7zr; print(py7zr.__version__)')"
  echo "cve2:         $(python3 -I -c 'import json,sys; print(next(i for i in json.load(open(sys.argv[1]))["imports"] if i["from"]=="openhwgroup/cve2")["commit"])' "$REPO/reuse.lock.json")"
  echo "reuse.lock.json: sha256:$(sha "$REPO/reuse.lock.json")"
  echo "wrapper:      sha256:$(sha "$WRAPPER")"
  echo "converted_verilog: sha256:$(sha "$W/$TOP.v")"
  echo "asap7:        $PIN_UPSTREAM"
  echo "asap7sc7p5t_28: $PIN_CELLS"
  echo "liberty_corner: RVT $CORNER (merged)  sha256:$(sha "$PDK/lib/${CELL_LIB}_$CORNER.lib")"
  echo "netlist:      sha256:$(sha "$OUT/netlist.v")"
} >"$OUT/tool-versions.txt"
echo "synth.sh: records -> flow/core/records/$DATE" >&2
