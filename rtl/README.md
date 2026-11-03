# rtl

The core is the unmodified upstream CVE2 (`openhwgroup/cve2@d7f21568`), which is
**not vendored**: `flow/core/fetch.sh` downloads the file closure of `cve2_top`
listed in [`../reuse.lock.json`](../reuse.lock.json) and refuses any file whose
sha256 differs.

| File | Role |
|---|---|
| `cve2_rv32imc_wrapper.sv` | Configuration wrapper: `RV32E=0`, `RV32M=RV32MFast`, no debug module, no CV-X-IF. The only RTL authored here. |
| `inventory.json` | T1 item 1 attestation inventory for `klt signoff --attest 1`. |

Synthesis and the committed gate-level netlist: [`../flow/core/`](../flow/core/).
Decision record: [`../spec/decisions/0010-sv2v-and-core-closure.md`](../spec/decisions/0010-sv2v-and-core-closure.md).
