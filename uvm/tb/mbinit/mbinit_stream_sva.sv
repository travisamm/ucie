`ifndef MBINIT_STREAM_SVA_SV
`define MBINIT_STREAM_SVA_SV

// ===========================================================================
// mbinit_stream_sva  (Pass 6)
// ---------------------------------------------------------------------------
// Reusable cycle-level assertion layer for the 128-bit ready/valid sideband
// streams of MBINIT, mirroring sbinit_stream_sva. This is the home for *generic*
// stream invariants that the event-driven scoreboard (which consumes protocol
// events, not raw cycles) should not own. It is kept separate from
// tb/logphy_sva.sv (read-only, binds DUT-internal signals) and is bound onto the
// MBINIT sideband lane interfaces (mb_req_if, mb_rsp_if).
//
// First generic rule: payload stability under back-pressure.
//   While VALID is asserted and the beat has not been accepted (READY low), the
//   payload must remain stable until it is taken. The SBINIT RTL had a known bug
//   (data assigned inside `when(tx.ready)`) that drove the payload to 0 while
//   valid was held; this rule catches the analogous behavior on MBINIT.
//
// Staged/gated: each instance is gated by an `en` input tied to the lane
// interface's stable_chk_en bit, which mbinit_env sets from the per-lane cfg
// flag (mbinit_env_cfg.req_stable_chk_en / rsp_stable_chk_en, default 0). So the
// checker is DORMANT for every current MBINIT test and only activates when a
// test opts in (Pass 8). This keeps the 12 legacy tests behavior-neutral and
// avoids asserting against any not-yet-characterized MBINIT back-pressure
// behavior until a test deliberately exercises it.
// ===========================================================================
checker mbinit_payload_stability_sva (
  input logic         clock,
  input logic         reset,
  input logic         valid,
  input logic         ready,
  input logic [127:0] data,
  input logic         en
);
  import uvm_pkg::*;

  // If a beat is offered but not accepted (valid && !ready), then on the next
  // cycle EITHER valid has dropped OR the payload is unchanged. Tolerating the
  // valid-drop avoids false fires on a legitimate offer end, while the $stable
  // term still catches a payload that changes mid-offer while ready is low.
  property p_payload_stable_under_backpressure;
    @(posedge clock) disable iff (reset || !en)
    (valid && !ready) |=> (!valid || $stable(data));
  endproperty

  a_payload_stable: assert property (p_payload_stable_under_backpressure)
    else uvm_report_error("MBINIT_SVA",
      $sformatf("payload not stable under back-pressure: data changed while valid held and ready low (data=0x%0h)",
                data));

endchecker

// ---------------------------------------------------------------------------
// Bind the generic checker onto each lane's TX stream. `en` follows the
// interface's stable_chk_en bit (set per test from mbinit_env_cfg).
// ---------------------------------------------------------------------------
bind mb_req_if mbinit_payload_stability_sva u_req_tx_stability (
  .clock (clock),
  .reset (reset),
  .valid (tx_valid),
  .ready (tx_ready),
  .data  (tx_bits_data),
  .en    (stable_chk_en)
);

bind mb_rsp_if mbinit_payload_stability_sva u_rsp_tx_stability (
  .clock (clock),
  .reset (reset),
  .valid (tx_valid),
  .ready (tx_ready),
  .data  (tx_bits_data),
  .en    (stable_chk_en)
);

`endif
