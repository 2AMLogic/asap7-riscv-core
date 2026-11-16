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
# flow/lib_test.sh checks those reads, and extract_rvt_liberty's counted
# fail-closed guard: the pins of record, that an unmatched label exits non-zero
# instead of yielding an empty pin, that a reordered spec paragraph does not
# move a pin, and that a corner with the wrong archive count dies before any
# extraction. It needs no PDK checkout, no klt and no network.
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
#   newest_record_with <root> <file>     newest directory under <root> holding <file> as a regular
#                                        file (trailing slash included); empty output, non-zero,
#                                        when none does
#   record_subs <dest> <path>=<tag>...   write the host-path substitution list every record is
#                                        redacted with, for flow/record_lib.py
#   record_leak_guard <record-dir>       die if any *.json in <dir> -- plus tool-versions.txt, when
#                                        present -- names a host path; fails closed on no *.json
#   extract_rvt_liberty <asap7> <dest> <corner>...
#                                        extract each requested corner's RVT Liberty archives from the
#                                        pinned checkout's LIB/NLDM into <dest>; dies with a counted
#                                        message unless every requested corner has exactly 5 archives
#   build_liberty_overlay <asap7> <root> <cell-lib> <corner>...
#                                        extract_rvt_liberty into <root>/lib/7z, then merge the RVT
#                                        Liberty for each corner under <root>/lib and write
#                                        <root>/klt-pdk.json

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

newest_record_with() {  # records-root filename -- print the newest directory holding filename
  # Record roots are heterogeneous: flow/core/records/ is written by both
  # synth.sh (netlist.v, synth.json, tool-versions.txt) and ff_simple_check.sh
  # (ff-simple-check.json alone), so "newest directory" is not the same
  # question as "newest record of the kind being looked for". Walk the
  # date-named directories newest-first and print the first holding <filename>
  # as a regular file, trailing slash included -- the form synth.sh's
  # ${LATEST#"$REPO"/} messages concatenate into. Empty output and a non-zero
  # status when nothing qualifies (or the root does not exist), so a caller can
  # refuse "nothing to compare against" distinctly from a failed comparison.
  local root="$1" want="$2" d
  [[ -d "$root" ]] || return 1
  local -a dirs=()
  readarray -t dirs < <(ls -d "$root"/*/ 2>/dev/null | sort -r)
  for d in "${dirs[@]}"; do
    if [[ -f "$d$want" ]]; then
      printf '%s\n' "$d"
      return 0
    fi
  done
  return 1
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

extract_rvt_liberty() {  # asap7 dest corner...
  # The RVT Liberty of the pinned asap7sc7p5t_28 checkout ships as .7z only (no
  # 7z binary on the workers): extract each requested corner's archives into
  # <dest> with a throwaway py7zr env. Fail closed with a counted message when
  # a requested corner does not have exactly 5 archives -- the five
  # asap7sc7p5t_28 groups (AO, INVBUF, OA, SEQ, SIMPLE) -- because an empty or
  # partial glob must never fall through as an unexpanded pattern into whatever
  # consumes <dest>. The expectation is 5 per corner requested, so a
  # single-corner caller is not wrong by construction.
  local asap7="$1" dest="$2" c n want=5; shift 2
  local libdir="$asap7/asap7sc7p5t_28/LIB/NLDM"
  for c in "$@"; do
    n="$(compgen -G "$libdir/*_RVT_${c}_nldm_*.lib.7z" | wc -l)" || true
    [[ "$n" == "$want" ]] \
      || die "expected $want RVT Liberty archives for corner $c in $libdir, found $n" 1
  done
  mkdir -p "$dest"
  uvx --quiet --from py7zr python -I - "$libdir" "$dest" "$@" <<'PY'
import glob, sys, py7zr
src, dst, *corners = sys.argv[1:]
for corner in corners:
    for f in sorted(glob.glob(f"{src}/*_RVT_{corner}_nldm_*.lib.7z")):
        with py7zr.SevenZipFile(f) as z:
            z.extractall(dst)
PY
}

build_liberty_overlay() {  # asap7 root cell_lib corner...
  # extract_rvt_liberty into <root>/lib/7z, then merge each corner's groups
  # into one Liberty per corner and write the klt-pdk.json naming them.
  local asap7="$1" root="$2" cell_lib="$3" c sep=""; shift 3
  extract_rvt_liberty "$asap7" "$root/lib/7z" "$@"
  for c in "$@"; do
    python3 -I "$REPO/flow/merge_lib.py" "$root/lib/${cell_lib}_$c.lib" "${cell_lib}_$c" "$root"/lib/7z/*_RVT_"$c"_nldm_*.lib
  done
  {
    printf '{"schema_version":1,"variant":"asap7","assets":{"libs_ref":"libs"},\n "liberty":{"%s":{' "$cell_lib"
    for c in "$@"; do printf '%s"%s":"lib/%s_%s.lib"' "$sep" "$c" "$cell_lib" "$c"; sep=","; done
    printf '}}}\n'
  } >"$root/klt-pdk.json"
}

record_leak_guard() {  # record-dir
  # The post-write check every core record directory must pass before the
  # script that wrote it exits: grep the *.json records -- plus
  # tool-versions.txt, when present -- for the four host-path roots and die
  # naming any file that matches. flow/smoke/run.sh runs the same four-root
  # grep inline, ahead of `klt env-provenance lint-envelope`; that inline copy
  # stays by choice -- the smoke flow is an attested path and folding it onto
  # this helper costs an item 9 re-attest -- so the duplication is deliberate,
  # not drift. Fails closed: a directory holding no *.json at all, or a grep
  # that errors (exit above 1), dies with its own reason instead of passing.
  local d="$1" f rc=0 leaks
  local -a jsons=() cands=()
  for f in "$d"/*.json; do [[ -f "$f" ]] && jsons+=("$f"); done
  if [[ ${#jsons[@]} -eq 0 ]]; then
    die "record_leak_guard: no *.json record in $d; refusing to pass an empty record set" 1
  fi
  cands=("${jsons[@]}")
  [[ -f "$d/tool-versions.txt" ]] && cands+=("$d/tool-versions.txt")
  leaks="$(grep -lE '(/home/|/tmp/|/Users/|/root/)' "${cands[@]}" 2>/dev/null)" || rc=$?
  if [[ $rc -gt 1 ]]; then
    die "record_leak_guard: grep failed over $d (exit $rc); failing closed" 1
  fi
  if [[ -n "$leaks" ]]; then
    printf '%s\n' "$leaks" >&2
    die "a record leaks an absolute host path" 1
  fi
}
