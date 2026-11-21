# Work Log

Chronological record of merged PRs and closed issues, maintained by the Guide
triage role. Newest first.

### 2026-11-20

- **Issue #222** (closed): Item 9 re-attest guidance still names Verilator as a host prerequisite
- **PR #228**: docs: drop Verilator from item 9 re-attest host prerequisites
- **Issue #219** (closed): Require Verilator only for smoke lint in verification/run.sh
- **PR #221**: fix(verification): require Verilator only for the smoke lint path
- **Issue #204** (closed): Lockstep check against Spike: compare every retired instruction in cocotb
- **PR #218**: feat(verification): compare every CVE2 retirement with Spike in cocotb
- **Issue #206** (closed): Compare CVE2 RVFI retirements with Spike in the cocotb core suite
- **PR #215**: fix(verification): pin fv.sh's negative control to the injected mismatch
- **Issue #213** (closed): fv.sh's negative control accepts any genuine test failure, not the injected mismatch
- **PR #212**: fix(verification): require JUnit evidence for negative-control exits
- **Issue #208** (closed): Remove duplicate negative-control checks that accept runner startup failures
- **PR #210**: feat(verification): generate a pinned Spike retirement trace for the core test ELFs
- **Issue #205** (closed): Generate a pinned Spike retirement trace for the CVE2 test ELFs
- **PR #203**: fix(flow): compare parsed SIMPLE FF and TT cell dictionaries directly
- **Issue #202** (closed): Compare parsed SIMPLE FF and TT timing tables directly
- **PR #201**: fix(flow): allocate every self-test fixture under a parent-owned scratch root
- **Issue #199** (closed): Remove ineffective fixture tracking from the sv2v and flow library self-tests
- **PR #190**: docs: propose attestation-retention decision and align item 10 recipe
- **Issue #89** (closed): Record when an attestation envelope may be regenerated in place
- **PR #197**: feat(flow): publish the latch-mapped 2026-11-20 core netlist and re-attest item 1

### 2026-11-19

- **PR #192**: docs: correct shared-archtest 0012 citation claim in spec/README.md
- **Issue #191** (closed): Correct the shared-archtest 0012 citation guidance in spec/README.md

### 2026-11-18

- **PR #187**: ci: add merge_group triggers to harness and signoff workflows
- **Issue #186** (closed): Merge queue: add the merge_group trigger to the required-check workflow(s)

### 2026-11-17

- **PR #128**: fix(signoff): label non-path attestation check rows by check kind in the drift map
- **Issue #117** (closed): Attestation-gate drift messages print "command " with an empty name for the non-path check rows
- **PR #182**: chore(loom): resync installed Loom to v0.19.1306
- **PR #179**: chore(evidence): item 9 attests subprocess-reached harness inputs
- **Issue #178** (closed): attest/item9.json's closure walk is source/import-only: four subprocess-reached repo inputs are still unattested
- **PR #154**: feat(attest): item 9 attests the harness's sourced inputs; decision 0015
- **Issue #145** (closed): item 9's attestation inventory omits five inputs its attested harness cannot run without

### 2026-11-16

- **PR #167**: chore(loom): resync installed Loom to v0.19.1302
- **PR #173**: docs: drop hand-kept queue sections from ROADMAP.md, point at WORK_PLAN.md and #6
- **Issue #165** (closed): Retire the hand-kept queue state in ROADMAP.md: it restates WORK_PLAN.md and is already stale
- **Issue #148** (closed): A signoff verdict is only valid for the merge ref it ran against: a stale green check turned main red for seven runs
- **PR #169**: docs: cite run.sh constructs, not line ranges, in smoke analysis notes
- **Issue #160** (closed): flow/smoke/analysis line citations into run.sh are stale: 3 of 4 in the LVS analysis point at the wrong code
- **PR #166**: config: record branchProtection block mirroring live required-checks ruleset
- **PR #147**: flow: guard core records for host-path leaks, redact ff_simple_check through record_lib.py
- **Issue #106** (closed): Core records are never checked for host-path leaks, and flow/core/ff_simple_check.sh redacts nothing at all
- **PR #137**: refactor(verification): one source of truth for the ASAP7 cell-group set
- **Issue #100** (closed): One source of truth for the ASAP7 cell-group set: it is restated in setup.sh and archtest_common.py
- **PR #127**: refactor(flow): one record-state predicate, one deck-hash gate
- **Issue #115** (closed): Three duplicated record-state reads in the smoke flow, and two unreachable-false guards
- **Issue #141** (closed): CLAUDE.md documents the re-attest obligation for item 10 only; item 9's attested testbench paths get no warning
- **PR #161**: docs: cover item 9 re-attest obligation and manifest inventory-hash binding
- **Issue #163** (closed): rtl/README.md cites archtest_common.py's CELL_GROUPS, a constant #137 deletes
- **PR #164**: docs: point rtl README's cell-group set reference at tool-versions.txt pins
- **Issue #158** (closed): README status paragraph still names the 2026-11-03 netlist as the arch-test DUT after #157 re-pointed it
- **PR #162**: docs: point README arch-test status at the 2026-11-14 netlist and its 2026-11-15 record
- **Issue #112** (closed): Test the shared fetch_checked download contract — CI never executes it today
- **PR #156**: test(flow): cover the CVE2 fetch contract's three outcomes and its staging
- **Issue #149** (closed): flow/lib_test.sh: the FAKES cleanup trap is dead code — every scratch dir survives the run
- **PR #155**: test: fix lib_test.sh's dead cleanup trap and vacuous negative refusals
- **Issue #107** (closed): The flow-record regeneration check that every flow proposal names as its acceptance criterion cannot run in a sweep worktree
- **PR #129**: docs(spec): ratify flow-record regeneration venue and citation form as decision 0015
- **Issue #118** (closed): verification/core/fv.py records absolute host paths: a fourth record writer with no redaction
- **PR #144**: fix(verification): redact host paths in klt-fv records, guard fv.sh against leaks
- **Issue #120** (closed): One flow-lib home for the record provenance rows: two drivers hand-roll tool-versions.txt and disagree on the klt row
- **PR #136**: refactor(flow): one flow-lib home for the record provenance rows
- **Issue #159** (closed): attest/item9.json omits flow/lib.sh, which flow/smoke/run.sh sources and cannot run without

