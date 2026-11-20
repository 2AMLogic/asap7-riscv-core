"""Lockstep comparator: Spike reference records in, DUT RVFI observations in,
first divergence out (issue #206, part of #204).

Pure logic, no simulator: verification/core/test_lockstep.py drives it with
samples read from the DUT each cycle, and test_lockstep_compare.py unit-tests
it offline. The reference records are spike_trace.py's output verbatim:

    {"pc": .., "enc": .., "len": 2|4, "priv": 3, "rd": ..|None, "rd_val": ..,
     "csr": [(num, name, val)], "loads": [addr], "stores": [(addr, val)]}
    {"exception": True, "epc": ..|None, "handler": ..}

The DUT observation is one dict per retirement (fields as read from the RVFI
port and the CSR observation, all sampled in the same read-only cycle):

    {"order", "pc", "insn", "trap", "priv", "rd_addr", "rd_wdata",
     "mem_rmask", "mem_wmask", "mem_addr", "mem_wdata", "cycle"}

Mapping rules, established against the pinned CVE2 RTL (cve2_core.sv,
cve2_cs_registers.sv at the reuse.lock.json commit):

- A synchronous exception never retires on the reference (spike_trace emits an
  exception record for the gap); on the DUT the flushed instruction IS kept in
  the RVFI tracking pipeline with rvfi_trap=1 ("Instructions that take traps
  flush the pipeline so ordinarily wouldn't be seen to retire"). So a
  reference exception record must map to a DUT retirement with trap=1 at the
  epc, and the following record's pc check enforces the handler entry.
- A write to x0 never appears in the reference (architecturally discarded) and
  the DUT reports rd_addr=0, so both sides normalize to rd=x0, value 0.
- Compressed instructions: the reference enc is the 16-bit encoding; the DUT
  rvfi_insn is compared masked to the reference length.
- Sub-word stores: rvfi_mem_wdata is the raw rs2 value, not lane-shifted -
  cve2_core.sv taps lsu_wdata (id_stage's rf_rdata_b_fwd) for the RVFI
  capture, upstream of the byte-lane shift the LSU applies to the bus - so
  the observed value is masked to the store's width (wmask popcount) and
  compared to the reference value as is.
- CSR effects: RVFI has no general CSR write channel, so the committed effect
  is checked with CVE2's own verification-only observation in
  cve2_cs_registers.sv (`RVFI_CONNECT`: rvfi_<name>_csr_wmask/_wdata pulse for
  one cycle when the register file commits a write, carrying the DUT's
  post-WARL next value). A reference CSR write passes only if a matching pulse
  is observed within WINDOW cycles of the owning retirement. CVE2's WARL
  projections are applied to the reference value first:
    mtvec  {v[31:8], 6'b0, 2'b01}   (MODE forced vectored, 256-byte base)
    mepc   {v[31:1], 1'b0}          (bit 0 forced to 0)
    mcause {v[31], v[5:0]}          (implementable cause bits)
  mstatus/mie/mscratch/mtval keep the written value. Reference writes to CSRs
  CVE2 gives no write observation (everything outside OBSERVED_CSRS, e.g.
  mstatush on mret, whose wmask is hardcoded 0) are skipped: the DUT commits
  no value a comparison could read, and mret's other effect (mstatus) is
  still checked. Hardware CSR writes with no reference record (trap entry
  updating mepc/mcause/mtval/mstatus, mret's delayed mstatus write) only ever
  add unmatched pulses, which age out; the reference's own view of those
  values is checked through the handler's csrr read-backs (rd comparison).
- Loads and stores: presence is decoded from the instruction encoding the
  retirement already matched, not from rvfi_mem_rmask: cve2_core.sv decodes
  rvfi_mem_mask_int from lsu_type with no memory-op gate, so rmask (and
  mem_addr, which is muxed from the ALU result) carry operand garbage on
  non-memory instructions. rvfi_mem_wmask IS gated by the bus write
  (data_we_o), so for a decoded store the wmask/addr/value are compared, and
  for a decoded load the rmask must be nonzero and the address must match.
  The loaded value is checked as the load's rd_wdata (RVFI reports the
  architecturally loaded value there), not as rvfi_mem_rdata.

End conditions: the reference's last record is the retiring store to tohost
(spike_trace guarantees it); when that record matches, the run is complete.
A DUT retirement with the reference exhausted, or a DUT stop with reference
records left, is a mismatch ("extra" / "missing").
"""

WINDOW = 8  # cycles a CSR pulse may sit from its owning retirement

MTVEC, MSCRATCH, MEPC, MCAUSE, MTVAL, MSTATUS, MIE = 0x305, 0x340, 0x341, 0x342, 0x343, 0x300, 0x304


MRET_ENC = 0x30200073
# mstatus bits cve2_cs_registers.sv's extended views drive: MIE, MPIE, MPP,
# MPRV, TW at their architectural positions.
MSTATUS_IMPL = (1 << 3) | (1 << 7) | (3 << 11) | (1 << 17) | (1 << 21)


