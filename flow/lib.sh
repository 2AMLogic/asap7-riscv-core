# shellcheck shell=bash
# Shared plumbing for the flow scripts (flow/smoke/run.sh, flow/core/synth.sh).
# Sourced, not executed. The caller sets REPO (the repository root) first.
#
# ASAP7 is a predictive PDK; nothing here is fabricated or measured.
#
# Provides:
#   die <msg> [rc]                       message prefixed with the script name, exit rc (default 2)
#   spec_sha <row-label>                 first 40-hex sha on the pdk-bringup.md row starting "| <label>"
#   check_pin <dir> <want-sha> <label>   refuse a checkout that is not at the pin
#   setup_scratch <name>                 sets SCRATCH (mktemp) and removes it on exit unless KEEP_SCRATCH=1
#   new_record_dir <subdir>              sets DATE and OUT=flow/<subdir>/records/<date>; refuses an
#                                        existing record set (records are append-only evidence)
#   record_subs <dest> <path>=<tag>...   write the host-path substitution list every record is
#                                        redacted with, for flow/record_lib.py
#   build_liberty_overlay <asap7> <root> <cell-lib> <corner>...
#                                        extract and merge the RVT Liberty for each corner under
#                                        <root>/lib and write <root>/klt-pdk.json

die() { echo "$(basename "$0"): $*" >&2; exit "${2:-2}"; }

spec_sha() {  # first 40-hex sha on the first row of pdk-bringup.md starting with "| $1"
  grep -m1 "^| $1" "$REPO/spec/pdk-bringup.md" | grep -o '[0-9a-f]\{40\}' | head -1
}

check_pin() {  # dir want label
  local got
  got="$(git -C "$1" rev-parse HEAD 2>/dev/null)" || die "$3: $1 is not a git checkout"
  [[ "$got" == "$2" ]] || die "$3 is at $got, spec/pdk-bringup.md pins $2"
}

setup_scratch() {  # name
  SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/asap7-$1.XXXXXX")"
  trap '[[ "${KEEP_SCRATCH:-0}" == 1 ]] || rm -rf "$SCRATCH"' EXIT
}

new_record_dir() {  # subdir (smoke|core)
  DATE="${RECORD_DATE:-$(date -u +%Y-%m-%d)}"
  OUT="$REPO/flow/$1/records/$DATE"
  if compgen -G "$OUT/*.json" >/dev/null; then
    die "records already exist in flow/$1/records/$DATE; set RECORD_DATE to a new label (records are append-only evidence)"
  fi
  mkdir -p "$OUT"
}

record_subs() {  # dest path=tag...
  # The one convention for naming the host paths a record may not contain: a
  # JSON array of "<path>=<tag>" strings, applied by flow/record_lib.py in the
  # order given, so a path that is a prefix of another is listed first.
  local dest="$1" sep="" p; shift
  {
    printf '['
    for p in "$@"; do printf '%s"%s"' "$sep" "$p"; sep=","; done
    printf ']'
  } >"$dest"
}

build_liberty_overlay() {  # asap7 root cell_lib corner...
  local asap7="$1" root="$2" cell_lib="$3" c sep=""; shift 3
  local libdir="$asap7/asap7sc7p5t_28/LIB/NLDM"
  mkdir -p "$root/lib/7z"
  # Liberty ships as .7z only (no 7z on the workers): extract with a throwaway py7zr env.
  uvx --quiet --from py7zr python -I - "$libdir" "$root/lib/7z" "$@" <<'PY'
import glob, sys, py7zr
src, dst, *corners = sys.argv[1:]
for corner in corners:
    for f in sorted(glob.glob(f"{src}/*_RVT_{corner}_nldm_*.lib.7z")):
        with py7zr.SevenZipFile(f) as z:
            z.extractall(dst)
PY
  for c in "$@"; do
    python3 -I "$REPO/flow/merge_lib.py" "$root/lib/${cell_lib}_$c.lib" "${cell_lib}_$c" "$root"/lib/7z/*_RVT_"$c"_nldm_*.lib
  done
  {
    printf '{"schema_version":1,"variant":"asap7","assets":{"libs_ref":"libs"},\n "liberty":{"%s":{' "$cell_lib"
    for c in "$@"; do printf '%s"%s":"lib/%s_%s.lib"' "$sep" "$c" "$cell_lib" "$c"; sep=","; done
    printf '}}}\n'
  } >"$root/klt-pdk.json"
}
