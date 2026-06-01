`ifndef MBINIT_PTTEST_REQ_STUB_SV
`define MBINIT_PTTEST_REQ_STUB_SV

// ---------------------------------------------------------------------------
// mbinit_pttest_req_stub  (Pass 3)
// ---------------------------------------------------------------------------
// Requester-side Tx point-test stub on mb_pttest_req_if. On each rising edge of
// start, wait three cycles, then drive done + results_valid + per-lane
// results_bits for one cycle. The per-lane result depends on the REPAIRMB
// scenario flags in svc_cfg (read live), reproducing the legacy driver exactly:
//
//   * rm07_first_repairmb_pt_all_fault : first REPAIRMB PT all-fault (0xFFFF)
//   * rm05_post_repair_pt_sequence     : first PT upper-half fault (0xFF00),
//                                        subsequent PTs full fault (0xFFFF)
//   * rm02_mixed_pt_first              : first REPAIRMB PT mixed (0x0FF0)
//   * otherwise                         : svc_cfg.pt_test_results
//
// REPAIRMB is currentState == 3'h5 (read from mb_ctrl_if). The per-REPAIRMB
// point-test index resets whenever the DUT leaves REPAIRMB.
//
// Pass 6 makes it reset-aware: done/results are idled and the start edge + the
// per-REPAIRMB index reset whenever reset is high; a reset mid-result aborts
// cleanly via the reset_watch fork.
// ---------------------------------------------------------------------------
class mbinit_pttest_req_stub extends uvm_component;
  `uvm_component_utils(mbinit_pttest_req_stub)

  virtual mb_pttest_req_if vif;
  virtual mb_ctrl_if       ctrl_vif;   // currentState (REPAIRMB == 3'h5)
  mbinit_service_cfg       svc_cfg;

  localparam logic [2:0] MB_STATE_REPAIRMB = 3'h5;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual mb_pttest_req_if)::get(this, "", "mbinit_pttest_req_vif", vif))
      `uvm_fatal("NO_VIF", {"mbinit_pttest_req_vif must be set for: ", get_full_name()})
    if (!uvm_config_db#(virtual mb_ctrl_if)::get(this, "", "mbinit_ctrl_vif", ctrl_vif))
      `uvm_fatal("NO_VIF", {"mbinit_ctrl_vif must be set for: ", get_full_name()})
    if (!uvm_config_db#(mbinit_service_cfg)::get(this, "", "mbinit_svc_cfg", svc_cfg))
      `uvm_fatal("NO_CFG", {"mbinit_svc_cfg must be set for: ", get_full_name()})
  endfunction

  task run_phase(uvm_phase phase);
    bit          prev_start;
    int unsigned idx;
    logic [15:0] ptb;
    forever begin
      vif.drv_cb.done          <= 1'b0;
      vif.drv_cb.results_valid <= 1'b0;
      vif.drv_cb.results_bits  <= 16'h0;
      prev_start = 1'b0;
      idx        = 0;
      wait (vif.reset == 1'b0);
      fork
        begin : active
          forever begin
            @(vif.drv_cb);
            if (ctrl_vif.currentState != MB_STATE_REPAIRMB)
              idx = 0;
            if (vif.drv_cb.start && !prev_start) begin
              repeat (3) @(vif.drv_cb);
              if (ctrl_vif.currentState == MB_STATE_REPAIRMB) begin
                if (svc_cfg.rm07_first_repairmb_pt_all_fault && idx == 0)
                  ptb = 16'hFFFF;
                else if (svc_cfg.rm05_post_repair_pt_sequence)
                  ptb = (idx == 0) ? 16'hFF00 : 16'hFFFF;
                else if (svc_cfg.rm02_mixed_pt_first && idx == 0)
                  ptb = 16'h0FF0;
                else
                  ptb = svc_cfg.pt_test_results;
              end
              else
                ptb = svc_cfg.pt_test_results;
              vif.drv_cb.done          <= 1'b1;
              vif.drv_cb.results_valid <= 1'b1;
              vif.drv_cb.results_bits  <= ptb;
              @(vif.drv_cb);
              vif.drv_cb.done          <= 1'b0;
              vif.drv_cb.results_valid <= 1'b0;
              if (ctrl_vif.currentState == MB_STATE_REPAIRMB)
                idx++;
            end
            prev_start = vif.drv_cb.start;
          end
        end
        begin : reset_watch
          @(posedge vif.reset);
        end
      join_any
      disable fork;
      vif.drv_cb.done          <= 1'b0;  // re-idle after a reset abort
      vif.drv_cb.results_valid <= 1'b0;
    end
  endtask

endclass

`endif
