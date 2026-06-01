`ifndef MBINIT_RESET_DRIVER_SV
`define MBINIT_RESET_DRIVER_SV

// ---------------------------------------------------------------------------
// mbinit_reset_driver  (Pass 6)
// ---------------------------------------------------------------------------
// Drives the sequence-controlled reset request (mb_reset_if.reset_req), which
// mbinit_tb_top OR's into the DUT reset (assign reset = por_reset | reset_req).
// It owns reset_req only; it does NOT react to reset (it is the source). Idle is
// reset_req=0 (DUT reset then follows the power-on reset alone). Mirrors
// sbinit_reset_driver.
// ---------------------------------------------------------------------------
class mbinit_reset_driver extends uvm_driver #(mbinit_reset_transaction);
  `uvm_component_utils(mbinit_reset_driver)

  virtual mb_reset_if vif;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual mb_reset_if)::get(this, "", "mbinit_reset_vif", vif))
      `uvm_fatal("NO_VIF", {"mbinit_reset_vif must be set for: ", get_full_name()})
  endfunction

  task run_phase(uvm_phase phase);
    vif.drv_cb.reset_req <= 1'b0;
    forever begin
      seq_item_port.get_next_item(req);
      drive_item(req);
      seq_item_port.item_done();
    end
  endtask

  task drive_item(mbinit_reset_transaction t);
    if (t.delay > 0)
      repeat (t.delay) @(vif.drv_cb);

    vif.drv_cb.reset_req <= 1'b1;
    repeat (t.cycles > 0 ? t.cycles : 1) @(vif.drv_cb);
    vif.drv_cb.reset_req <= 1'b0;
    @(vif.drv_cb);  // let the combined reset settle low before item_done
  endtask

endclass

`endif