### 2026-11-15

- **Issue #98** (closed): Explain the LVS mismatch on the counter smoke layout (19 topology errors)
- **PR #123**: docs: classify the 19 LVS topology errors on the 2026-11-05 counter smoke record
- **PR #157**: verify(core): simulate the 2026-11-14 netlist, re-attest item 9, defer the item-1 tail with cause
- **Issue #130** (closed): spec/README.md's enumerated bare-`decision 0012` citation inventory is already stale against main
- **PR #153**: docs(spec): replace rotting bare-citation inventory with invariant + on-demand grep
- **Issue #133** (closed): Run the all-ran output-equality check for #91: the yosys/ABC hang clears with a short TMPDIR
- **PR #151**: feat(flow): append the all-ran 2026-11-15 smoke record set and output-equality analysis
- **Issue #126** (closed): flow/core/sv2v.sh still reads its pins with head -1, and its non-empty guard cannot run
- **PR #142**: fix: read the sv2v pin label-scoped and fail closed naming the pin
- **Issue #96** (closed): Account for the one unmapped $_DLATCH_N_ instance in the core netlist
- **PR #138**: fix(synth): map the cve2_clock_gate latch onto DLLx1_ASAP7_75t_R via klt latch_map
- **Issue #102** (closed): README's Reproduce table cites the superseded 2026-10-23 smoke record and says par is not_run
- **PR #143**: docs: cite the records of record in README status and Reproduce table
- **Issue #105** (closed): flow/core/synth.sh --check picks the newest record directory and cannot compare when it holds no netlist.v
- **PR #140**: fix(synth): pick --check's comparison target by content, not directory order
- **Issue #91** (closed): Narrow the mkrecord.py interface in flow/smoke/run.sh: single-build residue from #87
- **PR #134**: refactor(smoke): derive klt_build in mkrecord.py, add record_ran/deck_hash helpers
- **Issue #152** (closed): flow/lib_test.sh: the fail-closed negative cases pass when the helper is absent, not only when it refuses
- **Issue #125** (closed): No CI step runs any shell self-test: flow/lib_test.sh is committed but never executed
- **PR #150**: ci: run the repo's shell self-tests in the harness job
- **Issue #113** (closed): Split the .7z Liberty extractor out of build_liberty_overlay: flow/core/ff_simple_check.sh is a third copy
- **PR #146**: refactor: split extract_rvt_liberty with a counted fail-closed guard out of build_liberty_overlay
- **Issue #131** (closed): 3 of 5 `manifests/asap7-riscv-core.json` content_hash pins do not match their evidence file's bytes
- **Issue #124** (closed): signoff is red on main: evidence/item9.json pins a flow/smoke/run.sh hash that no longer matches
- **Issue #135** (closed): Decision needed: P&R-time handling of the clock-gate latch (committed netlist is unplaceable; pinned ASAP7 library has no latch cell)
- **PR #139**: chore(evidence): re-attest item 9 envelope over run.sh and setup.sh drift
- **Issue #116** (closed): spec/README.md still describes decisions/ as "(0001-0009)"; the directory holds 0001-0014
- **Issue #90** (closed): Two decision records share number 0012, making bare "decision 0012" citations ambiguous
- **PR #121**: docs: link the ambiguous `decision 0012` citations and guard duplicate decision numbers
- **PR #94**: docs: roadmap as of 2026-11-13

### 2026-11-14

