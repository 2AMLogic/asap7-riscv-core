"""Offline self-test for the lockstep comparator (lockstep_compare.py).

    python3 -I verification/core/test_lockstep_compare.py

No simulator, no Spike, no network: synthetic reference records and DUT
observations exercise every comparison rule and every failure kind the bench
can report, from the issue #206 test plan: a clean run through trap and mret,
a corrupted write-back (the negative control's injected shape), a wrong pc,
trap shapes in both directions, missing and extra events, the CSR write
observation with CVE2's WARL projections, sub-word store normalization,
compressed-instruction masking, the retirement order check and timeout
reporting when no PC is available.

Exit status: 0 every case passed; 1 a case failed.
"""

import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from lockstep_compare import (MEPC, MSTATUS, MSCRATCH, MTVEC, MRET_ENC,  # noqa: E402
                              OBSERVED_CSRS, Lockstep, project_csr)

PASS = FAIL = 0


def ok(msg):
    global PASS
    PASS += 1
    print(f"ok   - {msg}")


def no(msg):
    global FAIL
    FAIL += 1
    print(f"FAIL - {msg}")


def check(cond, msg):
    (ok if cond else no)(msg)
    return cond


def ref(**kw):
    r = {"pc": 0x1000, "enc": 0x1234_5678, "len": 4, "priv": 3, "rd": None,
         "rd_val": None, "csr": [], "loads": [], "stores": []}
    r.update(kw)
    return r


def obs(**kw):
    o = {"order": 1, "pc": 0x1000, "insn": 0x1234_5678, "trap": 0, "priv": 3,
         "rd_addr": 0, "rd_wdata": 0, "mem_rmask": 0, "mem_wmask": 0,
         "mem_addr": 0, "mem_wdata": 0, "cycle": 10}
    o.update(kw)
    return o


TOHOST = 0x8000_1000

# A miniature program: a write-back, a discarded x0 write, a load, a sub-word
# store, an mtvec csrw (non-representable write value -> WARL), a trap gap,
# the handler's mcause read-back, an mret (mstatus write one cycle late), and
# the retiring tohost store.
REF = [
    ref(rd=8, rd_val=5, enc=0x00500413),                 # 1: addi s0,zero,5
    ref(pc=0x1004, enc=0x00040013),                      # 2: mv zero,s0 (x0)
    ref(pc=0x1008, enc=0x0004a503, rd=10, rd_val=0xAB, loads=[0x2000]),   # 3: lw
    ref(pc=0x100C, enc=0x00A99223, stores=[(0x2006, 0x1234)]),            # 4: sh
    ref(pc=0x1010, enc=0x30529073, csr=[(MTVEC, "mtvec", 0x2001)]),       # 5: csrw
    ref(pc=0x1014, enc=0x00802A23, stores=[(0x2010, 7)]),                 # 6: sw
    {"exception": True, "epc": 0x1018, "handler": 0x2000},                # 7: gap
    ref(pc=0x2000, enc=0x342023F3, rd=7, rd_val=3),      # 8: csrr t2,mcause
    ref(pc=0x2004, enc=0x30200073, csr=[(MSTATUS, "mstatus", 0x80),
                                        (0x310, "mstatush", 0)]),         # 9: mret
    ref(pc=0x101C, enc=0x00C02023, stores=[(TOHOST, 1)]),                 # 10: halt
]


