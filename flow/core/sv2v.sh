#!/usr/bin/env bash
# The one place the pinned sv2v is read, fetched, verified, and the CVE2 closure
# is converted. Shared by flow/core/synth.sh (synthesis), verification/core/setup.sh
# (fetch) and verification/core/archtest_common.py (architectural-test netlist), so the
# netlist that is verified is converted exactly as the netlist that is synthesized.
#
#   source flow/core/sv2v.sh; sv2v_ensure <build-dir>
#       Reads the pin from spec/core.md, sets PIN_SV2V, PIN_SV2V_SHA, SV2V and
#       SV2V_VERSION. Unless $SV2V is already set, downloads the pinned release
#       into <build-dir>/sv2v/<pin>/ (sha256-checked). Always asserts the version.
#       Exits 1 on any failure.
#
#   flow/core/sv2v.sh convert <sv2v> <upstream-dir> <wrapper.sv> <top> <out.v>
#       Converts the CVE2 closure under <upstream-dir> plus the wrapper.
#       -DSYNTHESIS drops the simulation-only DPI export block in cve2_if_stage.sv.
#       Same command as sky130-riscv-soc scripts/convert-cve2.sh, plus the wrapper.
_SV2V_REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

sv2v_ensure() {
  local build="$1" zip
  PIN_SV2V="$(grep -o 'sv2v v[0-9][0-9.]*' "$_SV2V_REPO/spec/core.md" | head -1 | cut -d' ' -f2)"
  PIN_SV2V_SHA="$(grep -A2 'zachjs/sv2v' "$_SV2V_REPO/spec/core.md" | grep -o '[0-9a-f]\{64\}' | head -1)"
  [[ -n "$PIN_SV2V" && -n "$PIN_SV2V_SHA" ]] || { echo "sv2v.sh: could not read the sv2v pin from spec/core.md" >&2; exit 1; }
  if [[ -z "${SV2V:-}" ]]; then
    SV2V="$build/sv2v/$PIN_SV2V/sv2v-Linux/sv2v"
    if [[ ! -x "$SV2V" ]]; then
      mkdir -p "$build/sv2v/$PIN_SV2V"
      zip="$build/sv2v/$PIN_SV2V/sv2v-Linux.zip"
      curl -fsSL --retry 2 -o "$zip" "https://github.com/zachjs/sv2v/releases/download/$PIN_SV2V/sv2v-Linux.zip" \
        || { rm -f "$zip"; echo "sv2v.sh: sv2v download failed" >&2; exit 1; }
      [[ "$(sha256sum "$zip" | cut -d' ' -f1)" == "$PIN_SV2V_SHA" ]] \
        || { rm -f "$zip"; echo "sv2v.sh: sv2v-Linux.zip sha256 does not match the pin" >&2; exit 1; }
      python3 -I -c 'import sys, zipfile; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])' "$zip" "$build/sv2v/$PIN_SV2V"
      chmod +x "$SV2V"
    fi
  fi
  SV2V_VERSION="$("$SV2V" --version)"
  [[ "$SV2V_VERSION" == "sv2v $PIN_SV2V" ]] \
    || { echo "sv2v.sh: sv2v reports '$SV2V_VERSION', spec/core.md pins $PIN_SV2V" >&2; exit 1; }
}

sv2v_convert() {  # sv2v upstream-dir wrapper top out
  local sv2v="$1" up="$2" wrapper="$3" top="$4" out="$5"
  local prim=vendor/lowrisc_ip/ip/prim/rtl
  (
    cd "$up"
    mapfile -t REST < <(ls rtl/*.sv | grep -v -e cve2_pkg.sv -e cve2_core.sv -e cve2_top.sv | sort)
    "$sv2v" -DSYNTHESIS -I "$prim" -I rtl -I vendor/lowrisc_ip/dv/sv/dv_utils \
      "$prim/prim_assert.sv" rtl/cve2_pkg.sv "$prim/prim_ram_1p_pkg.sv" \
      "${REST[@]}" rtl/cve2_core.sv rtl/cve2_top.sv "$wrapper" \
      --top "$top" -w "$out"
  )
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  set -euo pipefail
  case "${1:-}" in
    convert) [[ $# -eq 6 ]] || { echo "usage: sv2v.sh convert <sv2v> <upstream-dir> <wrapper.sv> <top> <out.v>" >&2; exit 2; }
             sv2v_convert "$2" "$3" "$4" "$5" "$6" ;;
    *) echo "usage: sv2v.sh convert <sv2v> <upstream-dir> <wrapper.sv> <top> <out.v>" >&2; exit 2 ;;
  esac
fi
