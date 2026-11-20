# The deterministic longer program for the lockstep lane (issue #206).
#
# Assembled and linked by verification/core/lockstep.py with the same pinned
# GCC, link.ld and tohost convention as the riscv-arch-test programs
# (build_tests.py), so the Spike reference reader (spike_trace.py) accepts it:
# entry at 0x80000080, mtvec written only in the shape both Spike and CVE2
# reproduce (vectored mode, 256-byte-aligned base, decision 0011), and the
# halt is a store of 1 to tohost.
#
# What it deliberately exercises, per the issue's test plan:
#   - 16- and 32-bit instructions (c.* and full-width, so instruction length
#     differs per retirement);
#   - idle cycles: div/rem and mul stall the pipeline for multiple cycles
#     between retirements;
#   - x0/no-write: discarded writes to x0;
#   - repeated PCs: an unrolled-free countdown loop, 64 iterations, so the
#     same PCs retire 64 times;
#   - loads and stores through the data port (single- and half-word);
#   - CSR write + read-back (mtvec, mscratch);
#   - a synchronous trap (ebreak) delivered to the vectored handler, with
#     mcause/mepc read-back and mret;
#   - the final retiring store to tohost.
#
# The program is fully deterministic: no inputs, a fixed loop count, and every
# computed value is written back through a register destination.
    .section .text.init, "ax", @progbits
    .globl rvtest_entry_point
rvtest_entry_point:
    addi s0, zero, 5              # 32-bit; the negative control's target
    la   t0, vector_base
    ori  t0, t0, 1                # vectored mode, base stays 256-byte aligned
    csrw mtvec, t0
    csrr t1, mtvec                # read-back must equal the written value
    la   s1, scratch
    li   a0, 64                   # loop countdown: repeated PCs
    li   a1, 7
loop:
    c.addi s0, 1                  # 16-bit
    c.addi a1, 3                  # 16-bit
    addi x0, s0, 0                # write to x0: architecturally discarded
    mul  a2, s0, a1               # multi-cycle: idle cycles before retirement
    divu a3, a2, a1               # multi-cycle
    rem  a4, s0, a1               # multi-cycle; s0 < a1, so a4 = s0 varies per iteration
    sw   a2, 0(s1)
    lw   a5, 0(s1)
    sh   a3, 4(s1)
    lhu  a6, 4(s1)
    sb   a4, 6(s1)
    lbu  a7, 6(s1)
    c.addi a0, -1                 # 16-bit
    bnez a0, loop
    csrw mscratch, s0
    csrr s2, mscratch             # read-back
    sw   s2, 8(s1)
    ebreak                        # synchronous trap: mcause = 3
back_from_trap:
    la   t0, tohost
    li   t1, 1
    sw   t1, 0(t0)                # the halt store the trace stops at
1:  j 1b

    .section .text, "ax", @progbits
    .align 8
vector_base:
trap_handler:
    csrr t2, mcause               # 3 (breakpoint)
    csrr t3, mepc                 # the ebreak pc
    sw   t2, 12(s1)
    la   t4, back_from_trap
    csrw mepc, t4
    mret

    .pushsection .tohost, "aw", @progbits
    .align 8; .global tohost; tohost: .dword 0;
    .align 8; .global fromhost; fromhost: .dword 0;
    .popsection
    .section .data
    .align 4
scratch: .word 0
         .word 0
         .word 0
         .word 0
