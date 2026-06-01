# MBINIT Framework Refactor Plan

> Saved to memory. We execute this pass-by-pass. The SBINIT environment (under
> `uvm/{if,agent,env,coverage,seq,tests,tb}/sbinit/`) is the gold-standard
> template this refactor mirrors: whenever a design question comes up, look at
> how SBINIT solved it first and copy that shape.

## How to resume this work (read this first)

You are an Opus 4.8 (extra effort) agent picking up a multi-pass refactor of the
**MBINIT UVM verification environment** for an open-source UCIe 3.0 die-to-die
interconnect. RTL is Chisel→SystemVerilog (pre-elaborated, checked in); the
testbench is UVM on Cadence Xcelium. Passes 0–6 are done; **start at the first
unchecked box in the Progress tracker** (Pass 7 as of this writing).

**You are running ON the remote EECS machine with Xcelium available. Verify your
own work by running sim — do not defer it.** The previous agent worked locally
without a simulator and had to hand every change to the user to run; that
constraint is GONE. After each change, compile and run:

```bash
cd uvm
make mbinit MBTEST=test_mbinit_sanity     # fastest single-test smoke
make mbinit_all                           # full 13-test regression (the gate)
make cov_mbinit                           # coverage build (after coverage edits)
make sbinit SBTEST=test_sbinit_sanity     # only if you touch shared Makefile/SVA/pkg
```
A pass is GREEN when `make mbinit_all` reports PASS for all 13 tests. Pass/fail
is detected by `UVM_ERROR`/`UVM_FATAL`/xrun `*E` patterns in the per-test logs
under `uvm/run_logs/mbinit/`; the `.results` file there has error excerpts +
log tails for any failure. Iterate (edit → `make mbinit_all` → read the failing
log → fix) until green BEFORE moving to the next pass or writing a commit
message. Treat "compiles and all 13 pass" as the definition of done for the
framework work.

**Hard constraints (do NOT violate):**
- Do NOT edit Scala RTL (`scala/**`) or elaborated Verilog (`elab/generatedVerilog/**`,
  e.g. `MBInitSM.sv`). The RTL is the thing under test; never "fix" it to make a
  check pass.
- Do NOT edit `uvm/tb/logphy_sva.sv` (read-only, binds DUT internals).
- Do NOT touch any `mbtrain_*` files (MBTRAIN is out of scope for this refactor).
- Do NOT change the DUT port connections / instantiation in
  `uvm/tb/mbinit/mbinit_tb_top.sv` (the `MBInitSM dut (...)` block stays on `vif`;
  the Pass-3 bridge + Pass-6 `assign reset = por_reset | rst_if.reset_req` are the
  only TB-side wiring). Removing the bridge is a Pass 8/9 task, not before.
- Ground every assertion in the UCIe 3.0 spec, NOT in the RTL you are verifying.
  Known RTL/TB gaps stay represented as cfg-gated expectations; do not silently
  change MBINIT test intent.

**Per-pass etiquette (the user expects this):**
- Before a major pass, surface real architecture/design decisions to the user
  (the previous agent did this with AskUserQuestion). Don't ask about things with
  an obvious SBINIT-shaped default — just do those and mention them.
- After each pass: get it green on `make mbinit_all`, then write a commit message
  (one-line subject + a detailed paragraph body; end with
  `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`). Wait for the user
  to ask before actually committing.
- Update the Progress tracker box for the pass you finish, and append any new
  decisions to "Decisions locked" / carried-forward TODOs.

