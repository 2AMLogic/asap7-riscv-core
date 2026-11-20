#!/usr/bin/env bash
# Fetch the pinned inputs of the core architectural-test run into
# verification/build/ (gitignored): the riscv-arch-test sources, the Sail
# golden model, the bare-metal RISC-V GCC, the pinned sv2v, the hash-checked
# CVE2 closure and the ASAP7 RVT cell Verilog (gate-level run). Nothing is installed on the host. Every download is verified
# against a pin and a mismatch deletes it and exits 1. Re-running is a no-op
# once everything is in place.
#
#   verification/core/setup.sh            every input above, including the
#                                         cell models for run.sh --core --gate
#   verification/core/setup.sh --rtl      only the inputs the RTL runs read
#                                         (run.sh --core, fv.sh); skips the
#                                         cell models, which only gate-level
#                                         simulation reads (#200), so a cold
#                                         RTL start cannot fail on that
#                                         download
#
# Pins: verification/tool-versions.txt (arch-test, Sail, GCC), spec/core.md
# (sv2v, same pin as flow/core/synth.sh), reuse.lock.json (CVE2 closure).
set -euo pipefail

RTL_ONLY=0
for arg in "$@"; do
  case "$arg" in
    --rtl) RTL_ONLY=1 ;;
    *) echo "usage: setup.sh [--rtl]" >&2; exit 2 ;;
  esac
done

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
# shellcheck source=verification/lib.sh
. "$REPO/verification/lib.sh"
# shellcheck source=fetch_checked.sh
. "$REPO/fetch_checked.sh"
BUILD="$REPO/verification/build"

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
    "$SAIL_DIR/sail.tar.gz" "$(pin sail_riscv_sha256)" || exit 1
  tar xzf "$SAIL_DIR/sail.tar.gz" -C "$SAIL_DIR"
fi

# ---- RISC-V GCC ---------------------------------------------------------------
GCC_REL="$(pin riscv_gcc_release)"
GCC_DIR="$BUILD/riscv-gcc/$GCC_REL"
GCC_NAME="xpack-riscv-none-elf-gcc-${GCC_REL#v}"
if [ ! -x "$GCC_DIR/$GCC_NAME/bin/riscv-none-elf-gcc" ]; then
  mkdir -p "$GCC_DIR"
  fetch_checked "https://github.com/xpack-dev-tools/riscv-none-elf-gcc-xpack/releases/download/$GCC_REL/$GCC_NAME-linux-x64.tar.gz" \
    "$GCC_DIR/gcc.tar.gz" "$(pin riscv_gcc_sha256)" || exit 1
  tar xzf "$GCC_DIR/gcc.tar.gz" -C "$GCC_DIR"
fi

# ---- LLVM clang, used only as the assembler for the tests GNU as rejects ----
# (I-jalr-01: `la x0,<label>` is an illegal operand to GNU as >= 2.36 but valid
# for LLVM's assembler). Only bin/clang-<major> is extracted; linking stays with
# the pinned GNU toolchain above.
LLVM_REL="$(pin llvm_release)"
LLVM_DIR="$BUILD/llvm/$LLVM_REL"
LLVM_NAME="LLVM-$LLVM_REL-Linux-X64"
LLVM_MAJOR="${LLVM_REL%%.*}"
if [ ! -x "$LLVM_DIR/$LLVM_NAME/bin/clang-$LLVM_MAJOR" ]; then
  mkdir -p "$LLVM_DIR"
  fetch_checked "https://github.com/llvm/llvm-project/releases/download/llvmorg-$LLVM_REL/$LLVM_NAME.tar.xz" \
    "$LLVM_DIR/llvm.tar.xz" "$(pin llvm_sha256)" || exit 1
  tar xJf "$LLVM_DIR/llvm.tar.xz" -C "$LLVM_DIR" "$LLVM_NAME/bin/clang-$LLVM_MAJOR"
  rm -f "$LLVM_DIR/llvm.tar.xz"
fi
"$LLVM_DIR/$LLVM_NAME/bin/clang-$LLVM_MAJOR" --version | head -1 | grep -q "clang version $LLVM_REL" \
  || die "clang version is not $LLVM_REL"

