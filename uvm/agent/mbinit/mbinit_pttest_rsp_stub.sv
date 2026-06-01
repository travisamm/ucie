`ifndef MBINIT_PTTEST_RSP_STUB_SV
`define MBINIT_PTTEST_RSP_STUB_SV

// ---------------------------------------------------------------------------
// mbinit_pttest_rsp_stub  (Pass 3)
// ---------------------------------------------------------------------------
// Responder-side Tx point-test stub on mb_pttest_rsp_if: on each rising edge of
// start, pulse done three cycles later. Replaces the legacy driver's
// TxPtTestResp auto-stub fork.
//
// Pass 6 makes it reset-aware: done is idled whenever reset is high and a reset
// mid-pulse aborts cleanly via the reset_watch fork.
// ---------------------------------------------------------------------------
class mbinit_pttest_rsp_stub extends uvm_component;
  `uvm_component_utils(mbinit_pttest_rsp_stub)

  virtual mb_pttest_rsp_if vif;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual mb_pttest_rsp_if)::get(this, "", "mbinit_pttest_rsp_vif", vif))
      `uvm_fatal("NO_VIF", {"mbinit_pttest_rsp_vif must be set for: ", get_full_name()})
  endfunction

  task run_phase(uvm_phase phase);
    forever begin
      vif.drv_cb.done <= 1'b0;
      wait (vif.reset == 1'b0);
      fork
        begin : active
          forever begin
            @(vif.drv_cb iff vif.drv_cb.start);
            repeat (3) @(vif.drv_cb);
            vif.drv_cb.done <= 1'b1;
            @(vif.drv_cb);
            vif.drv_cb.done <= 1'b0;
          end
        end
        begin : reset_watch
          @(posedge vif.reset);
        end
      join_any
      disable fork;
      vif.drv_cb.done <= 1'b0;  // re-idle after a reset abort
    end
  endtask

endclass

`endif
