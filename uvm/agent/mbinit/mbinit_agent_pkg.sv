`ifndef MBINIT_AGENT_PKG_SV
`define MBINIT_AGENT_PKG_SV

package mbinit_agent_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  // Base transaction (logphy_transaction) must be defined first
  import logphy_agent_pkg::*;
  // Pass 4: event/decoder types for the new monitors.
  import mbinit_event_pkg::*;

  // MBINIT-specific transaction (extends logphy_transaction)
  `include "mbinit_transaction.sv"
  // Pass 3: split-channel drive items + shared service policy
  `include "mbinit_rx_transaction.sv"
  `include "mbinit_ctrl_transaction.sv"
  `include "mbinit_service_cfg.sv"
  // Pass 6: reset-injection item
  `include "mbinit_reset_transaction.sv"

  // Inline sequencer typed to the MBINIT transaction
  class mbinit_sequencer extends uvm_sequencer #(mbinit_transaction);
    `uvm_component_utils(mbinit_sequencer)
    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction
  endclass

  // Pass 3: new split-channel sequencers
  `include "mbinit_rx_sequencer.sv"
  `include "mbinit_ctrl_sequencer.sv"
  // Pass 6: reset-injection sequencer
  `include "mbinit_reset_sequencer.sv"

  // Legacy driver + new split drivers + legacy adapter (extends mbinit_driver)
  `include "mbinit_driver.sv"
  `include "mbinit_req_rx_driver.sv"
  `include "mbinit_rsp_rx_driver.sv"
  `include "mbinit_ctrl_driver.sv"
  `include "mbinit_legacy_adapter.sv"
  // Pass 6: reset-injection driver
  `include "mbinit_reset_driver.sv"

  // Pass 3: autonomous service stubs (replace the legacy driver's stub forks)
  `include "mbinit_cal_stub.sv"
  `include "mbinit_pw_stub.sv"
  `include "mbinit_pr_stub.sv"
  `include "mbinit_pttest_req_stub.sv"
  `include "mbinit_pttest_rsp_stub.sv"

  `include "mbinit_monitor.sv"

  // Pass 4: event-producing monitors (shadow stream, fed to mbinit_event_audit).
  // Base must come before the lane monitors that extend it.
  `include "mbinit_lane_monitor_base.sv"
  `include "mbinit_req_monitor.sv"
  `include "mbinit_rsp_monitor.sv"
  `include "mbinit_ctrl_monitor.sv"
  `include "mbinit_reset_monitor.sv"
  `include "mbinit_cal_monitor.sv"
  `include "mbinit_pw_monitor.sv"
  `include "mbinit_pr_monitor.sv"
  `include "mbinit_pttest_req_monitor.sv"
  `include "mbinit_pttest_rsp_monitor.sv"
  `include "mbinit_lane_ctrl_monitor.sv"

  // Agent — same structure as logphy_agent, typed to MBINIT classes
  class mbinit_agent extends uvm_agent;
    `uvm_component_utils(mbinit_agent)

    mbinit_driver    driver;
    mbinit_sequencer sequencer;
    mbinit_monitor   monitor;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      monitor = mbinit_monitor::type_id::create("monitor", this);
      if (get_is_active() == UVM_ACTIVE) begin
        driver    = mbinit_driver::type_id::create("driver", this);
        sequencer = mbinit_sequencer::type_id::create("sequencer", this);
      end
    endfunction

    function void connect_phase(uvm_phase phase);
      if (get_is_active() == UVM_ACTIVE)
        driver.seq_item_port.connect(sequencer.seq_item_export);
    endfunction
  endclass

endpackage
`endif