# ---- sv2v (the pin flow/core/synth.sh uses, read from spec/core.md) ----------
# shellcheck source=flow/core/sv2v.sh
. "$REPO/flow/core/sv2v.sh"
sv2v_ensure "$BUILD"
SV2V_DIR="$BUILD/sv2v/$PIN_SV2V"

# ---- CVE2 closure, sha256-checked against reuse.lock.json --------------------
if [ ! -f "$BUILD/cve2/upstream/rtl/cve2_top.sv" ]; then
  "$REPO/flow/core/fetch.sh" "$BUILD/cve2/upstream"
fi

# ---- ASAP7 RVT functional cell Verilog (gate-level run, run.sh --core --gate) ---
# Which groups to fetch is derived from the pin file rather than restated here:
# one asap7_cells_<GRP>_sha256 key per group, taken in pin-file order. That file
# is the evidence record, so it is the single source of truth for the set, and
# paths.env below hands the same list to the Python side. Skipped by --rtl: the
# two RTL entry points never read these files.
if [ "$RTL_ONLY" = 0 ]; then
  CELLS_COMMIT="$(pin asap7_cells_commit)"
  CELLS_DIR="$BUILD/asap7-cells/$CELLS_COMMIT"
  mkdir -p "$CELLS_DIR"
  mapfile -t CELL_GROUPS < <(sed -n 's/^asap7_cells_\(.*\)_sha256=.*/\1/p' "$PINS")
  # Fail closed the way pin() does on a missing key: an empty set would fetch
  # nothing and leave the gate-level run with no cell models at all.
  [ "${#CELL_GROUPS[@]}" -gt 0 ] \
    || die "no asap7_cells_<group>_sha256 pins in verification/tool-versions.txt"
  for grp in "${CELL_GROUPS[@]}"; do
    f="$CELLS_DIR/asap7sc7p5t_$grp.v"
    want="$(pin "asap7_cells_${grp}_sha256")"
    if [ ! -f "$f" ] || [ "$(sha256sum "$f" | cut -d' ' -f1)" != "$want" ]; then
      fetch_checked "https://raw.githubusercontent.com/The-OpenROAD-Project/asap7sc7p5t_28/$CELLS_COMMIT/Verilog/asap7sc7p5t_$grp.v" \
        "$f" "$want" || exit 1
    fi
  done
  # Whitespace-free by construction: group names match [A-Z0-9_]+ in the pins.
  CELL_GROUPS_CSV="$(IFS=,; printf '%s' "${CELL_GROUPS[*]}")"
fi

# Paths for the other scripts. Values must be whitespace-free: paths() in
# archtest_common.py splits this file on all whitespace, not on newlines.
# Publish the pins the gate-level record cites, read through pin() so a missing
# or renamed key fails here at setup time instead of as a KeyError in
# runner.py after the whole run has finished.
RISCV_ARCH_TEST_COMMIT="$(pin riscv_arch_test_commit)"
SAIL_RISCV_RELEASE="$(pin sail_riscv_release)"
cat >"$BUILD/paths.env" <<EOF
AT=$AT
SAIL=$SAIL_DIR/sail-riscv-Linux-x86_64/bin/sail_riscv_sim
GCC=$GCC_DIR/$GCC_NAME/bin/riscv-none-elf-gcc
SV2V=$SV2V_DIR/sv2v-Linux/sv2v
CLANG=$LLVM_DIR/$LLVM_NAME/bin/clang-$LLVM_MAJOR
CVE2=$BUILD/cve2/upstream
RISCV_ARCH_TEST_COMMIT=$RISCV_ARCH_TEST_COMMIT
SAIL_RISCV_RELEASE=$SAIL_RISCV_RELEASE
EOF
if [ "$RTL_ONLY" = 0 ]; then
  # Only the gate-level run reads these (archtest_common.gate_sources,
  # runner.py write_record); run.sh --core --gate re-runs full setup before
  # the gate runner, so an --rtl paths.env can never starve it.
  cat >>"$BUILD/paths.env" <<EOF
CELLS=$CELLS_DIR
CELL_GROUPS=$CELL_GROUPS_CSV
ASAP7_CELLS_COMMIT=$CELLS_COMMIT
EOF
fi
echo "setup.sh: ok"
