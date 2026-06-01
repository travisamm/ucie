`ifndef MBINIT_REQ_RX_DRIVER_SV
`define MBINIT_REQ_RX_DRIVER_SV

// ---------------------------------------------------------------------------
// mbinit_req_rx_driver  (Pass 3)
// ---------------------------------------------------------------------------
// Drives the requester RX lane (partner -> DUT: rx_valid/rx_bits_data) on
// mb_req_if, plus the tx_ready auto-stub (ready follows valid) as an
// independent sibling process on the same lane. Matches the legacy driver's
// behavior: rx_valid is held for hold_cycles then cleared; tx_ready tracks the
// DUT's tx_valid every cycle.
//
// Pass 6 makes it reset-aware: idle outputs, run until reset asserts, then abort
// the in-flight drive, re-idle, and release the UVM item handshake so a sequence
// is never stranded across a reset boundary. The tx_ready auto-stub runs as a
// sibling process INSIDE the same fork so it is torn down on reset too.
// TODO(pass>=8): promote tx_ready to its own sequencer/driver for back-pressure.
// ---------------------------------------------------------------------------
class mbinit_req_rx_driver extends uvm_driver #(mbinit_rx_transaction);
  `uvm_component_utils(mbinit_req_rx_driver)

  virtual mb_req_if vif;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual mb_req_if)::get(this, "", "mbinit_req_vif", vif))
      `uvm_fatal("NO_VIF", {"mbinit_req_vif must be set for: ", get_full_name()})
  endfunction

  task run_phase(uvm_phase phase);
    bit item_in_flight;
    forever begin
      drive_idle();
      wait (vif.reset == 1'b0);
      item_in_flight = 0;
      fork
        begin : txready  // auto-stub: ready follows valid every cycle
          forever begin
            @(vif.drv_cb);
            vif.drv_cb.tx_ready <= vif.drv_cb.tx_valid;
          end
        end
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

  task drive_idle();
    vif.drv_cb.tx_ready     <= 0;
    vif.drv_cb.rx_valid     <= 0;
    vif.drv_cb.rx_bits_data <= 0;
  endtask

  task drive_item(mbinit_rx_transaction t);
    if (t.delay > 0) begin
      vif.drv_cb.rx_valid <= 0;
      repeat (t.delay) @(vif.drv_cb);
    end
    vif.drv_cb.rx_valid     <= t.rx_valid;
    vif.drv_cb.rx_bits_data <= t.rx_data;
    repeat (t.hold_cycles > 0 ? t.hold_cycles : 1) @(vif.drv_cb);
    vif.drv_cb.rx_valid <= 0;
  endtask

endclass

`endif
