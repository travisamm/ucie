`ifndef MBINIT_PW_STUB_SV
`define MBINIT_PW_STUB_SV

// ---------------------------------------------------------------------------
// mbinit_pw_stub  (Pass 3)
// ---------------------------------------------------------------------------
// PatternWriter service responder on mb_pattern_writer_if: hold req_ready high,
// and on each req_valid pulse resp_complete five cycles later. Replaces the
// legacy driver's PatternWriter auto-stub fork.
//
// Pass 6 makes it reset-aware: resp_complete is idled (req_ready stays at its
// steady accept-high) and any in-flight completion is aborted on reset.
// ---------------------------------------------------------------------------
class mbinit_pw_stub extends uvm_component;
  `uvm_component_utils(mbinit_pw_stub)

  virtual mb_pattern_writer_if vif;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual mb_pattern_writer_if)::get(this, "", "mbinit_pw_vif", vif))
      `uvm_fatal("NO_VIF", {"mbinit_pw_vif must be set for: ", get_full_name()})
  endfunction

  task run_phase(uvm_phase phase);
    forever begin
      vif.drv_cb.req_ready     <= 1'b1;
      vif.drv_cb.resp_complete <= 1'b0;
      wait (vif.reset == 1'b0);
      fork
        begin : active
          forever begin
            @(vif.drv_cb iff vif.drv_cb.req_valid);
            repeat (5) @(vif.drv_cb);
            vif.drv_cb.resp_complete <= 1'b1;
            @(vif.drv_cb);
            vif.drv_cb.resp_complete <= 1'b0;
          end
        end
        begin : reset_watch
          @(posedge vif.reset);
        end
      join_any
      disable fork;
      vif.drv_cb.resp_complete <= 1'b0;  // re-idle after a reset abort
    end
  endtask

endclass

`endif
