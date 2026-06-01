`ifndef MBINIT_ENV_CFG_SV
`define MBINIT_ENV_CFG_SV

// ===========================================================================
// mbinit_env_cfg  (Pass 1: configuration object, additive)
// ---------------------------------------------------------------------------
// Mirrors today's settable scoreboard expectation flags (env/mbinit/
// mbinit_scoreboard.sv) plus the driver's service-stub knobs (agent/mbinit/
// mbinit_driver.sv), so tests can eventually configure behavior through one
// typed cfg object instead of mutating env.scoreboard.expect_* and
// env.agent.driver.* directly.
//
// Pass 1 is additive: this class is declared but NOT yet consumed by the env,
// scoreboard, or driver. Pass 5 wires the scoreboard to read these expectation
// flags; Pass 3 wires the service stubs to read the service knobs. Defaults
// here match the current scoreboard/driver defaults exactly, so adopting the
// cfg later is behavior-neutral.
// ===========================================================================

class mbinit_env_cfg extends uvm_object;
  `uvm_object_utils(mbinit_env_cfg)

  // ---- Scoreboard expectation flags (defaults match mbinit_scoreboard) -----
  bit expect_param_messages           = 1;
  bit expect_param_common_rate        = 1;
  bit expect_param_negotiation        = 1;
  bit expect_full_mbinit              = 1;
  bit expect_mbinit_through_cal       = 0;  // PARAM->CAL exit only
  bit expect_mbinit_through_repairclk = 0;  // PARAM->REPAIRCLK exit only
  bit expect_repairclk_rc03           = 0;  // unrepairable clock -> error
  bit expect_interop_failure          = 0;  // MP-04 interop-not-found path
  bit expect_fsm_done                 = 1;
  bit expect_fsm_error                = 0;
  bit expect_lane_ctrl_checks         = 1;  // XC-05
  bit expect_pattern_type_checks      = 1;  // RC-02/RV-03/LR-02/RM-01
  bit expect_rv01_checks              = 1;  // VALTRAIN + reader + phase subset
  bit expect_lr03_pattern_reader      = 1;  // responder PatternReader in REVERSALMB
  bit expect_lr04_apply_lane_reversal = 0;  // applyLaneReversal after fail+retry
  bit expect_rm02_per_lane_reader     = 0;  // heterogeneous PT bits in REPAIRMB
  bit expect_rm07_repairmb_unrepairable = 0;// all-lane fail -> error in REPAIRMB
  bit expect_rm05_post_repair_witness = 0;  // >=2 PT beats + txWidthChanged pulse

  // ---- Driver service-stub knobs (defaults match mbinit_driver) ------------
  // Cycles after each mbInitCalStart rising edge before mbInitCalDone pulses.
  int unsigned cal_done_repeat_cycles      = 3;
  // PatternReader response the TB returns (all lanes pass by default).
  bit [15:0]   pattern_reader_per_lane     = 16'hFFFF;
  bit          pattern_reader_aggregate    = 1'b1;
  // Default Tx point-test per-lane result bits (no fault).
  bit [15:0]   pt_test_results             = 16'h0000;
  // REPAIRMB point-test scenario injects (mutually exclusive in tests):
  //   rm02_mixed_pt_first             : first PT beat returns mixed pass/fail
  //   rm07_first_repairmb_pt_all_fault: first PT beat all-fault -> error
  //   rm05_post_repair_pt_sequence    : first PT upper-half fault (width degrade),
  //                                     then persistent fault -> error
  bit          rm02_mixed_pt_first             = 1'b0;
  bit          rm07_first_repairmb_pt_all_fault= 1'b0;
  bit          rm05_post_repair_pt_sequence    = 1'b0;

  // ---- Pass 6: per-lane payload-stability SVA opt-in (default OFF) ----------
  // mbinit_env pushes these onto each lane interface's stable_chk_en bit, which
  // gates mbinit_stream_sva's back-pressure payload-stability checker. Default 0
  // keeps the checker dormant for the 12 legacy tests; a Pass 8 back-pressure
  // test sets cfg.req_stable_chk_en / rsp_stable_chk_en to opt in per lane.
  bit          req_stable_chk_en               = 1'b0;
  bit          rsp_stable_chk_en               = 1'b0;

  function new(string name = "mbinit_env_cfg");
    super.new(name);
  endfunction

endclass

`endif
