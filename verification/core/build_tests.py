"""Compile the pinned riscv-arch-test I/M/C tests and produce Sail reference signatures.

Usage: python build_tests.py <out-dir>      (after verification/core/setup.sh)

For every test selected from the pinned suite this writes, under <out-dir>:
  <name>.hex       32-bit words from 0x80000000 ($readmemh)
  <name>.json      {tohost, sig_begin, sig_end, expected: [words]}
The expected signature comes from the Sail golden model run on the same ELF,
never from the DUT.
"""

import json
import re
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
BUILD = HERE.parent / "build"
BASE = 0x80000000
MEM_WORDS = 1 << 19  # 2 MiB

# Tests not run, with the reason. Empty entries mean "run everything".
EXCLUDE = json.loads((HERE / "excluded.json").read_text())


def paths():
    return dict(l.split("=", 1) for l in (BUILD / "paths.env").read_text().split())


def select(at):
    out = []
    for ext in ("I", "M", "C"):
        for s in sorted((at / "riscv-test-suite/rv32i_m" / ext / "src").glob("*.S")):
            out.append((ext, s))
    return out


def build_one(p, at, ext, src, out):
    name = f"{ext}-{src.stem}"
    if name in EXCLUDE:
        return None
    elf = out / f"{name}.elf"
    subprocess.run(
        [p["GCC"], "-march=rv32imc_zicsr", "-mabi=ilp32", "-static", "-mcmodel=medany",
         "-fvisibility=hidden", "-nostdlib", "-nostartfiles", "-DXLEN=32", "-DTEST_CASE_1=True",
         "-w", "-T", str(HERE / "link.ld"), f"-I{HERE}", f"-I{at}/riscv-test-suite/env",
         str(src), "-o", str(elf)], check=True)
    # Memory image.
    gcc_bin = Path(p["GCC"]).parent
    objcopy = gcc_bin / "riscv-none-elf-objcopy"
    binf = out / f"{name}.bin"
    subprocess.run([str(objcopy), "-O", "binary", str(elf), str(binf)], check=True)
    raw = binf.read_bytes()
    raw += b"\0" * (-len(raw) % 4)
    entry_off = 0x80
    # The objcopy binary starts at the first loaded section (0x80000080).
    words = [int.from_bytes(raw[i:i + 4], "little") for i in range(0, len(raw), 4)]
    assert entry_off // 4 + len(words) <= MEM_WORDS, f"{name} does not fit in memory"
    (out / f"{name}.hex").write_text(f"@{entry_off // 4:x}\n" + "".join(f"{w:08x}\n" for w in words))
    binf.unlink()
    syms = subprocess.run([str(gcc_bin / "riscv-none-elf-nm"), str(elf)], check=True,
                          capture_output=True, text=True).stdout
    sym = {m.group(2): int(m.group(1), 16)
           for m in re.finditer(r"^([0-9a-f]+) \w (\w+)$", syms, re.M)}
    sig = out / f"{name}.sail.sig"
    r = subprocess.run(
        [p["SAIL"], "--rv32", "--inst-limit", "5000000", "--stop-at-pc", hex(sym["cve2_act_halt"]), "--test-signature", str(sig),
         "--signature-granularity", "4", str(elf)],
        capture_output=True, text=True, timeout=300)
    if not sig.exists():
        sys.exit(f"{name}: Sail produced no signature\n{r.stdout}{r.stderr}")
    expected = [int(l, 16) for l in sig.read_text().split()]
    n = (sym["end_signature"] - sym["begin_signature"]) // 4
    assert len(expected) == n, f"{name}: Sail signature has {len(expected)} words, ELF has {n}"
    (out / f"{name}.json").write_text(json.dumps({
        "name": name, "source": str(src.relative_to(at)),
        "tohost": sym["tohost"], "sig_begin": sym["begin_signature"],
        "sig_end": sym["end_signature"], "expected": expected}))
    return name


def main(out):
    out.mkdir(parents=True, exist_ok=True)
    p = paths()
    at = Path(p["AT"])
    built = [n for n in (build_one(p, at, e, s, out) for e, s in select(at)) if n]
    (out / "tests.json").write_text(json.dumps(built))
    print(f"build_tests: {len(built)} tests built, {len(EXCLUDE)} excluded")


if __name__ == "__main__":
    main(Path(sys.argv[1]).resolve())