def project_csr(num, val, enc=None):
    """The value CVE2 commits for a CSR write of <val> to <num> (its WARL).

    <enc> is the owning instruction's encoding, needed for mret: CVE2
    implements no U-mode, so mret sets MPP to M (the least privilege it
    supports - cve2_cs_registers.sv's csr_restore_mret keeps mstatus_q.mpp),
    where Spike, which implements U-mode, writes 0. The privileged spec's
    "MPP is set to the least-privileged supported mode" makes both legal;
    mret's other mstatus effects (MIE<-MPIE, MPIE<-1) are unambiguous and
    stay compared bit for bit."""
    if num == MTVEC:
        return (val & 0xFFFF_FF00) | 0x01
    if num == MEPC:
        return val & 0xFFFF_FFFE
    if num == MCAUSE:
        return (val & 0x8000_0000) | (val & 0x3F)
    if num == MSTATUS:
        v = val & MSTATUS_IMPL  # every unimplemented bit commits nothing
        if enc == MRET_ENC:
            v |= 3 << 11
        return v
    return val & 0xFFFF_FFFF


# The CSRs cve2_cs_registers.sv's RVFI_CONNECT can pulse a write mask for.
# Everything else (mstatush, dcsr, dpc, dscratch*, mip, misa) has either an
# empty mask term or no machine-write path in these programs, and reference
# writes there are skipped rather than falsely failed.
OBSERVED_CSRS = {MSTATUS, MIE, MTVEC, MSCRATCH, MEPC, MCAUSE, MTVAL}

CSR_NAMES = {MSTATUS: "mstatus", MIE: "mie", MTVEC: "mtvec", MSCRATCH: "mscratch",
             MEPC: "mepc", MCAUSE: "mcause", MTVAL: "mtval"}


def _popcount(x):
    return bin(x).count("1")


def _is_mem(enc):
    """(is_load, is_store) decoded from the RV32IMC encoding: the memory
    opcodes plus the four compressed loads/stores. cve2_core.sv leaves
    rvfi_mem_mask_int undecoded for non-memory instructions, so presence
    cannot come from rmask."""
    if enc & 3 == 3:
        return (enc & 0x7F) == 0x03, (enc & 0x7F) == 0x23
    q, f3 = enc & 3, (enc >> 13) & 7
    if q == 0:
        return f3 == 2, f3 == 6          # c.lw / c.sw
    if q == 2:
        return f3 == 2, f3 == 6          # c.lwsp / c.swsp
    return False, False


def _hex(v):
    return "-" if v is None else f"{v:#x}"


def _fmt(v):
    if v is None:
        return "none"
    return f"{v:#x} ({v})" if isinstance(v, int) else str(v)


class Mismatch(dict):
    """The first divergence, as structured data and a diagnostic for the bench."""

    def format_text(self, disasm):
        pc = self["pc"]
        where = "(PC unavailable)"
        if pc is not None:
            where = f"at pc {pc:#010x} ({disasm.get(pc, '?')})"
        text = (f"{self['name']}: retirement {self['ordinal']} {where}: "
                f"{self['field']}: {self['detail']}")
        if self["expected"] is not None or self["observed"] is not None:
            text += f" [expected {_fmt(self['expected'])}, dut {_fmt(self['observed'])}]"
        if self["rd"] is not None:
            text += f" [destination x{self['rd']}]"
        return text


