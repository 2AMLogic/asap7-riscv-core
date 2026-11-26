#!/usr/bin/env bash
# Self-test for the shared testbench hex writer, archtest_common.hex_image()
# (issue #300), and for the two builders that feed it: build_tests.py (the
# riscv-arch-test programs) and lockstep.py (the longer program).
#
# Both builders used to carry their own copy of the objcopy-binary-to-hex
# conversion for tb_core.v's RAM, and only build_tests.py's copy checked that
# the image fits. The cases pin the shared writer's output byte for byte
# against what those two copies produced before they were merged (the sha256
# values below were recorded from both, which agreed, at 67d9abf), then run
# the real builders with a stub objcopy to check that each accepts an image
# at the RAM's capacity and rejects one a byte over it.
#
# Needs no toolchain, no simulator and no network: the cases run the real
# archtest_common.py, build_tests.py and lockstep.py in a scratch tree
# holding copies of them, with GCC, objcopy, nm and Sail stood in by one stub
# whose objcopy writes as many bytes as STUB_BIN_BYTES says. The tracked
# verification/build/ is never read or written.
#
# usage: verification/core/hex_image_test.sh
# Exit status: 0 every case passed; 1 a case failed.
set -uo pipefail

SELF_REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PASS=0
FAIL=0

ok() { PASS=$((PASS + 1)); echo "ok   - $1"; }
no() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }

flat() { tr '\n' ' '; }

eq() {  # label want got
  if [ "$2" = "$3" ]; then
    ok "$1"
  else
    no "$1: want '$(printf '%s' "$2" | flat)', got '$(printf '%s' "$3" | flat)'"
  fi
}

yes() {  # label command... : passes while command succeeds
  local label=$1; shift
  if "$@"; then ok "$label"; else no "$label"; fi
}

# rejects label reason command... : passes while command exits non-zero and
# its stderr names the reason.
rejects() {
  local label=$1 want=$2 got=0; shift 2
  "$@" >/dev/null 2>"$SCRATCH/stderr" || got=$?
  if [ "$got" -ne 0 ] && grep -q -- "$want" "$SCRATCH/stderr"; then
    ok "$label"
  else
    no "$label: want a non-zero exit naming '$want', got exit $got: $(flat <"$SCRATCH/stderr" | tail -c 300)"
  fi
}

SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/asap7-heximage.XXXXXX")" || exit 1
trap 'rm -rf "$SCRATCH"' EXIT

CORE_SRC="$SELF_REPO/verification/core"
TREE="$SCRATCH/tree"
CORE="$TREE/verification/core"
BUILD="$TREE/verification/build"
BIN="$SCRATCH/bin"
STUBS="$SCRATCH/stubs"
mkdir -p "$CORE" "$BIN" "$STUBS/cocotb_tools" "$BUILD/riscv-arch-test/riscv-test-suite/rv32i_m/I/src"
cp "$CORE_SRC"/{archtest_common.py,build_tests.py,excluded.json,link.ld,lockstep.py,lockstep_prog.S,spike_trace.py,fv.py} \
   "$CORE/"
: >"$BUILD/riscv-arch-test/riscv-test-suite/rv32i_m/I/src/add-01.S"

cat >"$BIN/tool" <<'EOF'
#!/usr/bin/env python3
# Stands in for every toolchain binary the two builders call. objcopy writes
# the first STUB_BIN_BYTES of a repeating 0..255 pattern, Sail writes the
# signature the nm stub describes, and the rest write an empty file to -o.
import os
import sys
from pathlib import Path

