# shellcheck shell=bash
# Shared plumbing for the flow scripts (flow/smoke/run.sh, flow/core/synth.sh).
# Sourced, not executed. The caller sets REPO (the repository root) first.
#
# ASAP7 is a predictive PDK; nothing here is fabricated or measured.
#
# Every pin read here is anchored on a label and fails closed: it dies rather
# than returning an empty or position-dependent value, so a pin can never be
# silently wrong because a spec paragraph was reordered. Callers write
# `|| exit 1`, which holds whether or not errexit is set in the calling shell
# (die runs inside the caller's command substitution, so its exit leaves only
# that subshell) -- the same contract as verification/lib.sh's pin().
#
# flow/lib_test.sh checks those reads: the pins of record, that an unmatched
# label exits non-zero instead of yielding an empty pin, and that a reordered
# spec paragraph does not move a pin. It needs no PDK checkout and no klt.
#
# Provides:
#   die <msg> [rc]                       message prefixed with the script name, exit rc (default 2)
#   spec_sha <row-label>                 first 40-hex sha on the pdk-bringup.md row starting "| <label>"
#   spec_pin <label> <regex> [after]     first <regex> match on the first spec/core.md line containing
#                                        the literal <label>, or within <after> lines below it
#   spec_klt_pin                         the flow's klt pin from spec/core.md (e.g. klayout-tools==0.9.0)
#   klt_cmd <klt-pin>                    sets the KLT array to the pinned klt, KLT_CMD overriding it
#   check_pin <dir> <want-sha> <label>   refuse a checkout that is not at the pin
#   setup_scratch <name>                 sets SCRATCH (mktemp) and removes it on exit unless KEEP_SCRATCH=1
#   new_record_dir <subdir>              sets DATE and OUT=flow/<subdir>/records/<date>; refuses an
#                                        existing record set (records are append-only evidence)
#   build_liberty_overlay <asap7> <root> <cell-lib> <corner>...
#                                        extract and merge the RVT Liberty for each corner under
#                                        <root>/lib and write <root>/klt-pdk.json

die() { echo "$(basename "$0"): $*" >&2; exit "${2:-2}"; }

spec_sha() {  # first 40-hex sha on the first row of pdk-bringup.md starting with "| $1"
  local v
  v="$(grep -m1 "^| $1" "$REPO/spec/pdk-bringup.md" 2>/dev/null | grep -o '[0-9a-f]\{40\}' | head -1 || true)"
  [[ -n "$v" ]] || die "spec/pdk-bringup.md: no 40-hex sha on a row starting \"| $1\"" 1
  printf '%s\n' "$v"
}

spec_pin() {  # label regex [lines-after]
  # Label-anchored read of spec/core.md: find the first line containing the
  # literal $1, then take the first $2 match on that line or within the next
  # ${3:-0} lines. Anchoring on a label rather than on document order is what
  # keeps a pin correct when the spec's prose is reflowed or reordered -- the
  # read either finds the pin next to its own label or dies.
  local v
  v="$(grep -F -m1 -A"${3:-0}" -e "$1" "$REPO/spec/core.md" 2>/dev/null \
       | grep -o -e "$2" | head -1 || true)"
  [[ -n "$v" ]] || die "spec/core.md: no match for /$2/ on or within ${3:-0} line(s) below \"$1\"" 1
  printf '%s\n' "$v"
}

spec_klt_pin() {
  # The one klt the flow runs. spec/core.md states it as the pinned release for
  # DRC, LVS and the smoke flow (decision 0012), and core synthesis runs that
  # same release. `klt signoff` is a separate pin (0.8.0, decision 0008), read
  # by .github/workflows/signoff.yml and never here -- the two sit two lines
  # apart in one spec paragraph, so this read must not depend on their order.
  spec_pin 'pinned release for DRC, LVS and the smoke flow' 'klayout-tools==[0-9][0-9.]*'
}

klt_cmd() {  # klt-pin -- sets the KLT array
  # --quiet suppresses uvx's own resolve/install chatter on stderr. It is load
  # bearing, not cosmetic: flow/smoke/run.sh reads `klt version` with 2>&1 into
  # the klt_build.version field of every record, so uvx noise on a cold cache
  # would be recorded as the klt version. The repo's other uvx calls already
  # pass it. KLT_CMD overrides the whole command (verification/fv.sh sets it).
  # shellcheck disable=SC2034  # KLT is set for the sourcing script, not used here
  read -r -a KLT <<<"${KLT_CMD:-uvx --quiet --from $1 klt}"
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