class Lockstep:
    """Compare one program's DUT retirements against its reference trace."""

    def __init__(self, name, ref, tohost):
        self.name = name
        self.ref = ref
        self.tohost = tohost
        self.idx = 0            # next reference record
        self.n = 0              # DUT retirements consumed
        self.complete = False   # the retiring tohost store matched
        self._order = None
        self._pulses = []       # unconsumed (cycle, num, wdata) observations

    # -- DUT-side inputs -----------------------------------------------------

    def csr_pulse(self, num, wdata, cycle):
        """A one-cycle rvfi_<name>_csr_wmask != 0 observation."""
        self._pulses.append((cycle, num, wdata))

    def retirement(self, obs):
        """One DUT retirement. Returns Mismatch or None; sets self.complete."""
        self.n += 1
        if self._order is None:
            self._order = obs["order"]
        elif obs["order"] != self._order + self.n - 1:
            return self._bad("order", obs, "retirement order jumped",
                             self._order + self.n - 1, obs["order"])
        if self.idx >= len(self.ref):
            return self._bad("extra-event", obs,
                             "the DUT retired after the reference was exhausted "
                             f"({len(self.ref)} records)")
        r = self.ref[self.idx]

        if r.get("exception"):
            if not obs["trap"]:
                return self._bad("trap-expected", obs,
                                 "the reference has a synchronous trap here (no "
                                 f"retirement) entering the handler at {r['handler']:#x}")
            if r["epc"] is not None and obs["pc"] != r["epc"]:
                return self._bad("pc", obs, "trapping pc (reference epc)",
                                 r["epc"], obs["pc"])
            self.idx += 1
            return None
        if obs["trap"]:
            return self._bad("unexpected-trap", obs,
                             "the DUT trapped where the reference retired")
        if obs["pc"] != r["pc"]:
            return self._bad("pc", obs, "pc", r["pc"], obs["pc"])
        mask = (1 << (8 * r["len"])) - 1
        if obs["insn"] & mask != r["enc"]:
            return self._bad("insn", obs, "instruction bits "
                             f"({r['len']} bytes)", r["enc"] & mask, obs["insn"] & mask)
        if obs["priv"] != r["priv"]:
            return self._bad("priv", obs, "privilege mode", r["priv"], obs["priv"])

        rd, rd_val = r["rd"] or 0, (r["rd_val"] or 0) if r["rd"] not in (None, 0) else 0
        if obs["rd_addr"] != rd:
            return self._bad("rd_addr", obs, "integer destination", rd, obs["rd_addr"])
        if obs["rd_wdata"] != rd_val:
            return self._bad("rd_wdata", obs, f"write-back value for x{rd}",
                             rd_val, obs["rd_wdata"])

        is_load, is_store = _is_mem(r["enc"])
        if is_load != bool(r["loads"]):
            want = "loads " + ", ".join(_hex(a) for a in r["loads"]) if r["loads"] else "loads nothing"
            return self._bad("load" if r["loads"] else "extra-load", obs,
                             "reference " + want)
        if is_load:
            if not obs["mem_rmask"]:
                return self._bad("load", obs, "rvfi_mem_rmask is 0 for a decoded load")
            if obs["mem_addr"] not in r["loads"]:
                return self._bad("load-addr", obs, "load address",
                                 r["loads"][0], obs["mem_addr"])
        if is_store != bool(r["stores"]):
            want = "stores " + ", ".join(_hex(a) for a, _ in r["stores"]) if r["stores"] else "stores nothing"
            return self._bad("store" if r["stores"] else "extra-store", obs,
                             "reference " + want)
        if is_store:
            addrs = {a for a, _ in r["stores"]}
            if obs["mem_addr"] not in addrs:
                return self._bad("store-addr", obs, "store address",
                                 r["stores"][0][0], obs["mem_addr"])
            w = obs["mem_wdata"] & ((1 << (8 * _popcount(obs["mem_wmask"]))) - 1)
            if len(r["stores"]) == 1 and w != r["stores"][0][1]:
                return self._bad("store-value", obs,
                                 f"stored value at {r['stores'][0][0]:#x}",
                                 r["stores"][0][1], w)

        for num, name, val in r["csr"]:
            if num not in OBSERVED_CSRS:
                continue
            want = project_csr(num, val, r.get("enc"))
            hit = None
            for p in self._pulses:
                if p[1] == num and p[2] == want and abs(p[0] - obs["cycle"]) <= WINDOW:
                    hit = p
                    break
            if hit is None:
                seen = ", ".join(f"{CSR_NAMES[p[1]]}={p[2]:#x}@cycle{p[0]}"
                                 for p in self._pulses) or "none observed"
                return self._bad(f"csr-{name}", obs,
                                 f"CSR write {name}={val:#x} (reference projects "
                                 f"{want:#x}); observed pulses: {seen}", want, None)
            self._pulses.remove(hit)
        self._pulses = [p for p in self._pulses if obs["cycle"] - p[0] <= WINDOW]

        self.idx += 1
        if self.idx == len(self.ref) and r["stores"] and r["stores"][-1][0] == self.tohost:
            self.complete = True
        return None

    def finish(self):
        """Report unconsumed reference records at the end of a DUT stream."""
        if self.complete or self.idx >= len(self.ref):
            return None
        r = self.ref[self.idx]
        left = len(self.ref) - self.idx
        pc = r.get("epc") if r.get("exception") else r.get("pc")
        where = f" at {pc:#x}" if pc is not None else ""
        return Mismatch(kind="missing-events", name=self.name, ordinal=self.idx + 1,
                        pc=pc, field="retirement", rd=None,
                        detail=f"{left} reference record(s) never retired; the next is "
                               f"ordinal {self.idx + 1}{where}",
                        expected=None, observed=None)

    # -- reporting -------------------------------------------------------------

    def timeout(self, cycles):
        """Report progress when the cycle limit expires before the tohost store."""
        return Mismatch(kind="timeout", name=self.name, ordinal=self.n + 1, pc=None,
                        field="timeout", rd=None,
                        detail=f"no retiring store to tohost {self.tohost:#x} within "
                               f"{cycles} cycles ({self.n} retirements compared, "
                               f"{len(self.ref) - self.idx} reference records left)",
                        expected=None, observed=None)

    def _bad(self, field, obs, what, expected=None, observed=None):
        return Mismatch(kind="lockstep-divergence", name=self.name, ordinal=self.n,
                        pc=obs["pc"], field=field, rd=obs.get("rd_addr"),
                        detail=what, expected=expected, observed=observed)
