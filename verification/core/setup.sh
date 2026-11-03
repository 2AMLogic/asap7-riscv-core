#!/usr/bin/env bash
# Fetch the pinned inputs of the core architectural-test run into
# verification/build/ (gitignored): the riscv-arch-test sources, the Sail
# golden model, the bare-metal RISC-V GCC, the pinned sv2v and the hash-checked
# CVE2 closure. Nothing is installed on the host. Every download is verified
# against a pin and a mismatch deletes it and exits 1. Re-running is a no-op
# once everything is in place.
#
#   verification/core/setup.sh
#
# Pins: verification/tool-versions.txt (arch-test, Sail, GCC), spec/core.md
# (sv2v, same pin as flow/core/synth.sh), reuse.lock.json (CVE2 closure).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
PINS="$REPO/verification/tool-versions.txt"
BUILD="$REPO/verification/build"

die() { echo "setup.sh: $*" >&2; exit 1; }
pin() { local v; v="$(sed -n "s/^$1=//p" "$PINS")"; [ -n "$v" ] || die "no pin for $1 in verification/tool-versions.txt"; echo "$v"; }

fetch_checked() { # url dest sha256
  local url="$1" dest="$2" want="$3" tmp
  tmp="$dest.part"
  curl -fsSL --retry 2 -o "$tmp" "$url" || { rm -f "$tmp"; die "download failed: $url"; }
  if [ "$(sha256sum "$tmp" | cut -d' ' -f1)" != "$want" ]; then
    rm -f "$tmp"; die "sha256 mismatch for $url (pinned $want)"
  fi
  mv "$tmp" "$dest"
}

mkdir -p "$BUILD"

# ---- riscv-arch-test, at the pinned commit ---------------------------------
AT_COMMIT="$(pin riscv_arch_test_commit)"
AT="$BUILD/riscv-arch-test"
if [ "$(git -C "$AT" rev-parse HEAD 2>/dev/null || true)" != "$AT_COMMIT" ]; then
  rm -rf "$AT"; mkdir -p "$AT"
  git -C "$AT" init -q
  git -C "$AT" fetch -q --depth 1 https://github.com/riscv-non-isa/riscv-arch-test "$AT_COMMIT" \
    || die "cannot fetch riscv-arch-test $AT_COMMIT"
  git -C "$AT" checkout -q FETCH_HEAD
  [ "$(git -C "$AT" rev-parse HEAD)" = "$AT_COMMIT" ] || die "riscv-arch-test checkout is not $AT_COMMIT"
fi

# ---- Sail golden model --------------------------------------------------------
SAIL_REL="$(pin sail_riscv_release)"
SAIL_DIR="$BUILD/sail-riscv/$SAIL_REL"
if [ ! -x "$SAIL_DIR/sail-riscv-Linux-x86_64/bin/sail_riscv_sim" ]; then
  mkdir -p "$SAIL_DIR"
  fetch_checked "https://github.com/riscv/sail-riscv/releases/download/$SAIL_REL/sail-riscv-Linux-x86_64.tar.gz" \
    "$SAIL_DIR/sail.tar.gz" "$(pin sail_riscv_sha256)"
  tar xzf "$SAIL_DIR/sail.tar.gz" -C "$SAIL_DIR"
fi

# ---- RISC-V GCC ---------------------------------------------------------------
GCC_REL="$(pin riscv_gcc_release)"
GCC_DIR="$BUILD/riscv-gcc/$GCC_REL"
GCC_NAME="xpack-riscv-none-elf-gcc-${GCC_REL#v}"
if [ ! -x "$GCC_DIR/$GCC_NAME/bin/riscv-none-elf-gcc" ]; then
  mkdir -p "$GCC_DIR"
  fetch_checked "https://github.com/xpack-dev-tools/riscv-none-elf-gcc-xpack/releases/download/$GCC_REL/$GCC_NAME-linux-x64.tar.gz" \
    "$GCC_DIR/gcc.tar.gz" "$(pin riscv_gcc_sha256)"
  tar xzf "$GCC_DIR/gcc.tar.gz" -C "$GCC_DIR"
fi

# ---- sv2v (the pin flow/core/synth.sh uses, read from spec/core.md) ----------
PIN_SV2V="$(grep -o 'sv2v v[0-9][0-9.]*' "$REPO/spec/core.md" | head -1 | cut -d' ' -f2)"
PIN_SV2V_SHA="$(grep -A2 'zachjs/sv2v' "$REPO/spec/core.md" | grep -o '[0-9a-f]\{64\}' | head -1)"
[ -n "$PIN_SV2V" ] && [ -n "$PIN_SV2V_SHA" ] || die "could not read the sv2v pin from spec/core.md"
SV2V_DIR="$BUILD/sv2v/$PIN_SV2V"
if [ ! -x "$SV2V_DIR/sv2v-Linux/sv2v" ]; then
  mkdir -p "$SV2V_DIR"
  fetch_checked "https://github.com/zachjs/sv2v/releases/download/$PIN_SV2V/sv2v-Linux.zip" \
    "$SV2V_DIR/sv2v-Linux.zip" "$PIN_SV2V_SHA"
  python3 -I -c 'import sys, zipfile; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])' \
    "$SV2V_DIR/sv2v-Linux.zip" "$SV2V_DIR"
  chmod +x "$SV2V_DIR/sv2v-Linux/sv2v"
fi
[ "$("$SV2V_DIR/sv2v-Linux/sv2v" --version)" = "sv2v $PIN_SV2V" ] || die "sv2v version is not $PIN_SV2V"

# ---- CVE2 closure, sha256-checked against reuse.lock.json --------------------
if [ ! -f "$BUILD/cve2/upstream/rtl/cve2_top.sv" ]; then
  "$REPO/flow/core/fetch.sh" "$BUILD/cve2/upstream"
fi

# Paths for the other scripts.
cat >"$BUILD/paths.env" <<EOF
AT=$AT
SAIL=$SAIL_DIR/sail-riscv-Linux-x86_64/bin/sail_riscv_sim
GCC=$GCC_DIR/$GCC_NAME/bin/riscv-none-elf-gcc
SV2V=$SV2V_DIR/sv2v-Linux/sv2v
CVE2=$BUILD/cve2/upstream
EOF
echo "setup.sh: ok"
