#!/usr/bin/env bash
# Self-test for the first-program build behind the three negative controls
# (issue #297): build_tests.py's --first-only selection, and the output
# directory archtest_common.prepare() gives it.
#
# The RTL, gate-level and klt negative controls run one program, so their
# build stops after the first eligible program in suite order instead of
# compiling every program and running Sail for each; and that one-program
# build lands in a run-local directory, because its one-entry tests.json must
# not replace the full suite's shared manifest under verification/build/tests/.
#
# Needs no toolchain, no simulator and no network: the cases run the real
# build_tests.py and prepare() in a scratch tree holding copies of the real
# archtest_common.py, build_tests.py, excluded.json and link.ld, with the
# pinned arch-test sources, GCC, clang, Sail and sv2v.sh stood in by stubs
# that log every invocation. The tracked verification/build/ is never read or
# written.
#
# usage: verification/core/build_tests_test.sh
# Exit status: 0 every case passed; 1 a case failed.
set -uo pipefail

SELF_REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PASS=0
FAIL=0

ok() { PASS=$((PASS + 1)); echo "ok   - $1"; }
no() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }

eq() {  # label want got
  local got=${3//$'\n'/ }
  if [ "$2" = "$got" ]; then ok "$1"; else no "$1: want '$2', got '$got'"; fi
}

yes() {  # label command... : passes while command succeeds
  local label=$1; shift
  if "$@"; then ok "$label"; else no "$label"; fi
}

SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/asap7-buildtest.XXXXXX")" || exit 1
cleanup() { rm -rf "$SCRATCH"; }
trap cleanup EXIT

CORE_SRC="$SELF_REPO/verification/core"
TREE="$SCRATCH/tree"
CORE="$TREE/verification/core"
BUILD="$TREE/verification/build"
AT="$BUILD/riscv-arch-test"
BIN="$SCRATCH/bin"
CALLS="$SCRATCH/calls"
SUITE="I-add-01 I-jalr-01 M-add-01 C-add-01"

mkdir -p "$CORE" "$BIN" "$TREE/flow/core" "$AT/riscv-test-suite/env"
cp "$CORE_SRC/archtest_common.py" "$CORE_SRC/build_tests.py" \
   "$CORE_SRC/excluded.json" "$CORE_SRC/link.ld" "$CORE/"

# Suite order is I, then M, then C, each directory sorted; C-cebreak-01 is
# excluded by the tracked excluded.json. A program is named <ext>-<stem>.
for s in I/src/add-01 I/src/jalr-01 M/src/add-01 C/src/add-01 C/src/cebreak-01; do
  f="$AT/riscv-test-suite/rv32i_m/$s.S"
  mkdir -p "$(dirname "$f")"
  : >"$f"
done

cat >"$SCRATCH/tool" <<'EOF'
#!/bin/sh
name="$(basename "$0")"
echo "$name $*" >>"@CALLS@"
for last; do :; done
case "$name" in
  riscv-none-elf-nm)
    printf '80001000 T cve2_act_halt\n80002000 T tohost\n'
    printf '80003000 T begin_signature\n80003010 T end_signature\n'
    exit 0 ;;
  riscv-none-elf-objcopy) printf '01234567' >"$last"; exit 0 ;;
esac
out= sig=
while [ $# -gt 0 ]; do
  case "$1" in -o) out=$2 ;; --test-signature) sig=$2 ;; esac
  shift
done
case "$name" in
  sail_riscv_sim) printf '11111111\n22222222\n33333333\n44444444\n' >"$sig" ;;
  *) printf 'elf' >"$out" ;;
esac
EOF
sed -i "s|@CALLS@|$CALLS|" "$SCRATCH/tool"
chmod +x "$SCRATCH/tool"
for t in riscv-none-elf-gcc riscv-none-elf-ld riscv-none-elf-objcopy riscv-none-elf-nm clang-19 sail_riscv_sim; do
  ln -s "$SCRATCH/tool" "$BIN/$t"
done

cat >"$TREE/flow/core/sv2v.sh" <<'EOF'
#!/bin/sh
echo "sv2v.sh $*" >>"@CALLS@"
for dest; do :; done
printf '// stub conversion\n' >"$dest"
EOF
sed -i "s|@CALLS@|$CALLS|" "$TREE/flow/core/sv2v.sh"