## Locked decisions / context that survives compaction
- Full typed interface split (10 split interfaces); see Baseline facts.
- Keep all 13 current MBINIT tests green throughout via a temporary **legacy
  facade**: `mbinit_env` factory-overrides `mbinit_driver` →
  `mbinit_legacy_adapter`, so `env.agent.driver` is still a `mbinit_driver`
  (the rm02/rm07/rm05 tests' `$cast` + RM-flag set keep working) but it
  decomposes each legacy `mbinit_transaction` onto the new split sequencers via
  `execute_item`. Retire only in Pass 8 once tests run on `env.vseqr`.
- DUT stays on monolithic `mbinit_if` (`vif`) with a bidirectional bridge in
  `mbinit_tb_top` (DUT-out → split mirror; split → DUT-in driven solely by the
  new drivers' clocking blocks). The split→DUT-in direction is what resolved the
  Pass-2 **ICDCBA** double-driver error (a clocking `output` cannot also be
  continuously assigned). Remove the bridge in Pass 8/9.
- Event-driven checking (Route 2): 10 passive monitors publish ONE
  `mbinit_event` stream; scoreboard + coverage + `mbinit_event_audit` all consume
  it. Scoreboard uses **timestamp-bucket** processing (Phase A settles
  STATE/NEG_PARAMS/LANE_CTRL context, Phase B runs state-dependent checks) to
  defuse same-cycle event-ordering nondeterminism.
- `MB_EVT_STATE` is a control/state SNAPSHOT event: emitted on first post-reset
  sample and on any change of currentState OR {usingPatternWriter,
  usingPatternReader, applyLaneReversal, localPhySettings_clockPhase}; it carries
  the FULL snapshot, not just the changed field.
- Reference predictor (Pass 7) is added only now that the event stream +
  scoreboard are stable. Keep the requirement scoreboard answering "did it
  happen?" and make the predictor answer "was it legal / order-correct?".
- The framework refactor must not silently fix RTL or change MBINIT test intent;
  known gaps stay cfg-gated.

> Reference material kept locally; the user runs nothing for you anymore — you
> run it. Cadence Xcelium is on PATH via the Makefile (`XRUN`).

## Progress tracker
> **First step on resume:** run `make mbinit_all` to confirm the Pass 6 baseline
> is green (all 13 tests PASS) before starting Pass 7. Passes 4–6 were authored
> without a local simulator and marked "pending verification"; you have the
> simulator now, so establish the green baseline first, then build on it. If a
> baseline test is red, fix that before adding the predictor — a red predictor
> pass is meaningless on a red baseline.
- [x] Pass 0: Baseline (documented below)
- [x] Pass 1: Add foundation (msg pkg, event pkg, env_cfg, decode smoke test)
- [x] Pass 2: Split interfaces + TB wiring (10 split ifs as passive mirrors;
      DUT stayed on mbinit_if; ICDCBA double-driver error surfaced and was
      deferred to Pass 3 per "mirror now" decision).
- [x] Pass 3: New agents behind legacy facade + bridge flip. Decisions: DUT
      stays on vif + bidirectional bridge (temporary; remove ~Pass 8/9); legacy
      adapter `extends mbinit_driver`; tx_ready auto-stub (per-lane tx_ready
      seqrs deferred); simple driver structure (reset-aware drivers are Pass 6).
      ICDCBA resolved. All 12 tests pass under make mbinit_all.
- [x] Pass 4: Event-producing monitors (shadow). 11 monitors (lane base + req/rsp
      + ctrl + reset + cal/pw/pr/pttest_req/pttest_rsp + lane_ctrl) feed a single
      passive `mbinit_event_audit` subscriber. Event model extended with
      `svc_kind`, `pr_per_lane`/`pr_aggregate`, and split `MB_SRC_PTTEST` ->
      `_REQ`/`_RSP`. Legacy monitor/scoreboard/coverage untouched and still
      authoritative. (Authored without local sim; covered by the resume baseline run.)
- [x] Pass 5: Event-driven scoreboard + coverage (clean cutover). Scoreboard +
      coverage now consume the single mbinit_event stream via timestamp-bucket
      processing (Phase A context, Phase B checks); src-qualified witnesses;
      saw_bad_{req,rsp}_tx preserved; neg_valid tracking; cfg pulled via
      config_db("scoreboard","cfg"). Event extended with 4 control-snapshot bits
      + lane-ctrl scalars registered. Legacy mbinit_monitor instantiated but
      UNCONNECTED (retired Pass 8). Legacy scoreboard backed up at
      /tmp/mbinit_scoreboard_legacy_backup.sv. NOTE: a post-Pass-5 fix added the
      level-based RV-01 witness `saw_rv01_repairval_reader_on` in
      `apply_state()`'s MB_STATE_REPAIRVAL arm (set from `ev.using_pr`, mirroring
      the LR-03 witness) to fix 3 tests that regressed on the reader-on check;
      confirm those (sanity / lr04_reversal_apply / rm02_per_lane_reader) pass on
      the baseline run.
- [x] Pass 6: Reset and assertion layer. Sequence-driven reset injection
      (mbinit_reset_{transaction,sequencer,driver}) OR'd into the DUT reset in
      tb_top via `assign reset = por_reset | rst_if.reset_req` (DUT .reset(reset)
      port connection untouched); vseqr.reset_seqr handle + env wiring added. All
      RX/ctrl drivers AND all 5 service stubs made reset-aware (idle outputs,
      abort in-flight cleanly via fork/reset_watch + disable fork, release UVM
      handshakes; tx_ready auto-stub folded into the same fork). New SVA:
      mbinit_reset_sva (ALWAYS-ON reset-quiesce on sideband lanes + ctrl + ALL
      service buses - cal/pw/pr/pttest_req/pttest_rsp; DUT request/transmit
      quiesce + TB response idle, qualified by `(reset && $past(reset))`,
      `!== 1'b1` X-tolerant) and mbinit_stream_sva (generic payload-stability
      under back-pressure, opt-in per lane via cfg.{req,rsp}_stable_chk_en,
      default OFF -> dormant for the 12 legacy tests). Both SVA files added to the
      mbinit + cov_mbinit Makefile targets after mbinit_tb_top.sv. Strict
      requester/responder state-sync SVA left unbound (XC-03). Behavior-neutral
      for the POR-only legacy tests (reset-quiesce evaluates only at the 2nd held
      POR cycle, where all signals are 0/X). Authored without local sim; the
      always-on reset-quiesce SVA is the one thing to watch on the baseline run —
      if anything fires unexpectedly, read the firing signal/time and decide
      whether the driver/stub idle timing needs a cycle of slack (the SVA is
      spec-grounded; prefer fixing TB idle timing over weakening the assertion).
- [ ] Pass 7: MBINIT reference predictor  ← **START HERE**
- [ ] Pass 8: Test migration after framework

## Summary
Refactor MBINIT to match the SBINIT template before rewriting existing tests.
The refactor is incremental and keeps today's MBINIT tests compiling/running
through a temporary legacy facade.

Decisions locked:
- Use a full typed interface split.
- Keep current tests green during framework work.
- Add MBINIT-specific `mbinit_msg_pkg` and `mbinit_event_pkg`.
- Add the golden/reference predictor after the event stream and scoreboard
  migration are stable.

## Baseline facts (Pass 0 reference)

### MBINIT sideband message wire format (spec / SBMsgCompare layout)
- `opcode[4:0]`: `NODATA = 0x12`, `64DATA = 0x1B`
- `msgCode[21:14]`: `REQ = 0xA5`, `RESP = 0xAA`
- `msgSubcode[39:32]`:
  PARAM 0x00, CAL 0x02, RCLK_INIT 0x03, RCLK_RES 0x04, RCLK_DONE 0x08,
  RVAL_INIT 0x09, RVAL_RES 0x0A, RVAL_DONE 0x0C, LR_INIT 0x0D, LR_CLR 0x0E,
  LR_RES 0x0F, LR_DONE 0x10, RM_START 0x11, RM_END 0x13, RM_APPLY/DEG 0x14
- `msgInfo[42:40]`: success/fail nibble on RESULT responses
  (RCLK success = 0x7, RVAL success = bit40)
- `data[127:64]`: 64-bit payload on `64DATA` messages (PARAM, LR_RES).
  PARAM decode bits: `maxDataRate = data[3:0]` (abs [67:64]),
  `clockMode = data[9]` (abs [73]). Canonical PARAM payload used by tests is
  `0x23FF`.

### Scoreboard expectation flags (mirror into `mbinit_env_cfg`)
expect_param_messages=1, expect_param_common_rate=1, expect_param_negotiation=1,
expect_full_mbinit=1, expect_mbinit_through_cal=0,
expect_mbinit_through_repairclk=0, expect_repairclk_rc03=0,
expect_interop_failure=0, expect_fsm_done=1, expect_fsm_error=0,
expect_lane_ctrl_checks=1, expect_pattern_type_checks=1, expect_rv01_checks=1,
expect_lr03_pattern_reader=1, expect_lr04_apply_lane_reversal=0,
expect_rm02_per_lane_reader=0, expect_rm07_repairmb_unrepairable=0,
expect_rm05_post_repair_witness=0.

### Driver service-stub knobs (mirror into `mbinit_env_cfg`)
cal_done_repeat_cycles=3, patternReader_perLaneStatusBits=0xFFFF,
patternReader_aggregateStatus=1, pt_test_results_bits=0x0000,
plus RM scenario injects: rm02_mixed_pt_first, rm07_first_repairmb_pt_all_fault,
rm05_post_repair_pt_sequence.

### Known RTL / TB gaps (keep represented as cfg-gated expectations)
- `fsmCtrl_done` disabled in some tests.
- RM-05 / RM-08 limitations (REPAIRMB iteration / exit count not fully observable).
- `mbinit_state_sync_sva` intentionally unbound (XC-03, too tight for RTL timing).

### Current MBINIT tests (must stay green — 13 total, the `make mbinit_all` set)
test_mbinit_decode (decoder smoke test, Pass 1), test_mbinit_sanity,
test_mbinit_param_mismatch, test_mbinit_param_only, test_mbinit_cal,
test_mbinit_repairclk, test_mbinit_repairclk_unrep, test_mbinit_repairval_unrep,
test_mbinit_lr04_reversal_apply, test_mbinit_lr07_reversal_trainerror,
test_mbinit_rm02_per_lane_reader, test_mbinit_rm07_unrepairable,
test_mbinit_rm05_post_repair_persist.
(The canonical list lives in `uvm/Makefile` `MBINIT_TESTS`; that is the gate.)

## Passes

### Pass 0: Baseline
- Run and archive current `make mbinit_all` behavior.
- Treat known RTL gaps as current constraints, especially `fsmCtrl_done`
  disabled in some tests and RM-05/RM-08 limitations.
- Do not change MBINIT tests yet.

### Pass 1: Add Foundation, No Behavior Change
- Add MBINIT message helpers: opcodes, msg codes, subcodes, PARAM payload
  helpers, success/fail builders.
- Add MBINIT event model: event kind, source, direction, phase, decoded fields,
  state/service evidence, raw word.
- Add `mbinit_env_cfg` mirroring existing scoreboard expectation flags plus
  service-stub knobs.
- Add decoder unit coverage via a focused decode smoke test, but do not migrate
  existing tests.

### Pass 2: Split Interfaces And TB Wiring
- Replace monolithic DUT wiring with: `mb_ctrl_if`, `mb_req_if`, `mb_rsp_if`,
  `mb_reset_if`, `mb_cal_if`, `mb_pattern_writer_if`, `mb_pattern_reader_if`,
  `mb_pttest_req_if`, `mb_pttest_rsp_if`, `mb_lane_ctrl_if`.
- Each driven interface gets clocking blocks and `drv`/`mon` modports.
- Add a temporary passive `mbinit_if` mirror so existing diagnostics using
  `mbinit_vif` still work.
- Keep a compatibility bridge until the old single-driver path is removed.

### Pass 3: New Agents Behind Legacy Facade
- Add active requester/responder agents with independent RX and TX-ready
  sequencers/drivers, like SBINIT.
- Add control, reset, calibration, pattern-writer, pattern-reader, point-test,
  and lane-control monitor/stub components.
- Add `mbinit_virtual_sequencer` with handles for every drive channel.
- Preserve `env.agent.sequencer` and `env.agent.driver` through a legacy adapter
  that decomposes old `mbinit_transaction` items into the new sequencers.
- Preserve current RM direct-driver knobs by forwarding them into the point-test
  service policy.

### Pass 4: Event-Producing Monitors
- Convert lane monitors to publish `mbinit_event` with offered/accepted
  lifecycle tracking.
- Add passive event producers for control/state, reset, lane-control,
  calibration, pattern writer/reader, and point-test observations.
- Keep old scoreboard checks active until the event stream is validated.

### Pass 5: Event-Driven Scoreboard And Coverage
- Migrate `mbinit_scoreboard` to consume the single MBINIT event stream.
- Move expectation defaults into `mbinit_env_cfg`; keep public
  `env.scoreboard.expect_*` aliases during compatibility.
- Preserve current requirement witnesses: MP, MC, RC, RV, LR, RM, XC-05,
  pattern-type checks, RM scenario checks.
- Convert coverage to `uvm_subscriber #(mbinit_event)` with coverpoints for
  kind/source/direction/phase/state/pattern/lane-control classes.
- Reduce per-event log chatter to `UVM_HIGH`/`UVM_DEBUG`; keep one concise
  summary.

### Pass 6: Reset And Assertion Layer  ✅ DONE
- [x] Sequence-driven reset injection via `mb_reset_if`, OR'd with POR.
- [x] All RX/ctrl drivers + all 5 service stubs reset-aware (idle, abort, release).
- [x] Payload-stability SVA (`mbinit_stream_sva`), opt-in per lane via cfg.
- [x] Reset-quiesce SVA (`mbinit_reset_sva`), always-on, all surfaces.
- [x] State-sync SVA left unbound (XC-03).
See the Progress tracker Pass 6 entry for the full file list and gotchas.

### Pass 7: MBINIT Reference Predictor  ← START HERE
Goal: add `env/mbinit/mbinit_predictor.sv` — a `uvm_subscriber #(mbinit_event)`
(or analysis-export + fifo, like the scoreboard) that models the LEGAL phase
order and flags illegal/out-of-order DUT behavior, complementing the requirement
scoreboard. **Template:** copy the shape of `env/sbinit/sbinit_predictor.sv`
(read it first) and adapt to MBINIT's states/messages.

Concrete steps (verify with `make mbinit_all` after each):
1. Read `env/sbinit/sbinit_predictor.sv` and `env/sbinit/sbinit_env.sv`
   connect_phase to see exactly how the predictor is built, fed the event
   stream, and how it reports. Mirror that structure.
2. Model the legal MBINIT phase order as a small state machine keyed off
   `MB_EVT_STATE` events:
   PARAM(0) → CAL(1) → REPAIRCLK(2) → REPAIRVAL(3) → REVERSALMB(4) →
   REPAIRMB(5) → TOMBTRAIN(6), with any-state → error exits. Flag an illegal
   transition (e.g. a skip or a backward jump that the spec/RTL does not allow).
   Allowed short-circuit exits exist (PARAM→CAL-only, PARAM→REPAIRCLK-only,
   interop-not-found → error) — gate these through `mbinit_env_cfg` flags
   (`expect_mbinit_through_cal`, `expect_mbinit_through_repairclk`,
   `expect_interop_failure`, etc.) so each existing test's truncated path stays
   legal under that test's cfg. Do NOT flag a truncated run that its cfg expects.
3. Optionally validate ordering of service/message events within a state
   (e.g. a PARAM message must precede the PARAM→CAL transition; a VALTRAIN
   PatternReader request belongs in REPAIRVAL). Keep this light at first; the
   requirement scoreboard already owns the "did it happen" witnesses.
4. Gate every known RTL/TB gap through cfg (same flags the scoreboard uses) so
   the 13 existing tests stay green. The predictor must not turn a currently
   passing, intentionally-truncated test red.
5. Wire it in `mbinit_env`: instantiate, publish cfg to it via
   `uvm_config_db#(mbinit_env_cfg)::set(this,"predictor","cfg",cfg)` (mirror the
   scoreboard wiring), and fan every monitor `ev_ap` into its export inside
   `connect_event_producer` (add `ap.connect(predictor.ev_export)` there).
   Include it in `mbinit_env_pkg.sv` before `mbinit_env.sv`.
6. Report at `report_phase`: a concise legal/illegal summary, errors via
   `uvm_report_error` so `make mbinit_all` catches a real ordering violation.

Division of labor to preserve: requirement scoreboard answers "did it happen?",
predictor answers "was it legal / order-correct?". Keep them separate classes.

### Pass 8: Test Migration After Framework
- Rewrite MBINIT sequences as virtual sequences using `p_sequencer`.
- Replace raw hex constants with `mbinit_msg_pkg` helpers.
- Move per-test expectations into cfg setup in `build_phase`.
- Replace fixed `#...ns` tails with watchdog waits on done/error plus a small
  drain.
- Replace direct `env.scoreboard` and `env.agent.driver` mutations with
  cfg/service policy knobs.
- Remove the legacy adapter only after all existing tests start on `env.vseqr`.
- Retirement checklist (only once every test runs on `env.vseqr`, all green):
  delete `mbinit_legacy_adapter`, the legacy `mbinit_driver`/`mbinit_sequencer`/
  `mbinit_monitor` + `mbinit_transaction`, drop the factory override in
  `mbinit_env`, and remove the `mbinit_if` + tb_top bridge (move DUT ports onto
  the split interfaces — this is the Pass 8/9 step the constraint "don't touch
  DUT ports" was deferring). Also delete `/tmp/mbinit_scoreboard_legacy_backup.sv`
  reference once the new scoreboard is trusted.

## Carried-forward TODOs (don't lose these)
- Remove the temporary `mbinit_if` + tb_top bridge and move DUT ports onto the
  split interfaces (Pass 8/9).
- Promote the `tx_ready` auto-stub to its own per-lane sequencer/driver for real
  back-pressure tests (currently folded into the RX driver's fork).
- Optionally introduce `mbinit_req_agent` / `mbinit_rsp_agent` wrappers (SBINIT
  has them; MBINIT currently wires the split drivers directly in the env).
- When MBTRAIN is eventually refactored, reuse MBINIT's final shape as its
  template, and port `mbtrain_cg` coverage from `dev-verification` into the
  reorganized layout.

## Public API Changes
- New preferred test API: `cfg` + `env.vseqr` + MBINIT virtual sequences.
- Temporary compatibility API retained: `env.agent.sequencer`,
  `env.agent.driver`, `env.scoreboard.expect_*`, and `mbinit_vif`.
- New package APIs: `mbinit_msg_pkg` for wire-format helpers and
  `mbinit_event_pkg` for decoded observations.

## Test Plan (you run all of this yourself — Xcelium is available)
- Tight loop while editing: `make mbinit MBTEST=test_mbinit_sanity` (fast
  single-test). Read `uvm/run_logs/mbinit/<test>.log` on failure.
- Gate for finishing any pass: `make mbinit_all` — all 13 PASS. The `.results`
  file under `uvm/run_logs/mbinit/` summarizes pass/fail with error excerpts.
- After coverage edits: `make cov_mbinit` (report at
  `uvm/cov_work/mbinit/coverage.md`).
- After decoder/event work: `make mbinit MBTEST=test_mbinit_decode`.
- Run `make patternwriter_lr02` if pattern-writer interface/SVA wiring is touched.
- Run `make sbinit SBTEST=test_sbinit_sanity` only if you change shared
  Makefile/SVA/package behavior.
- Do NOT mark a pass done or write its commit message until `make mbinit_all` is
  green. If a fix is non-obvious, read the failing log fully before editing —
  guessing without the log wastes a sim cycle.

## Assumptions
- MBTRAIN is not refactored in this plan, but MBINIT's final shape should be
  reusable as its template.
- The framework refactor must not silently "fix" RTL behavior or change expected
  MBINIT test intent.
- Known MBINIT RTL gaps remain represented as cfg-gated expectations until
  separately addressed.
