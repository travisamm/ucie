`ifndef MBINIT_CTRL_DRIVER_SV
`define MBINIT_CTRL_DRIVER_SV

// ---------------------------------------------------------------------------
// mbinit_ctrl_driver  (Pass 3)
// ---------------------------------------------------------------------------
// Drives the FSM-control bus on mb_ctrl_if: fsmCtrl_start and the local PHY
// settings. localPhySettings_valid is held high; voltageSwing/maxDataRate/etc.
// are updated per item. fsmCtrl_start is LATCHED: once an item asserts it, it
// stays high (the RTL gates the FSM on start held until done) - matching the
// legacy driver's "only assert, never clear".
//
// Pass 6 makes it reset-aware: on reset the start latch is CLEARED and the bus
// is re-idled (fsmCtrl_start back to 0), so after the DUT FSM resets to PARAM a
// fresh item must re-kick it. The in-flight item is aborted and its UVM
// handshake released. Behavior-neutral for the POR-only legacy tests (start is
// 0 throughout the power-on reset window regardless).
// ---------------------------------------------------------------------------
class mbinit_ctrl_driver extends uvm_driver #(mbinit_ctrl_transaction);
  `uvm_component_utils(mbinit_ctrl_driver)

  virtual mb_ctrl_if vif;
  bit start_latched;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual mb_ctrl_if)::get(this, "", "mbinit_ctrl_vif", vif))
      `uvm_fatal("NO_VIF", {"mbinit_ctrl_vif must be set for: ", get_full_name()})
  endfunction

  task run_phase(uvm_phase phase);
    bit item_in_flight;
    forever begin
      start_latched  = 1'b0;  // a fresh reset clears the start kick
      drive_idle();
      wait (vif.reset == 1'b0);
      item_in_flight = 0;
      fork
        begin : active
          forever begin
            seq_item_port.get_next_item(req);
            item_in_flight = 1;
            drive_item(req);
            seq_item_port.item_done();
            item_in_flight = 0;
          end
        end
        begin : reset_watch
          @(posedge vif.reset);
        end
      join_any
      disable fork;
      drive_idle();
      if (item_in_flight) begin
        seq_item_port.item_done();  // release the aborted item
        item_in_flight = 0;
      end
    end
  endtask

  // Idle: valid high + PARAM defaults; start reflects the latch (0 at reset).
  task drive_idle();
    vif.drv_cb.fsmCtrl_start            <= start_latched;
    vif.drv_cb.localPhySettings_valid        <= 1'b1;
    vif.drv_cb.localPhySettings_voltageSwing <= 5'h1F;
    vif.drv_cb.localPhySettings_maxDataRate  <= 4'hF;
    vif.drv_cb.localPhySettings_clockMode    <= 1'b1;
    vif.drv_cb.localPhySettings_clockPhase   <= 1'b0;
    vif.drv_cb.localPhySettings_ucieSx8      <= 1'b0;
    vif.drv_cb.localPhySettings_sbFeatExt    <= 1'b0;
    vif.drv_cb.localPhySettings_txAdjRuntime <= 1'b0;
    vif.drv_cb.localPhySettings_moduleId     <= 2'h0;
  endtask

  task drive_item(mbinit_ctrl_transaction t);
    if (t.delay > 0)
      repeat (t.delay) @(vif.drv_cb);
    if (t.start_fsm) start_latched = 1'b1;  // latch; never cleared
    vif.drv_cb.fsmCtrl_start                  <= start_latched;
    vif.drv_cb.localPhySettings_valid        <= 1'b1;
    vif.drv_cb.localPhySettings_voltageSwing <= t.local_voltageSwing;
    vif.drv_cb.localPhySettings_maxDataRate  <= t.local_maxDataRate;
    vif.drv_cb.localPhySettings_clockMode    <= t.local_clockMode;
    vif.drv_cb.localPhySettings_clockPhase   <= t.local_clockPhase;
    vif.drv_cb.localPhySettings_ucieSx8      <= t.local_ucieSx8;
    vif.drv_cb.localPhySettings_sbFeatExt    <= t.local_sbFeatExt;
    vif.drv_cb.localPhySettings_txAdjRuntime <= t.local_txAdjRuntime;
    vif.drv_cb.localPhySettings_moduleId     <= t.local_moduleId;
    repeat (t.hold_cycles > 0 ? t.hold_cycles : 1) @(vif.drv_cb);
    // Do NOT clear start or PHY settings; they persist across items.
  endtask

endclass

`endif
