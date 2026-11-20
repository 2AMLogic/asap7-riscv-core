#!/usr/bin/env bash
# Self-test for the paths.env that verification/core/setup.sh publishes.
#
# `setup.sh --rtl` skips the ASAP7 cell-model downloads, but run.sh --core and
# fv.sh may start in a checkout where a gate-level run has already finished
# setup and still reads the cell metadata (archtest_common.gate_sources before
# simulation, runner.write_record after it). These cases pin that paths.env
# carries the same keys in both modes, that an --rtl run after a full run
# leaves the gate metadata intact, and that no temp file is left behind.
#
# Runs the real setup.sh in a scratch copy of the repo with every download
# replaced by a stand-in already in place (a throwaway git repo at the
# pinned arch-test commit, stub tool binaries, hash-matching cell files), so it
# needs no network and no toolchain.
#
# usage: verification/core/setup_test.sh
# Exit status: 0 every case passed; 1 a case failed.
set -uo pipefail

SELF_REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PASS=0
FAIL=0
ok() { PASS=$((PASS + 1)); echo "ok   - $1"; }
no() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }

SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/asap7-setup-test.XXXXXX")"
trap 'rm -rf "$SCRATCH"' EXIT

R="$SCRATCH/repo"
mkdir -p "$R/verification/core" "$R/flow/core" "$R/spec"
cp "$SELF_REPO/verification/lib.sh" "$SELF_REPO/verification/tool-versions.txt" "$R/verification/"
cp "$SELF_REPO/verification/core/setup.sh" "$R/verification/core/"
cp "$SELF_REPO/fetch_checked.sh" "$R/"
cp "$SELF_REPO/flow/core/sv2v.sh" "$R/flow/core/"
cp "$SELF_REPO/spec/core.md" "$R/spec/"
B="$R/verification/build"
PINF="$R/verification/tool-versions.txt"
pinv() { sed -n "s/^$1=//p" "$PINF"; }

# Throwaway arch-test checkout, and its commit written into the scratch pins.
AT="$B/riscv-arch-test"
mkdir -p "$AT"
git -C "$AT" init -q
git -C "$AT" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m t
sed -i "s/^riscv_arch_test_commit=.*/riscv_arch_test_commit=$(git -C "$AT" rev-parse HEAD)/" "$PINF"

stub() {  # path body
  mkdir -p "$(dirname "$1")"
  printf '#!/bin/sh\n%s\n' "$2" >"$1"
  chmod +x "$1"
}
stub "$B/sail-riscv/$(pinv sail_riscv_release)/sail-riscv-Linux-x86_64/bin/sail_riscv_sim" 'exit 0'
GREL="$(pinv riscv_gcc_release)"
stub "$B/riscv-gcc/$GREL/xpack-riscv-none-elf-gcc-${GREL#v}/bin/riscv-none-elf-gcc" 'exit 0'
LREL="$(pinv llvm_release)"
stub "$B/llvm/$LREL/LLVM-$LREL-Linux-X64/bin/clang-${LREL%%.*}" "echo 'clang version $LREL'"
mkdir -p "$B/cve2/upstream/rtl"
: >"$B/cve2/upstream/rtl/cve2_top.sv"
SV2V_PIN="$(grep -o 'sv2v v[0-9][0-9.]*' "$R/spec/core.md" | head -1 | cut -d' ' -f2)"
stub "$SCRATCH/sv2v" "echo 'sv2v $SV2V_PIN'"
export SV2V="$SCRATCH/sv2v"

# Hash-matching stand-in cell models, pinned in the scratch pin file.
CELLS="$B/asap7-cells/$(pinv asap7_cells_commit)"
GROUPS_LIST="$(sed -n 's/^asap7_cells_\(.*\)_sha256=.*/\1/p' "$PINF")"
add_cells() {
  mkdir -p "$CELLS"
  local g
  for g in $GROUPS_LIST; do
    printf 'module m_%s; endmodule\n' "$g" >"$CELLS/asap7sc7p5t_$g.v"
    sed -i "s/^asap7_cells_${g}_sha256=.*/asap7_cells_${g}_sha256=$(sha256sum "$CELLS/asap7sc7p5t_$g.v" | cut -d' ' -f1)/" "$PINF"
  done
}

run_setup() { bash "$R/verification/core/setup.sh" "$@" >"$SCRATCH/out.log" 2>&1; }
keys() { sed 's/=.*//' "$1" | sort; }
GATE_KEYS="CELLS CELL_GROUPS ASAP7_CELLS_COMMIT"

echo "# 1. --rtl on a cold build (no cell models) publishes the gate metadata"
if run_setup --rtl; then ok "--rtl setup succeeds without cell models"; else no "--rtl setup failed: $(tail -3 "$SCRATCH/out.log")"; fi
cp "$B/paths.env" "$SCRATCH/paths.rtl"
for k in $GATE_KEYS; do
  grep -q "^$k=." "$SCRATCH/paths.rtl" && ok "--rtl paths.env carries $k" || no "--rtl paths.env lacks $k"
done
[ ! -d "$CELLS" ] && ok "--rtl downloads no cell models" || no "--rtl created the cell-model directory"

echo
echo "# 2. full setup, then --rtl: the gate metadata survives"
add_cells
if run_setup; then ok "full setup succeeds"; else no "full setup failed: $(tail -3 "$SCRATCH/out.log")"; fi
cp "$B/paths.env" "$SCRATCH/paths.full"
run_setup --rtl || no "--rtl after full setup failed: $(tail -3 "$SCRATCH/out.log")"
if cmp -s "$SCRATCH/paths.full" "$B/paths.env"; then
  ok "paths.env is identical after an --rtl run following a full run"
else
  no "--rtl after full setup changed paths.env"
fi
if [ "$(keys "$SCRATCH/paths.full")" = "$(keys "$SCRATCH/paths.rtl")" ]; then
  ok "both modes publish the same key set"
else
  no "the --rtl and full key sets differ"
fi

echo
echo "# 3. publishing leaves no temp file behind"
left="$(find "$B" -maxdepth 1 -name 'paths.env.*' | wc -l)"
[ "$left" -eq 0 ] && ok "no paths.env.* temp files remain" || no "$left paths.env.* temp file(s) remain"

echo
if [ "$FAIL" -eq 0 ]; then
  echo "ALL PASS ($PASS case(s))"
  exit 0
fi
echo "FAILURES: $FAIL of $((PASS + FAIL)) case(s)"
exit 1