def dut_stream():
    """Matching DUT observations (orders 1..10, cycles 10,11,...)."""
    o = []
    specs = [
        dict(order=1, pc=0x1000, insn=0x00500413, rd_addr=8, rd_wdata=5),
        dict(order=2, pc=0x1004, insn=0x00040013),
        dict(order=3, pc=0x1008, insn=0x0004A503, rd_addr=10, rd_wdata=0xAB,
             mem_rmask=0xF, mem_addr=0x2000),
        dict(order=4, pc=0x100C, insn=0x00A99223, mem_wmask=0xC, mem_addr=0x2006,
             mem_wdata=0x1234),  # raw rs2 value: the lane shift is bus-side only
        dict(order=5, pc=0x1010, insn=0x30529073),
        dict(order=6, pc=0x1014, insn=0x00802A23, mem_wmask=0xF, mem_addr=0x2010,
             mem_wdata=7),
        dict(order=7, pc=0x1018, insn=0x00100073, trap=1),  # ebreak kept by RVFI
        dict(order=8, pc=0x2000, insn=0x342023F3, rd_addr=7, rd_wdata=3),
        dict(order=9, pc=0x2004, insn=0x30200073),
        dict(order=10, pc=0x101C, insn=0x00C02023, mem_wmask=0xF, mem_addr=TOHOST,
             mem_wdata=1),
    ]
    for i, s in enumerate(specs):
        o.append(obs(cycle=10 + i, **s))
    return o


def pulses(cmp_):
    """Feed the CSR write pulses the DUT observation would carry."""
    cmp_.csr_pulse(MTVEC, project_csr(MTVEC, 0x2001), 13)   # csrw, 3 cycles before its retirement
    cmp_.csr_pulse(MEPC, 0x1018, 15)                        # trap entry: no reference record
    cmp_.csr_pulse(MSTATUS, 0x1880, 19)                     # mret's mstatus (MPP stays M on
    # CVE2), one cycle late


def run_clean():
    cmp_ = Lockstep("t", REF, TOHOST)
    pulses(cmp_)
    for o in dut_stream():
        m = cmp_.retirement(o)
        if m is not None:
            return m
    return cmp_.finish()


print("# 1. a clean run: all 10 records match, complete at the tohost store")
m = run_clean()
check(m is None, "no mismatch on a matching stream")
cmp_ = Lockstep("t", REF, TOHOST)
pulses(cmp_)
for o in dut_stream():
    if cmp_.retirement(o) is None and cmp_.complete:
        break
check(cmp_.complete and cmp_.n == 10, "complete is set exactly at the 10th retirement")

print("# 2. the negative control's shape: one write-back bit corrupted")
cmp_ = Lockstep("t", REF, TOHOST)
pulses(cmp_)
m = None
for o in dut_stream():
    if o["order"] == 1:
        o["rd_wdata"] ^= 1
    m = cmp_.retirement(o) or m
    if m:
        break
check(m is not None and m["field"] == "rd_wdata" and m["ordinal"] == 1
      and m["pc"] == 0x1000 and m["rd"] == 8 and m["expected"] == 5 and m["observed"] == 4,
      f"fails on retirement 1 at pc 0x1000, x8, expected 5, observed 4 (got {m})")
check(m.format_text({0x1000: "li s0,5"}) ==
      "t: retirement 1 at pc 0x00001000 (li s0,5): rd_wdata: write-back value for x8 "
      "[expected 0x5 (5), dut 0x4 (4)] [destination x8]",
      "the write-back diagnostic identifies the instruction, destination and both values")

print("# 3. wrong pc")
cmp_ = Lockstep("t", REF, TOHOST)
pulses(cmp_)
m = cmp_.retirement(obs(pc=0x1FFF))
check(m is not None and m["field"] == "pc", "a pc divergence is reported")

print("# 4. trap shapes in both directions")
cmp_ = Lockstep("t", REF, TOHOST)
pulses(cmp_)
for o in dut_stream()[:6]:
    cmp_.retirement(o)
m = cmp_.retirement(obs(order=7, pc=0x1018, insn=0x00100073, cycle=16, trap=0))
check(m is not None and m["field"] == "trap-expected",
      "a missing trap at the reference's exception gap is reported")
cmp_ = Lockstep("t", REF, TOHOST)
pulses(cmp_)
m = cmp_.retirement(obs(order=1, pc=0x1000, insn=0x00500413, rd_addr=8, rd_wdata=5, trap=1))
check(m is not None and m["field"] == "unexpected-trap",
      "a DUT trap where the reference retired is reported")

print("# 5. extra and missing events")
cmp_ = Lockstep("t", REF, TOHOST)
pulses(cmp_)
for o in dut_stream():
    if cmp_.retirement(o) is not None:
        break
