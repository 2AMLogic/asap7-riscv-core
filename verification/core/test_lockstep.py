"""cocotb bench: run one program on cve2_rv32imc_wrapper in lockstep with the
pinned Spike reference (issue #206, part of #204).

Environment (set by lockstep.py):

    LOCKSTEP_JSON  per-program file: {name, tohost, reference, disasm, inject}
    LOCKSTEP_STATS path the bench writes {retirements, cycles, mismatch} to

The DUT build is the sv2v conversion of the pinned CVE2 closure with -DRVFI
(lockstep.py converts it through flow/core/sv2v.sh, the same entry point the
attested netlist uses), so the core's RVFI retirement port
(tb_core.dut.u_cve2_top.rvfi_*) and the verification-only CSR write
observation in cve2_cs_registers.sv
(tb_core.dut.u_cve2_top.u_cve2_core.cs_registers_i.rvfi_<name>_csr_*) are
visible to the simulator without a single port added to the wrapper or tb.

Every cycle, after the clock edge in cocotb's read-only phase (settled
values): RVFI retirements and CSR write pulses are sampled and fed to
lockstep_compare.Lockstep. The run ends when the reference's retiring store
to tohost has been matched and consumed on both sides, or fails on the first
divergence, a cycle timeout, or a DUT stop with reference records left.

Negative control (inject = "ORDINAL:BIT"): the bench flips one bit of the
observed rvfi_rd_wdata at the given 1-based retirement ordinal before the
comparison, corrupting the observation path only - the DUT is untouched -
and the comparator must then fail naming that exact retirement, pc,
destination and value.
"""

import json
import os

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ReadOnly

from lockstep_compare import CSR_NAMES, Lockstep  # noqa: E402 (PYTHONPATH=core)


class Rvfi:
    """Handles for the RVFI port and the CSR write observation."""

    t_name = "?"  # the test name, for sampling diagnostics

    def __init__(self, dut):
        # hdl_toplevel is tb_core; the wrapper instance inside it is named
        # `dut`, and the core inside the wrapper `u_cve2_top`.
        top = dut.dut.u_cve2_top
        core = top.u_cve2_core
        self.valid = top.rvfi_valid
        self.order = top.rvfi_order
        self.pc = top.rvfi_pc_rdata
        self.insn = top.rvfi_insn
        self.trap = top.rvfi_trap
        self.mode = top.rvfi_mode
        self.rd_addr = top.rvfi_rd_addr
        self.rd_wdata = top.rvfi_rd_wdata
        self.mem_rmask = top.rvfi_mem_rmask
        self.mem_wmask = top.rvfi_mem_wmask
        self.mem_addr = top.rvfi_mem_addr
        self.mem_wdata = top.rvfi_mem_wdata
        csrs = core.cs_registers_i
        self.csr_obs = [(num, getattr(csrs, f"rvfi_{name}_csr_wmask"),
                         getattr(csrs, f"rvfi_{name}_csr_wdata"))
                        for num, name in CSR_NAMES.items()]

    def _int(self, sig, attr):
        try:
            return int(sig.value)
        except ValueError:
            raise AssertionError(
                f"{self.t_name}: rvfi {attr} is not 0/1 at a sampled retirement "
                f"(value {sig.value!r}); the RVFI stream is not settleable") from None

    def _csr_int(self, sig, attr):
        """CSR observation value with undriven bits read as 0: the extended
        views drive only the implemented field bits (mstatus_extended_write
        and friends are per-bit assigns), so every other bit is Z and means
        'this implementation commits nothing here', not an unknown."""
        v = sig.value
        try:
            return int(v)
        except ValueError:
            b = v.binstr
            bits = (b() if callable(b) else b).lower()
            if "x" in bits:
                raise AssertionError(
                    f"{self.t_name}: rvfi {attr} has unknown bits ({v!r}); the "
                    "CSR write observation is not settleable") from None
            return int(bits.replace("z", "0"), 2)

    def sample_csr(self, cmp_, cycle):
        for num, wmask, wdata in self.csr_obs:
            if self._int(wmask, f"rvfi_{CSR_NAMES[num]}_csr_wmask") != 0:
                cmp_.csr_pulse(num, self._csr_int(wdata, f"rvfi_{CSR_NAMES[num]}_csr_wdata"), cycle)

    def valid_now(self):
        return int(self._int(self.valid, "rvfi_valid"))

    def sample_retirement(self, cycle):
        return {"order": self._int(self.order, "rvfi_order"),
                "pc": self._int(self.pc, "rvfi_pc_rdata"),
                "insn": self._int(self.insn, "rvfi_insn"),
                "trap": self._int(self.trap, "rvfi_trap"),
                "priv": self._int(self.mode, "rvfi_mode"),
                "rd_addr": self._int(self.rd_addr, "rvfi_rd_addr"),
                "rd_wdata": self._int(self.rd_wdata, "rvfi_rd_wdata"),
                "mem_rmask": self._int(self.mem_rmask, "rvfi_mem_rmask"),
                "mem_wmask": self._int(self.mem_wmask, "rvfi_mem_wmask"),
                "mem_addr": self._int(self.mem_addr, "rvfi_mem_addr"),
                "mem_wdata": self._int(self.mem_wdata, "rvfi_mem_wdata"),
                "cycle": cycle}


@cocotb.test()
async def test_lockstep(dut):
    with open(os.environ["LOCKSTEP_JSON"]) as f:
        t = json.load(f)
    inject = t.get("inject")
    if inject:
        parts = [int(x) for x in inject.split(":")]
        inject_ordinal, inject_bit = parts[0], parts[1]
    else:
        inject_ordinal = inject_bit = None
    disasm = {int(k, 16): v for k, v in t.get("disasm", {}).items()}
    max_cycles = int(t.get("max_cycles", 3_000_000))

    cmp_ = Lockstep(t["name"], t["reference"], t["tohost"])
    rvfi = Rvfi(dut)
    Rvfi.t_name = t["name"]
    stats = {"retirements": 0, "cycles": 0, "mismatch": None}
    last_obs = [None]

    def fail(m):
        text = m.format_text(disasm)
        stats["mismatch"] = dict(m, text=text)
        stats["last_obs"] = last_obs[0]
        with open(os.environ["LOCKSTEP_STATS"], "w") as f:
            json.dump(stats, f)
        raise AssertionError(text)

    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    dut.rst_n.value = 0
    for _ in range(5):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1

    for cycle in range(max_cycles):
        await RisingEdge(dut.clk)
        await ReadOnly()
        rvfi.sample_csr(cmp_, cycle)
        if rvfi.valid_now():
            obs = rvfi.sample_retirement(cycle)
            last_obs[0] = obs
            if inject_ordinal is not None and cmp_.n + 1 == inject_ordinal:
                obs["rd_wdata"] ^= 1 << inject_bit
            m = cmp_.retirement(obs)
            stats["retirements"] = cmp_.n
            stats["cycles"] = cycle
            if m is not None:
                fail(m)
        if cmp_.complete:
            stats["retirements"] = cmp_.n
            stats["cycles"] = cycle
            with open(os.environ["LOCKSTEP_STATS"], "w") as f:
                json.dump(stats, f)
            dut._log.info(
                f"{t['name']}: {cmp_.n} retirements match the Spike reference "
                f"in lockstep through the retiring store to tohost "
                f"{t['tohost']:#x} ({cycle} cycles)")
            return
    stats["cycles"] = max_cycles
    fail(cmp_.timeout(max_cycles))
