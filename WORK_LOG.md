# Work Log

Chronological record of merged PRs and closed issues, maintained by the Guide
triage role. Newest first.

### 2026-10-27

- **PR #41**: build: pin smoke comparison build to klayout-tools 0.8.0
- **Issue #40** (closed): Bump klayout-tools pin 6bb7cf233677 → 0.8.0
- **PR #37**: feat: attest repo hygiene, add harness CI, bump klt pin to 0.8.0
- **PR #38**: docs(spec): record T1 item 6 as not applicable and bump signoff grader to 0.8.0
- **Issue #26** (closed): T1 item 10 (repo hygiene): README reproduction steps, harness in CI, and a klt signoff --attest 10 envelope
- **Issue #33** (closed): T1 item 6 (statistical rows): commit the hash-bound "not applicable" statement for the ratified spec

### 2026-10-24

- **PR #7**: ci: add klt signoff block manifest and verdict-record freshness check
- **Issue #5** (closed): Commit a T1 block manifest and a klt signoff CI job (T1 item 10)

### 2026-10-23

- **PR #19**: fix: wire package.json check/test/lint scripts to verification/run.sh
- **PR #16**: feat: add ASAP7 smoke flow script with step records and a dated bring-up re-run
- **PR #15**: spec: adopt the sky130-riscv-soc CVE2 core pin
- **Issue #18** (closed): Replace vacuous package.json check scripts (check:ci/test/lint always exit 0)
- **Issue #14** (closed): Add an ASAP7 flow smoke on the counter DUT and re-run the bring-up under current klt (T1 items 2-4, 11 groundwork)
- **Issue #13** (closed): Adopt sky130-riscv-soc's ratified CVE2 core pin (decision 0006 trigger met) (T1 item 1)

### 2026-10-21

- **PR #10**: Bump Repo Skills 0.24.3 -> 0.24.7

### 2026-10-20

- **PR #8**: feat: add PDK-free cocotb + Icarus verification harness skeleton
- **Issue #4** (closed): Add a PDK-free cocotb + Icarus verification harness skeleton (T1 item 9)

### 2026-10-17

- **PR #9**: docs(spec): ratify target spec and record ASAP7 bring-up under klt
- **Issue #3** (closed): Draft and ratify the target spec
- **PR #2**: chore(loom): commit the Loom merge-driver .gitattributes
- **PR #1**: chore(loom): Install Loom 0.19.1180