name = Path(sys.argv[0]).name
args = sys.argv[1:]
if name == "riscv-none-elf-objcopy":
    n = int(os.environ["STUB_BIN_BYTES"])
    Path(args[-1]).write_bytes((bytes(range(256)) * (n // 256 + 1))[:n])
elif name == "sail_riscv_sim":
    Path(args[args.index("--test-signature") + 1]).write_text(
        "11111111\n22222222\n33333333\n44444444\n")
elif name == "riscv-none-elf-nm":
    print("80001000 T cve2_act_halt\n80002000 T tohost\n"
          "80003000 T begin_signature\n80003010 T end_signature")
else:
    Path(args[args.index("-o") + 1]).write_bytes(b"elf")
EOF
chmod +x "$BIN/tool"
for t in riscv-none-elf-gcc riscv-none-elf-objcopy riscv-none-elf-nm sail_riscv_sim; do
  ln -s "$BIN/tool" "$BIN/$t"
done

# lockstep.py imports the cocotb runner at module level; nothing here simulates.
: >"$STUBS/cocotb_tools/__init__.py"
cat >"$STUBS/cocotb_tools/runner.py" <<'EOF'
def get_runner(*args, **kwargs):
    raise SystemExit("the hex-image self-test has no simulator")
EOF

cat >"$BUILD/paths.env" <<EOF
AT=$BUILD/riscv-arch-test
SAIL=$BIN/sail_riscv_sim
GCC=$BIN/riscv-none-elf-gcc
EOF

# Every image here is the start of a repeating 0..255 pattern.
image() {  # nbytes [program] : hex_image()'s text
  python3 -I - "$CORE" "$1" "${2:-prog}" <<'PYEOF'
import sys
sys.path.insert(0, sys.argv[1])
from archtest_common import hex_image

n = int(sys.argv[2])
sys.stdout.write(hex_image((bytes(range(256)) * (n // 256 + 1))[:n], sys.argv[3]))
PYEOF
}

mem_words() {  # MEM_WORDS, the RAM size hex_image() enforces
  python3 -I - "$CORE" <<'PYEOF'
import sys
sys.path.insert(0, sys.argv[1])
from archtest_common import MEM_WORDS
print(MEM_WORDS)
PYEOF
}

tb_words() {  # the RAM size tb_core.v declares
  python3 -I - "$CORE_SRC/tb_core.v" <<'PYEOF'
import re
import sys

src = open(sys.argv[1]).read()
m = re.search(r"localparam\s+WORDS\s*=\s*(\d+)\s*<<\s*(\d+)", src)
if not m:
    sys.exit("tb_core.v: no `localparam WORDS = <n> << <n>` to compare with MEM_WORDS")
print(int(m[1]) << int(m[2]))
PYEOF
}

sha() { sha256sum | cut -d' ' -f1; }

arch_hex() {  # nbytes : build_tests.py's hex for the one program
  rm -rf "$SCRATCH/arch"
  STUB_BIN_BYTES="$1" python3 -I "$CORE/build_tests.py" "$SCRATCH/arch" >/dev/null \
    && cat "$SCRATCH/arch/I-add-01.hex"
}

lock_hex() {  # nbytes : lockstep.py's hex for the longer program
  rm -rf "$SCRATCH/lock"
  STUB_BIN_BYTES="$1" python3 -I - "$CORE" "$STUBS" "$SCRATCH/lock" <<'PYEOF' && cat "$SCRATCH/lock/lockstep-prog.hex"
import sys
from pathlib import Path

sys.path[:0] = [sys.argv[1], sys.argv[2]]
import lockstep

Path(sys.argv[3]).mkdir()
lockstep.build_long_program(lockstep.paths(), Path(sys.argv[3]))
PYEOF
}

LIMIT=2097024        # (1 << 19 words less the 32 before the load address) * 4
LIMIT_SHA=ac1f31035905a824e2082dec7c73da6b1e5fa5e81516ee08d4dc4836564ed92b

echo "# 1. the format: little-endian 32-bit words from word address 0x20, last word zero-padded"
eq "a partial final word" $'@20\n03020100\n00000004' "$(image 5)"
eq "one byte" $'@20\n00000000' "$(image 1)"
eq "a whole number of words, no padding" $'@20\n03020100\n07060504' "$(image 8)"
eq "64 words and a byte: the writers' output, byte for byte" \
  "6a09721e47a99d966386f95ece852588683e69f22d368bc7875ce2b68225541f" "$(image 257 | sha)"
eq "an empty image is the load address alone" "@20" "$(image 0)"
eq "MEM_WORDS is the size of tb_core.v's RAM" "$(tb_words)" "$(mem_words)"

echo
echo "# 2. the capacity check against that RAM"
eq "three bytes short of the limit: accepted, 524,256 data words" "524257" "$(image $((LIMIT - 3)) | wc -l)"
eq "its final word is zero-padded" "0000007c" "$(image $((LIMIT - 3)) | tail -n 1)"
eq "at the limit: the writers' output, byte for byte" "$LIMIT_SHA" "$(image "$LIMIT" | sha)"
eq "at the limit: 524,256 data words" "524257" "$(image "$LIMIT" | wc -l)"
eq "at the limit: the final word is whole" "7f7e7d7c" "$(image "$LIMIT" | tail -n 1)"
rejects "one byte over the limit is rejected, naming the program" \
  "prog does not fit in memory" image $((LIMIT + 1))
rejects "4 KiB over the limit is rejected" \
  "prog does not fit in memory" image $((LIMIT + 4096))

echo
echo "# 3. both builders write that image"
eq "build_tests.py: a partial final word" $'@20\n03020100\n00000004' "$(arch_hex 5)"
eq "lockstep.py: a partial final word" $'@20\n03020100\n00000004' "$(lock_hex 5)"
eq "build_tests.py: at the limit, byte for byte" "$LIMIT_SHA" "$(arch_hex "$LIMIT" | sha)"
eq "lockstep.py: at the limit, byte for byte" "$LIMIT_SHA" "$(lock_hex "$LIMIT" | sha)"
yes "at the limit the two hex files are byte-identical" \
  cmp "$SCRATCH/arch/I-add-01.hex" "$SCRATCH/lock/lockstep-prog.hex"

echo
echo "# 4. both builders reject an image one byte over"
rejects "build_tests.py rejects it, naming the program" \
  "I-add-01 does not fit in memory" arch_hex $((LIMIT + 1))
yes "build_tests.py writes no hex file for it" test ! -e "$SCRATCH/arch/I-add-01.hex"
rejects "lockstep.py rejects it, naming the program" \
  "lockstep-prog does not fit in memory" lock_hex $((LIMIT + 1))
yes "lockstep.py writes no hex file for it" test ! -e "$SCRATCH/lock/lockstep-prog.hex"

echo
if [ "$FAIL" -eq 0 ]; then
  echo "ALL PASS ($PASS case(s))"
  exit 0
fi
echo "FAILURES: $FAIL of $((PASS + FAIL)) case(s)"
exit 1
