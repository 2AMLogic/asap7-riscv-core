"""Placeholder cocotb test for verification/smoke/counter.sv.

Proves the flow only; deleted or replaced when the core is pinned.
SMOKE_NEGATIVE_CONTROL=1 makes the final assertion deliberately fail.
"""

import os

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge


@cocotb.test()
async def test_counts_when_enabled(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    dut.en.value = 0
    dut.rst_n.value = 0
    for _ in range(2):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)
    assert int(dut.count.value) == 0

    dut.en.value = 1
    for _ in range(5):
        await RisingEdge(dut.clk)
    dut.en.value = 0
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)

    expected = 99 if os.environ.get("SMOKE_NEGATIVE_CONTROL") == "1" else 5
    assert int(dut.count.value) == expected, f"count={int(dut.count.value)}, expected {expected}"