m = cmp_.retirement(obs(order=11, pc=0x1020, cycle=21))
check(m is not None and m["field"] == "extra-event",
      "a DUT retirement after the reference is exhausted is reported")
cmp_ = Lockstep("t", REF, TOHOST)
pulses(cmp_)
for o in dut_stream()[:8]:
    cmp_.retirement(o)
m = cmp_.finish()
check(m is not None and m["kind"] == "missing-events" and m["ordinal"] == 9
      and m["pc"] == 0x2004,
      f"finish() reports the unretired reference records from the next ordinal (got {m})")

print("# 6. the CSR write observation")
cmp_ = Lockstep("t", REF, TOHOST)
cmp_.csr_pulse(MTVEC, 0x2000 | 1, 13)  # the value CVE2 commits (WARL of 0x2001)
m = None
for o in dut_stream()[:5]:
    m = cmp_.retirement(o) or m
check(m is None, "an mtvec write matches through its WARL projection")
cmp_ = Lockstep("t", REF, TOHOST)
for o in dut_stream()[:5]:
    m = cmp_.retirement(o) or m
    if m:
        break
check(m is not None and m["field"] == "csr-mtvec",
      "a reference CSR write with no committed write observed is reported")
cmp_ = Lockstep("t", REF, TOHOST)
pulses(cmp_)
m = None
for o in dut_stream()[:9]:
    m = cmp_.retirement(o) or m
check(m is None, "mret matches: mstatus one cycle late (MPP projected to M on CVE2), mstatush (0x310) skipped as unobserved")
check(MSTATUS in OBSERVED_CSRS and 0x310 not in OBSERVED_CSRS,
      "the observed set is the machine CSRs CVE2 can pulse")
check(project_csr(MSTATUS, 0x80, MRET_ENC) == 0x1880
      and project_csr(MSTATUS, 0x80) == 0x80,
      "the mret projection sets only MPP; an explicit csrw mstatus compares unprojected MPP")

print("# 7. sub-word store value normalization and instruction masking")
cmp_ = Lockstep("t", REF, TOHOST)
pulses(cmp_)
m = None
for o in dut_stream()[:4]:
    m = cmp_.retirement(o) or m
check(m is None, "a sub-word store's raw rs2 value matches masked to its width")
cmp_ = Lockstep("t", REF, TOHOST)
pulses(cmp_)
CREF = [ref(pc=0x1000, enc=0x0501, len=2, rd=8, rd_val=5),
        ref(pc=0x1002, enc=0x00C02023, stores=[(TOHOST, 1)])]
cmp_ = Lockstep("t", CREF, TOHOST)
m = cmp_.retirement(obs(order=1, pc=0x1000, insn=0xABCD_0501, rd_addr=8, rd_wdata=5))
check(m is None, "a compressed instruction matches masked to its 16-bit reference encoding")
m2 = cmp_.retirement(obs(order=2, pc=0x1002, insn=0x00C02023, mem_wmask=0xF,
                         mem_addr=TOHOST, mem_wdata=1))
check(m2 is None and cmp_.complete, "the tohost store completes the run")

print("# 8. retirement order")
cmp_ = Lockstep("t", REF, TOHOST)
cmp_.retirement(obs(cycle=10))
m = cmp_.retirement(obs(order=3, pc=0x1004, cycle=11))
check(m is not None and m["field"] == "order", "an order jump is reported")

print("# 9. timeout while waiting for the next retirement")
cmp_ = Lockstep("t", REF, TOHOST)
for o in dut_stream()[:2]:
    cmp_.retirement(o)
m = cmp_.timeout(50)
check(m["pc"] is None and m["ordinal"] == 3 and m.format_text({0x1004: "mv zero,s0"}) ==
      "t: retirement 3 (PC unavailable): timeout: no retiring store to tohost 0x80001000 "
      "within 50 cycles (2 retirements compared, 8 reference records left)",
      "timeout without a retiring PC reports the cycle limit and reference progress")

print()
print(f"test_lockstep_compare: {PASS} passed, {FAIL} failed")
sys.exit(1 if FAIL else 0)
