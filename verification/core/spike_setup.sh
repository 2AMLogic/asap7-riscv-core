#!/usr/bin/env bash
# Build the pinned Spike ISA simulator and the dtc release it forks into
# verification/build/ (gitignored): spike/<commit>/bin/spike and dtc/<release>/.
# Nothing is installed on the host; every artifact lands under verification/build/.
# Spike upstream (riscv-software-src/riscv-isa-sim) ships no release binaries, so
# the pinned commit is fetched and compiled; its berkeley-softfloat-3 submodule
# is fixed by that tree's own gitlink and checked out from it. Spike forks the
# external dtc at every startup to build its device tree (riscv/dts.cc), so the
# pinned dtc release is built too and must be on Spike's PATH at run time
# (spike_trace.py does that).
#
# This is deliberately not part of verification/core/setup.sh: the item 9 cold
# start (verification/run.sh --core, attest/item9.json, timeout 1800 s) must not
# grow a C++ build. The Spike lane is driven by spike_trace.py, which the
# attested harness does not execute, so it builds its own inputs here.
#
# Host prerequisites, checked and never installed: g++, make, flex, bison and
# the Boost headers + libboost_regex (Spike's configure fails with its own
# message when a one is missing). Builds use -j2: this box is shared.
#
#   verification/core/spike_setup.sh
#
# Pins: verification/tool-versions.txt (spike_commit, dtc_release, dtc_sha256).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
# shellcheck source=verification/lib.sh
. "$REPO/verification/lib.sh"
# shellcheck source=fetch_checked.sh
. "$REPO/fetch_checked.sh"
BUILD="$REPO/verification/build"
JOBS=2

mkdir -p "$BUILD"
for t in g++ make flex bison git curl tar; do
  command -v "$t" >/dev/null \
    || die "$t not found on PATH (Spike build prerequisite; the host is never modified)"
done

# ---- dtc at the pinned release ---------------------------------------------
# The tarball is the sha256-verified source archive; PREFIX is uppercase in
# dtc's Makefile (a lowercase prefix= silently installs into $HOME).
DTC_REL="$(pin dtc_release)"
DTC_DIR="$BUILD/dtc/$DTC_REL"
if [ ! -x "$DTC_DIR/bin/dtc" ]; then
  SRC="$BUILD/dtc-src-$DTC_REL"
  rm -rf "$DTC_DIR" "$SRC"
  mkdir -p "$DTC_DIR" "$SRC"
  fetch_checked "https://git.kernel.org/pub/scm/utils/dtc/dtc.git/snapshot/dtc-$DTC_REL.tar.gz" \
    "$SRC/dtc.tar.gz" "$(pin dtc_sha256)" || exit 1
  tar xzf "$SRC/dtc.tar.gz" -C "$SRC"
  make -C "$SRC/dtc-$DTC_REL" -j"$JOBS" PREFIX="$DTC_DIR" install \
    >"$BUILD/dtc-build.log" 2>&1 || { tail -20 "$BUILD/dtc-build.log" >&2; die "dtc build failed"; }
  rm -rf "$SRC"
fi
LD_LIBRARY_PATH="$DTC_DIR/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
  "$DTC_DIR/bin/dtc" --version | grep -q "DTC $DTC_REL" \
  || die "dtc version is not $DTC_REL"

# ---- Spike at the pinned commit ----------------------------------------------
SPIKE_COMMIT="$(pin spike_commit)"
SPIKE_DIR="$BUILD/spike/$SPIKE_COMMIT"
if [ ! -x "$SPIKE_DIR/bin/spike" ]; then
  SRC="$BUILD/spike-src-$SPIKE_COMMIT"
  rm -rf "$SPIKE_DIR" "$SRC"
  mkdir -p "$SRC"
  git -C "$SRC" init -q
  git -C "$SRC" fetch -q --depth 1 https://github.com/riscv-software-src/riscv-isa-sim "$SPIKE_COMMIT" \
    || die "cannot fetch riscv-isa-sim $SPIKE_COMMIT"
  git -C "$SRC" checkout -q FETCH_HEAD
  [ "$(git -C "$SRC" rev-parse HEAD)" = "$SPIKE_COMMIT" ] \
    || die "riscv-isa-sim checkout is not $SPIKE_COMMIT"
  # The berkeley-softfloat-3 submodule is pinned by this tree's own gitlink.
  git -C "$SRC" submodule update --init -q
  (
    cd "$SRC"
    PATH="$DTC_DIR/bin:$PATH" ./configure --prefix="$SPIKE_DIR"
    make -j"$JOBS"
    make install
  ) >"$BUILD/spike-build.log" 2>&1 || {
    tail -20 "$BUILD/spike-build.log" >&2
    die "spike build failed (log: verification/build/spike-build.log; prerequisites: g++, make, flex, bison, Boost)"
  }
  rm -rf "$SRC"
fi
# Spike has no --version; -h exercises binary + linked libraries.
PATH="$DTC_DIR/bin:$PATH" "$SPIKE_DIR/bin/spike" -h >/dev/null 2>&1 \
  || die "$SPIKE_DIR/bin/spike does not run"
echo "spike_setup.sh: ok ($SPIKE_DIR/bin/spike, dtc $DTC_REL)"
