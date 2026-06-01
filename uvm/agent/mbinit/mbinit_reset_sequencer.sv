`ifndef MBINIT_RESET_SEQUENCER_SV
`define MBINIT_RESET_SEQUENCER_SV

// ---------------------------------------------------------------------------
// mbinit_reset_sequencer  (Pass 6)
// ---------------------------------------------------------------------------
// Sequencer for reset-injection items. Lives at env level (with the reset
// driver and the existing reset monitor). Pass 8 virtual sequences drive it via
// env.vseqr.reset_seqr to inject mid-sim resets. Mirrors sbinit_reset_sequencer.
// ---------------------------------------------------------------------------
class mbinit_reset_sequencer extends uvm_sequencer #(mbinit_reset_transaction);
  `uvm_component_utils(mbinit_reset_sequencer)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

endclass

`endif