- **PR #119**: fix(synth): name the cell_library asap7sc7p5t_28_R so klt maps tie cells
- **PR #114**: refactor(flow): label-anchored, fail-closed pin reads in one flow-lib home
- **PR #110**: ci: gate T1 item 9's attestation envelope with klt --check, and re-attest it
- **PR #108**: refactor(flow): one shared record redactor and writer for both flow record writers
- **PR #104**: docs(smoke): classify the 549 DRC violations on the 2026-11-05 counter layout
- **PR #109**: refactor: one hash-checked download primitive shared by flow/ and verification/
- **PR #92**: ci: make item-10 attestation drift self-explanatory and state the rule
- **Issue #101** (closed): One flow-lib home for the klt pin read and the report-usability check, and two spec reads that depend on document position
- **Issue #99** (closed): Consolidate the duplicated record host-path redactor in flow/smoke/run.sh and flow/core/synth.sh
- **Issue #97** (closed): Classify the 549 DRC violations on the counter smoke layout by rule and cause
- **Issue #95** (closed): Re-run core synthesis on the pinned klt 0.9.0 with a cell_library key that gets tie cells
- **Issue #93** (closed): Three hash-checked downloaders with three contracts: consolidate fetch_checked, fetch.sh and sv2v.sh
- **Issue #88** (closed): evidence/item9.json records stale content hashes for 5 of 11 attested testbenches, and nothing re-checks it
- **Issue #83** (closed): Guide docs pass reds the item-10 signoff gate whenever it edits README.md
- **PR #87**: refactor(smoke): drop the 0.8.0 comparison-build fallback from the smoke flow
- **Issue #85** (closed): Remove the 0.8.0 comparison-build fallback from flow/smoke/run.sh: the pin now does every step
- **PR #86**: refactor(verification): one sourced lib for die/pin/check_version
- **Issue #84** (closed): Consolidate duplicated verification/ shell helpers and drop a dead function in flow/smoke/run.sh

### 2026-11-12

- **PR #78**: Bump Repo Skills 0.25.10 -> 0.26.1

### 2026-11-07

- **PR #75**: Bump Repo Skills 0.25.1 -> 0.25.10

### 2026-11-06

- **PR #73**: feat(verification): run arch tests on the gate-level netlist (--core --gate)
- **Issue #70** (closed): verification: run the riscv-arch-test suite on the committed ASAP7 gate-level netlist
- **PR #72**: docs: record deck follow-ups and pin the LVS deck hash
- **Issue #71** (closed): Decision 0012 follow-ups: DRC record released flag, stale dev-build line, PAD coverage claim, LVS deck pin
- **PR #66**: feat(flow): re-run smoke flow on klt 0.9.0 with par ok and counter-layout checks
- **Issue #17** (closed): Follow-on from PR #16: place-and-route on the counter smoke DUT (par.json is not_run)
- **PR #68**: refactor(verification): share arch-test driver setup and drop debug hooks
- **Issue #65** (closed): Consolidate duplicate arch-test drivers: runner.py vs fv.py

### 2026-11-05

- The klt 0.9.0 smoke run for #17 produced DEF and GDS for the counter (`par` reported `ok`). With the re-pinned DRC deck (decision 0012, `sha256:14f146f0…`, 267 categories), DRC reported 549 violations across seven rule categories. LVS reported `mismatch` with 19 topology errors. ERC reported `not_checked`. STA remains predicted. [Smoke run records](flow/smoke/records/2026-11-05/)
- **PR #63**: feat: run core arch-test suite through klt functional-verification
- **Issue #59** (closed): Run the riscv-arch-test core suite through klt functional-verification and commit the report
- **PR #61**: feat: add SIMPLE RVT FF Liberty comparison script and record
- **Issue #60** (closed): Gather evidence on whether the SIMPLE RVT FF Liberty is characterised at 0.77 V / 0 °C

### 2026-11-03

- **PR #56**: refactor: share PDK pin and Liberty-merge helpers between flow scripts
- **PR #55**: refactor: share sv2v pin/fetch and CVE2 conversion across synth, setup and runner
- **Issue #53** (closed): Consolidate duplicated sv2v pin/fetch and CVE2 conversion closure (synth.sh, setup.sh, runner.py)
- **Issue #46** (closed): Dedupe shared PDK/pin helpers between flow/smoke/run.sh and flow/core/synth.sh
- **PR #52**: test: pin clang for I-jalr-01, diagnose C-cebreak-01, re-attest item 9
- **Issue #50** (closed): Diagnose C-cebreak-01 hang on cve2_rv32imc_wrapper in the arch-test core bench
- **PR #49**: test: run riscv-arch-test I/M/C on the RV32IMC core and attest T1 item 9
- **Issue #27** (closed): T1 item 9 (testbenches shipped): core-level RV32IMC test suite with cold-start invocation and --attest 9 inventory
- **PR #45**: feat(flow): synthesize unmodified CVE2 RV32IMC and attest design sources
- **Issue #25** (closed): T1 item 1 (design sources): fetch the pinned CVE2 RTL and synthesize cve2_top to a committed ASAP7 gate-level netlist

### 2026-11-01

- **PR #43**: Bump Repo Skills 0.24.7 -> 0.25.1

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