cat >"$BUILD/paths.env" <<EOF
AT=$AT
SAIL=$BIN/sail_riscv_sim
GCC=$BIN/riscv-none-elf-gcc
SV2V=$BIN/sv2v
CLANG=$BIN/clang-19
CVE2=$BUILD/cve2/upstream
CELLS=$BUILD/asap7-cells
CELL_GROUPS=SIMPLE
EOF

calls() {  # extended-regex -> number of logged invocations that match
  grep -cE "$1" "$CALLS"
}

compiled() { calls '^(riscv-none-elf-gcc|clang-19) '; }
sailed() { calls '^sail_riscv_sim '; }

files() {  # dir -> its entries, sorted, on one line
  find "$1" -mindepth 1 -maxdepth 1 -printf '%f\n' | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//'
}

squash() { tr '\n' ' ' | sed 's/ $//'; }

names() {  # tests.json -> one name per line
  python3 -I -c 'import json, sys; print("\n".join(json.load(open(sys.argv[1]))))' "$1" 2>/dev/null
}

build() {  # out-dir [builder flags]
  python3 -I "$CORE/build_tests.py" "$@"
}

prepare() {  # run-dir negative|normal gate|rtl ; prints "<tests_dir>|<names>|<dut .v>"
  # The builder's own summary line precedes the result on stdout, as it does
  # for the real drivers.
  python3 -I - "$CORE" "$@" <<'PYEOF' | tail -n 1
import sys
from pathlib import Path

sys.path.insert(0, sys.argv[1])
from archtest_common import prepare

tests_dir, names, dut = prepare(Path(sys.argv[2]), sys.argv[3] == "negative", sys.argv[4] == "gate")
print(f"{tests_dir}|{','.join(names)}|{dut}")
PYEOF
}

echo "# 1. the default build is the full suite, in suite order"
: >"$CALLS"
build "$SCRATCH/full" >/dev/null || no "the default build exits non-zero"
eq "tests.json lists every eligible program in suite order" \
  "$SUITE" "$(names "$SCRATCH/full/tests.json" | squash)"
eq "every eligible program is compiled" "4" "$(compiled)"
eq "Sail runs once per program" "4" "$(sailed)"
eq "the excluded program reaches no tool" "0" "$(calls 'C-cebreak-01')"

echo
echo "# 2. --first-only stops after the first eligible program"
: >"$CALLS"
build "$SCRATCH/first" --first-only >/dev/null || no "the --first-only build exits non-zero"
eq "tests.json names the first eligible program only" "I-add-01" "$(names "$SCRATCH/first/tests.json")"
eq "one program is compiled" "1" "$(compiled)"
eq "Sail runs once" "1" "$(sailed)"
eq "only that program's files are written" \
  "I-add-01.elf I-add-01.hex I-add-01.json I-add-01.sail.sig tests.json" "$(files "$SCRATCH/first")"
eq "its json carries the Sail signature" "I-add-01 4" \
  "$(python3 -I -c 'import json, sys; t = json.load(open(sys.argv[1])); print(t["name"], len(t["expected"]))' \
     "$SCRATCH/first/I-add-01.json" 2>/dev/null)"

echo
echo "# 3. --first-only skips excluded programs before the first eligible one"
printf '{"I-add-01": "self-test exclusion", "C-cebreak-01": "self-test exclusion"}\n' >"$CORE/excluded.json"
: >"$CALLS"
build "$SCRATCH/next" --first-only >/dev/null || no "the --first-only build exits non-zero past an exclusion"
eq "tests.json names the next eligible program" "I-jalr-01" "$(names "$SCRATCH/next/tests.json")"
eq "the excluded program reaches no tool" "0" "$(calls 'I-add-01')"
eq "one program is compiled" "1" "$(compiled)"

echo
echo "# 4. --first-only with no eligible program leaves an empty manifest"
printf '{"I-add-01": "x", "I-jalr-01": "x", "M-add-01": "x", "C-add-01": "x", "C-cebreak-01": "x"}\n' \
  >"$CORE/excluded.json"
: >"$CALLS"
build "$SCRATCH/none" --first-only >/dev/null || no "the --first-only build exits non-zero with nothing eligible"
eq "tests.json is empty" "" "$(names "$SCRATCH/none/tests.json")"
eq "nothing is compiled" "0" "$(compiled)"
cp "$CORE_SRC/excluded.json" "$CORE/excluded.json"

