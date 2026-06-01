# MBINIT Framework Refactor Plan

> Saved to memory at the user's request. We execute this pass-by-pass. The
> SBINIT environment (under `uvm/{if,agent,env,coverage,seq,tests,tb}/sbinit/`)
> is the gold-standard template this refactor mirrors. Do **not** edit Scala
> RTL, `elab/generatedVerilog/`, `uvm/tb/logphy_sva.sv`, or any `mbtrain_*`
> files. Only static checking is available locally; the user runs sim/lint
> (Cadence Xcelium) on a remote server.

## Progress tracker
- [x] Pass 0: Baseline (documented below; no sim available locally)
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
      authoritative. Pending user `make mbinit_all` verification.
- [x] Pass 5: Event-driven scoreboard + coverage (clean cutover). Scoreboard +
      coverage now consume the single mbinit_event stream via timestamp-bucket
      processing (Phase A context, Phase B checks); src-qualified witnesses;
      saw_bad_{req,rsp}_tx preserved; neg_valid tracking; cfg pulled via
      config_db("scoreboard","cfg"). Event extended with 4 control-snapshot bits
      + lane-ctrl scalars registered. Legacy mbinit_monitor instantiated but
      UNCONNECTED (retired Pass 8). Legacy scoreboard backed up at
      /tmp/mbinit_scoreboard_legacy_backup.sv. Pending user make mbinit_all +
      cov_mbinit verification.
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
      POR cycle, where all signals are 0/X). Pending user make mbinit_all +
      cov_mbinit verification.
- [ ] Pass 7: MBINIT reference predictor
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

### Current MBINIT tests (must stay green)
test_mbinit_sanity, test_mbinit_param_mismatch, test_mbinit_param_only,
test_mbinit_cal, test_mbinit_repairclk, test_mbinit_repairclk_unrep,
test_mbinit_repairval_unrep, test_mbinit_lr04_reversal_apply,
test_mbinit_lr07_reversal_trainerror, test_mbinit_rm02_per_lane_reader,
test_mbinit_rm07_unrepairable, test_mbinit_rm05_post_repair_persist.

## Passes

### Pass 0: Baseline
- Run and archive current `make mbinit_all` behavior (user-run; no local sim).
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

### Pass 6: Reset And Assertion Layer
- Add sequence-driven reset injection using `mb_reset_if`, OR'd with POR like
  SBINIT.
- Make all drivers reset-aware: idle outputs, abort in-flight items cleanly, and
  release UVM item handshakes.
- Add MBINIT sideband ready/valid payload-stability SVA, opt-in per lane through
  cfg.
- Add reset-quiesce SVA for TB-driven inputs and DUT-observed outputs.
- Leave strict requester/responder state-sync SVA unbound unless rewritten with
  MBINIT-valid timing.

### Pass 7: MBINIT Reference Predictor
- Add `mbinit_predictor` consuming the event stream.
- Model legal phase order: PARAM, CAL, REPAIRCLK, REPAIRVAL, REVERSALMB,
  REPAIRMB, TOMBTRAIN/error.
- Validate DUT outputs against current modeled phase and partner/service inputs.
- Gate known RTL/testbench gaps through cfg so existing regressions stay
  meaningful.
- Keep the requirement scoreboard as "did it happen?" and the predictor as
  "was it legal/order-correct?"

### Pass 8: Test Migration After Framework
- Rewrite MBINIT sequences as virtual sequences using `p_sequencer`.
- Replace raw hex constants with `mbinit_msg_pkg` helpers.
- Move per-test expectations into cfg setup in `build_phase`.
- Replace fixed `#...ns` tails with watchdog waits on done/error plus a small
  drain.
- Replace direct `env.scoreboard` and `env.agent.driver` mutations with
  cfg/service policy knobs.
- Remove the legacy adapter only after all existing tests start on `env.vseqr`.

## Public API Changes
- New preferred test API: `cfg` + `env.vseqr` + MBINIT virtual sequences.
- Temporary compatibility API retained: `env.agent.sequencer`,
  `env.agent.driver`, `env.scoreboard.expect_*`, and `mbinit_vif`.
- New package APIs: `mbinit_msg_pkg` for wire-format helpers and
  `mbinit_event_pkg` for decoded observations.

## Test Plan
- After each pass: `make mbinit MBTEST=test_mbinit_param_only` and
  `make mbinit MBTEST=test_mbinit_sanity`.
- After passes 3, 5, 6, and 7: `make mbinit_all`.
- After decoder/event work: run the new MBINIT decode smoke test
  (`make mbinit MBTEST=test_mbinit_decode`).
- After coverage migration: `make cov_mbinit`.
- Run `make patternwriter_lr02` if pattern-writer interface/SVA wiring is
  touched.
- Run `make sbinit SBTEST=test_sbinit_sanity` only if shared
  Makefile/SVA/package behavior changes.

## Assumptions
- MBTRAIN is not refactored in this plan, but MBINIT's final shape should be
  reusable as its template.
- The framework refactor must not silently "fix" RTL behavior or change expected
  MBINIT test intent.
- Known MBINIT RTL gaps remain represented as cfg-gated expectations until
  separately addressed.
