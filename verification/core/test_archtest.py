"""cocotb test: run one riscv-arch-test program on cve2_rv32imc_wrapper.

Environment (set by runner.py and fv.py): ARCHTEST_JSON = the test's .json from
build_tests.py. The DUT's signature region must equal the Sail golden model's.
"""

import json
import os

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge

MAX_CYCLES = int(os.environ.get("ARCHTEST_MAX_CYCLES", "3000000"))


@cocotb.test()
async def test_signature(dut):
    with open(os.environ["ARCHTEST_JSON"]) as f:
        t = json.load(f)
    expected = list(t["expected"])
    if os.environ.get("CORE_NEGATIVE_CONTROL") == "1":
        expected[len(expected) // 2] ^= 0x1  # deliberately wrong expected word

    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    dut.rst_n.value = 0
    for _ in range(5):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1

    for cycle in range(MAX_CYCLES):
        await RisingEdge(dut.clk)
        if int(dut.done.value):
            break
    else:
        assert False, f"{t['name']}: no store to tohost within {MAX_CYCLES} cycles"
    for _ in range(4):
        await RisingEdge(dut.clk)

    base = (t["sig_begin"] - 0x80000000) // 4
    got = [int(dut.mem[base + i].value) for i in range(len(expected))]
    bad = [i for i, (g, e) in enumerate(zip(got, expected)) if g != e]
    assert not bad, (
        f"{t['name']}: {len(bad)}/{len(expected)} signature words differ, first at word "
        f"{bad[0]}: dut={got[bad[0]]:08x} sail={expected[bad[0]]:08x}"
    )
    dut._log.info(f"{t['name']}: {len(expected)} signature words match after {cycle} cycles")
