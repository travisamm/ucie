`ifndef MBINIT_PR_STUB_SV
`define MBINIT_PR_STUB_SV

// ---------------------------------------------------------------------------
// mbinit_pr_stub  (Pass 3)
// ---------------------------------------------------------------------------
// PatternReader service responder on mb_pattern_reader_if: hold req_ready high,
// and on each rising edge of req_done drive a one-cycle resp with the per-lane
// status + aggregate from svc_cfg. Mirrors the legacy driver's PatternReader
// auto-stub (which keys off req_bits_done, not req_valid, because the RTL drops
// req_valid in the done substate).
//
// Pass 6 makes it reset-aware: resp_valid is idled and the req_done edge state
// reset whenever reset is high; a reset mid-response aborts cleanly.
// ---------------------------------------------------------------------------
class mbinit_pr_stub extends uvm_component;
  `uvm_component_utils(mbinit_pr_stub)

  virtual mb_pattern_reader_if vif;
  mbinit_service_cfg           svc_cfg;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual mb_pattern_reader_if)::get(this, "", "mbinit_pr_vif", vif))
      `uvm_fatal("NO_VIF", {"mbinit_pr_vif must be set for: ", get_full_name()})
    if (!uvm_config_db#(mbinit_service_cfg)::get(this, "", "mbinit_svc_cfg", svc_cfg))
      `uvm_fatal("NO_CFG", {"mbinit_svc_cfg must be set for: ", get_full_name()})
  endfunction

  task run_phase(uvm_phase phase);
    bit prev_done;
    forever begin
      vif.drv_cb.req_ready  <= 1'b1;
      vif.drv_cb.resp_valid <= 1'b0;
      prev_done = 1'b0;
      wait (vif.reset == 1'b0);
      fork
        begin : active
          forever begin
            @(vif.drv_cb);
            if (vif.drv_cb.req_done && !prev_done) begin
              vif.drv_cb.resp_valid     <= 1'b1;
              vif.drv_cb.resp_perLane   <= svc_cfg.pattern_reader_per_lane;
              vif.drv_cb.resp_aggregate <= svc_cfg.pattern_reader_aggregate;
              @(vif.drv_cb);
              vif.drv_cb.resp_valid <= 1'b0;
            end
            prev_done = vif.drv_cb.req_done;
          end
        end
        begin : reset_watch
          @(posedge vif.reset);
        end
      join_any
      disable fork;
      vif.drv_cb.resp_valid <= 1'b0;  // re-idle after a reset abort
    end
  endtask

endclass

`endif
