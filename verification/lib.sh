# shellcheck shell=bash
# Shared plumbing for the verification scripts (verification/run.sh,
# verification/fv.sh, verification/core/setup.sh). Sourced, not executed.
#
# The counterpart of flow/lib.sh for the PDK-free harness: kept separate so
# verification/ does not have to source the PDK flow helpers, and so the one
# place that reads verification/tool-versions.txt lives beside that file.
#
# These helpers read tool pins only; they make no claim about any design.
#
# Provides:
#   die <msg>                  message prefixed with the script name, exit 1
#   pin <key>                  value of <key> in verification/tool-versions.txt;
#                              dies when the key is missing or empty, so a
#                              misspelled key fails closed instead of reading
#                              as "unpinned"
#   check_version <key> <got>  refuse an installed tool whose version is not the
#                              pinned one; <got> matches the pin exactly or as a
#                              more specific revision of it (5.050 -> 5.050.1)
#   leak_guard <file>          die when <file> still names an absolute host path
#                              (/home/, /tmp/, /Users/, /root/ -- the same
#                              four-root grep flow/smoke/run.sh runs on its own
#                              records); a file that cannot be read fails too.
#                              A committed record names no host path: an input
#                              is pinned by identity, not location.
#
# verification/lib_test.sh checks leak_guard: each of the four roots fails with
# the named reason, a redacted record passes, and an unreadable file fails
# closed. It needs no PDK checkout, no klt and no network.
#
# PINS is derived from this file's own location, so a caller in any directory
# reads the same pin file.

PINS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/tool-versions.txt"

die() { echo "$(basename "$0"): $*" >&2; exit 1; }

pin() {  # key
  local v
  v="$(sed -n "s/^$1=//p" "$PINS")"
  [ -n "$v" ] || die "no pin for $1 in verification/tool-versions.txt"
  printf '%s\n' "$v"
}

check_version() {  # key installed-version
  local want
  want="$(pin "$1")" || exit 1
  [ -n "$2" ] || die "$1 not found on PATH (pinned: $want)"
  case "$2" in
    "$want"|"$want".*) ;;
    *) die "$1 version mismatch: installed $2, pinned $want (verification/tool-versions.txt)" ;;
  esac
}

leak_guard() {  # file
  local m rc=0
  m="$(grep -nE '(/home/|/tmp/|/Users/|/root/)' "$1")" || rc=$?
  if [ "$rc" -eq 0 ]; then
    printf '%s\n' "$m" >&2
    die "$1 leaks an absolute host path"
  fi
  [ "$rc" -eq 1 ] || die "leak_guard: cannot scan $1 (grep exit $rc)"
}
