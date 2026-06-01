`ifndef MBINIT_RESET_SVA_SV
`define MBINIT_RESET_SVA_SV

// ===========================================================================
// mbinit_reset_sva  (Pass 6)
// ---------------------------------------------------------------------------
// Reset-handling assertions, bound onto the MBINIT split interfaces. They
// confirm that while the DUT is held in reset:
//   * the DUT does not actively request/transmit (sideband tx_valid, FSM done /
//     substateTransitioning, calibration / pattern / point-test requests are not
//     asserted), and
//   * the testbench drives its inputs idle (sideband rx_valid, fsmCtrl_start,
//     and every service-stub response - cal_done, resp_complete, resp_valid,
//     point-test done/results - are not asserted) - i.e. the reset-aware drivers
//     and service stubs actually idle.
//
// Spec grounding: UCIe 3.0 Section 4.5.3.1 (RESET) requires "Data, Valid, Clock,
// and Track Transmitters are tri-stated" and "Sideband Transmitters are held
// low". The DUT-quiesce rules below check the DUT is not actively driving its
// request/transmit surfaces while reset is held. The TB-idle rules are
// testbench hygiene (verify our own reset-aware drivers/stubs), not a DUT spec
// requirement.
//
// Each rule is qualified by `(reset && $past(reset))` so it only fires once
// reset has been stable for >=2 cycles. That tolerates the one cycle of
// register/driver reaction latency at the reset edge (a synchronous output
// register clears the cycle AFTER reset is sampled; the reset-aware drivers idle
// their clocking outputs one cycle after they see the reset edge), while still
// catching a signal that stays active throughout a held reset.
//
// `!== 1'b1` (rather than `== 1'b0`) lets X during early power-on reset pass.
// Always on (no enable gate): these are fundamental and must hold for every
// test, power-on and sequence-injected mid-sim resets alike.
// ===========================================================================

