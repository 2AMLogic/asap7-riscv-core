# shellcheck shell=bash
# The one download-and-verify primitive: fetch a pinned artifact over HTTPS,
# check its sha256 against the pin, fail closed. Sourced, not executed.
#
# Deliberately a third file rather than a function in flow/lib.sh or
# verification/lib.sh. Both trees need this primitive — verification/core/setup.sh
# (Sail, the RISC-V GCC, LLVM, the ASAP7 RVT cell Verilog), flow/core/fetch.sh
# (the CVE2 closure) and flow/core/sv2v.sh (the pinned sv2v release) — and
# flow/core/sv2v.sh is sourced by one script from each tree. Putting the helper
# in either lib would drag that lib's die() into the other tree through
# flow/core/sv2v.sh and silently redefine it: flow/lib.sh's die exits ${2:-2},
# verification/lib.sh's exits 1. It would also cross the boundary
# verification/lib.sh states, that verification/ does not source the PDK flow
# helpers. This file therefore defines exactly one function, depends on no lib,
# and does its own failure reporting.
#
# Provides:
#   fetch_checked <url> <dest> <sha256>
#       Downloads <url> to <dest>, following redirects, retrying twice.
#       Staged through <dest>.part, so <dest> only ever exists with the pinned
#       content; the partial file is removed on a failed download or a hash
#       mismatch. Writes a message naming the running script to stderr and
#       returns 1 on either failure, 0 on success. The caller decides the exit
#       status — callers here use `|| exit 1`, which holds whether or not
#       errexit is set in the shell that sourced them.
#
# These helpers read pins only; they make no claim about any design.

fetch_checked() {  # url dest sha256
  local url="$1" dest="$2" want="$3" tmp got
  tmp="$dest.part"
  if ! curl -fsSL --retry 2 -o "$tmp" "$url"; then
    rm -f "$tmp"
    echo "$(basename "$0"): download failed: $url" >&2
    return 1
  fi
  got="$(sha256sum "$tmp" | cut -d' ' -f1)"
  if [ "$got" != "$want" ]; then
    rm -f "$tmp"
    echo "$(basename "$0"): sha256 mismatch for $url: got $got, pinned $want" >&2
    return 1
  fi
  mv "$tmp" "$dest"
}