echo
echo "# 5. prepare(): a normal run builds the full suite into the shared directory"
: >"$CALLS"
normal="$(prepare "$SCRATCH/run-normal" normal gate)" || no "prepare() exits non-zero for a normal run"
eq "it returns the shared tests directory and every program" \
  "$BUILD/tests|I-add-01,I-jalr-01,M-add-01,C-add-01" "$(printf '%s' "$normal" | cut -d'|' -f1,2)"
eq "the shared directory holds the four programs" \
  "$(for n in C-add-01 I-add-01 I-jalr-01 M-add-01; do printf '%s ' "$n.elf" "$n.hex" "$n.json" "$n.sail.sig"; done)tests.json" \
  "$(files "$BUILD/tests")"
eq "no conversion runs for the gate-level DUT" "0" "$(calls '^sv2v.sh ')"
yes "no tests directory is left in the run dir" test ! -e "$SCRATCH/run-normal/tests"

echo
echo "# 6. prepare(): a negative control builds one program into the run directory"
cp "$BUILD/tests/tests.json" "$SCRATCH/shared.json"
: >"$CALLS"
negative="$(prepare "$SCRATCH/run-negative" negative gate)" \
  || no "prepare() exits non-zero for a negative control"
eq "it returns a run-local tests directory naming the first program" \
  "$SCRATCH/run-negative/tests|I-add-01" "$(printf '%s' "$negative" | cut -d'|' -f1,2)"
eq "one program is compiled" "1" "$(compiled)"
eq "Sail runs once" "1" "$(sailed)"
eq "no conversion runs for the gate-level DUT" "0" "$(calls '^sv2v.sh ')"
eq "no tool is pointed at the shared tests directory" "0" "$(calls " $BUILD/tests/")"
yes "the shared manifest is not replaced" cmp -s "$SCRATCH/shared.json" "$BUILD/tests/tests.json"

# fv.sh accepts an explicit output directory, including verification/build.
negative="$(prepare "$BUILD" negative rtl)" || no "prepare() exits non-zero with the build directory as output"
control_tests="${negative%%|*}"
yes "the control stores its program under the supplied output" test "$(dirname "$control_tests")" = "$BUILD"
yes "the control has its own tests directory" test ! "$control_tests" -ef "$BUILD/tests"
eq "the control manifest names only the first program" "I-add-01" "$(names "$control_tests/tests.json")"
yes "the explicit output preserves the full manifest byte for byte" cmp -s "$SCRATCH/shared.json" "$BUILD/tests/tests.json"

echo
echo "# 7. prepare(): an RTL run gets the converted closure from either build"
: >"$CALLS"
rtl_negative="$(prepare "$SCRATCH/run-rtl-negative" negative rtl)" \
  || no "prepare() exits non-zero for the RTL negative control"
eq "the negative control: run-local tests, one program, the converted closure" \
  "$SCRATCH/run-rtl-negative/tests|I-add-01|$SCRATCH/run-rtl-negative/cve2_rv32imc_wrapper.v" "$rtl_negative"
yes "the control's conversion ran" test -s "$SCRATCH/run-rtl-negative/cve2_rv32imc_wrapper.v"
rtl_normal="$(prepare "$SCRATCH/run-rtl-normal" normal rtl)" \
  || no "prepare() exits non-zero for the RTL normal run"
eq "a normal run: shared tests, every program, the converted closure" \
  "$BUILD/tests|I-add-01,I-jalr-01,M-add-01,C-add-01|$SCRATCH/run-rtl-normal/cve2_rv32imc_wrapper.v" \
  "$rtl_normal"

echo
echo "# 8. the normal invocation after a control still produces the full manifest"
after="$(prepare "$SCRATCH/run-after" normal gate)" || no "prepare() exits non-zero after a control"
eq "every program is returned" "I-add-01,I-jalr-01,M-add-01,C-add-01" "$(printf '%s' "$after" | cut -d'|' -f2)"
eq "the shared manifest lists every program" "$SUITE" "$(names "$BUILD/tests/tests.json" | squash)"

echo
if [ "$FAIL" -eq 0 ]; then
  echo "ALL PASS ($PASS case(s))"
  exit 0
fi
echo "FAILURES: $FAIL of $((PASS + FAIL)) case(s)"
exit 1