// ---- sideband lane (requester / responder) ----
checker mbinit_lane_reset_sva (
  input logic clock,
  input logic reset,
  input logic tx_valid,   // DUT drives
  input logic rx_valid    // TB drives
);
  import uvm_pkg::*;

  a_dut_quiesce: assert property (@(posedge clock)
    (reset && $past(reset)) |-> (tx_valid !== 1'b1))
    else uvm_report_error("MBINIT_SVA",
      "DUT sideband tx_valid asserted while held in reset");

  a_tb_idle: assert property (@(posedge clock)
    (reset && $past(reset)) |-> (rx_valid !== 1'b1))
    else uvm_report_error("MBINIT_SVA",
      "TB sideband rx_valid driven while DUT held in reset (reset-aware driver did not idle)");

endchecker

// ---- FSM control bus ----
checker mbinit_ctrl_reset_sva (
  input logic clock,
  input logic reset,
  input logic fsmCtrl_done,                  // DUT drives
  input logic fsmCtrl_substateTransitioning, // DUT drives
  input logic fsmCtrl_start                  // TB drives
);
  import uvm_pkg::*;

  a_done_quiesce: assert property (@(posedge clock)
    (reset && $past(reset)) |-> (fsmCtrl_done !== 1'b1))
    else uvm_report_error("MBINIT_SVA", "fsmCtrl_done asserted while held in reset");

  a_substate_quiesce: assert property (@(posedge clock)
    (reset && $past(reset)) |-> (fsmCtrl_substateTransitioning !== 1'b1))
    else uvm_report_error("MBINIT_SVA",
      "fsmCtrl_substateTransitioning asserted while held in reset");

  a_start_idle: assert property (@(posedge clock)
    (reset && $past(reset)) |-> (fsmCtrl_start !== 1'b1))
    else uvm_report_error("MBINIT_SVA",
      "fsmCtrl_start driven while DUT held in reset (reset-aware driver did not idle)");

endchecker

// ---- generic service handshake (one DUT request, one TB response) ----
// Reused for the calibration, pattern-writer, pattern-reader, and point-test
// (responder) buses. `dut_req` is a DUT output that must quiesce in reset;
// `tb_resp` is the stub's response pulse that must idle in reset. (Steady-high
// accept signals such as req_ready are intentionally NOT checked - they are a
// legitimate idle level, not a transient.)
checker mbinit_svc_reset_sva (
  input logic clock,
  input logic reset,
  input logic dut_req,    // DUT drives (request / start)
  input logic tb_resp     // TB drives  (done / complete / valid pulse)
);
  import uvm_pkg::*;

  a_dut_quiesce: assert property (@(posedge clock)
    (reset && $past(reset)) |-> (dut_req !== 1'b1))
    else uvm_report_error("MBINIT_SVA", "DUT service request asserted while held in reset");

  a_tb_idle: assert property (@(posedge clock)
    (reset && $past(reset)) |-> (tb_resp !== 1'b1))
    else uvm_report_error("MBINIT_SVA",
      "TB service response driven while DUT held in reset (reset-aware stub did not idle)");

endchecker

// ---- point-test requester (one DUT request, two TB response pulses) ----
checker mbinit_pttest_req_reset_sva (
  input logic clock,
  input logic reset,
  input logic start,          // DUT drives
  input logic done,           // TB drives
  input logic results_valid   // TB drives
);
  import uvm_pkg::*;

  a_dut_quiesce: assert property (@(posedge clock)
    (reset && $past(reset)) |-> (start !== 1'b1))
    else uvm_report_error("MBINIT_SVA",
      "DUT point-test start asserted while held in reset");

  a_done_idle: assert property (@(posedge clock)
    (reset && $past(reset)) |-> (done !== 1'b1))
    else uvm_report_error("MBINIT_SVA",
      "TB point-test done driven while DUT held in reset (reset-aware stub did not idle)");

  a_results_idle: assert property (@(posedge clock)
    (reset && $past(reset)) |-> (results_valid !== 1'b1))
    else uvm_report_error("MBINIT_SVA",
      "TB point-test results_valid driven while DUT held in reset (reset-aware stub did not idle)");

endchecker

// ---------------------------------------------------------------------------
// Binds onto the lane, control, and service interfaces.
// ---------------------------------------------------------------------------
bind mb_req_if mbinit_lane_reset_sva u_req_reset (
  .clock    (clock),
  .reset    (reset),
  .tx_valid (tx_valid),
  .rx_valid (rx_valid)
);

bind mb_rsp_if mbinit_lane_reset_sva u_rsp_reset (
  .clock    (clock),
  .reset    (reset),
  .tx_valid (tx_valid),
  .rx_valid (rx_valid)
);

bind mb_ctrl_if mbinit_ctrl_reset_sva u_ctrl_reset (
  .clock                         (clock),
  .reset                         (reset),
  .fsmCtrl_done                  (fsmCtrl_done),
  .fsmCtrl_substateTransitioning (fsmCtrl_substateTransitioning),
  .fsmCtrl_start                 (fsmCtrl_start)
);

bind mb_cal_if mbinit_svc_reset_sva u_cal_reset (
  .clock   (clock),
  .reset   (reset),
  .dut_req (cal_start),
  .tb_resp (cal_done)
);

bind mb_pattern_writer_if mbinit_svc_reset_sva u_pw_reset (
  .clock   (clock),
  .reset   (reset),
  .dut_req (req_valid),
  .tb_resp (resp_complete)
);

bind mb_pattern_reader_if mbinit_svc_reset_sva u_pr_reset (
  .clock   (clock),
  .reset   (reset),
  .dut_req (req_valid),
  .tb_resp (resp_valid)
);

bind mb_pttest_rsp_if mbinit_svc_reset_sva u_pttest_rsp_reset (
  .clock   (clock),
  .reset   (reset),
  .dut_req (start),
  .tb_resp (done)
);

bind mb_pttest_req_if mbinit_pttest_req_reset_sva u_pttest_req_reset (
  .clock         (clock),
  .reset         (reset),
  .start         (start),
  .done          (done),
  .results_valid (results_valid)
);

`endif
