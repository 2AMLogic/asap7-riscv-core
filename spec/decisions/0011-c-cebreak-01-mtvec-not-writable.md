# 0011 — C-cebreak-01 stays excluded: the core's mtvec is not fully writable

**Status:** adopted 2026-11-03. Follows the exclusions recorded with the core arch-test run (T1 item 9).

**Decision.** `C-cebreak-01` remains in `verification/core/excluded.json`, now with a diagnosed reason. The cause is
the core's (spec-legal) `mtvec` behaviour meeting a precondition of the pinned suite, not bench glue. The core is
pinned and unmodified and the suite is not edited, so neither side is changed to make the test pass.

**Measurement** (riscv-arch-test `331b0cd`, CVE2 `d7f2156`, Icarus, `verification/run.sh --core` with only this test):

1. The suite's README lists as target requirement 1: "`mtvec` must be completely writable by the test in machine mode".
   CVE2 does not satisfy it: `cve2_cs_registers.sv` writes `mtvec_d = {csr_wdata[31:8], 6'b0, 2'b01}` (MODE fixed to
   vectored, base 256-byte aligned).
2. The prolog (`arch_test.h`, `init_mtvec`) writes the address of its trampoline to `mtvec` and reads it back. The
   read-back can never match, so it takes the "fixed mtvec" path (`init_tramp`) and uses the original `mtvec`, which
   reads `0x80000001`, MODE bit included, as a word pointer to copy a 16-word trampoline there.
3. Memory dump after the prolog: words at `0x80000000` are `00006f00 80006f08 00006f08 ...`, the trampoline shifted
   by one byte. The prolog finishes at cycle 351; `c.ebreak` at `0x8000019c` vectors to `0x80000000` (cycle 420), the
   instructions there decode wrongly, and the fetch loops over `0x80000000..0x80000008` until the cycle limit. `tohost`
   is never written.

**Classification.** Core behaviour (a permitted WARL `mtvec`) against a suite assumption. It is not bench glue:
`RVMODEL_BOOT` cannot make `mtvec` writable, and aligning the copy would need editing the suite or the RTL, which the
scope rules forbid. A hack that pre-seeds bytes at `0x80000000` was rejected as fragile and as hiding the mismatch.

**Consequence.** T1 item 9 does not cover `C-cebreak-01`; the attestation says so. Reopen if the pinned suite or core
changes. `I-jalr-01` is separate: it now builds with a pinned LLVM clang (`verification/tool-versions.txt`) and passes.
