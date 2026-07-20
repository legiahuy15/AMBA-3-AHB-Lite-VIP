//=============================================================================
// File        : ahb_slave_sequencer.sv
// Project     : AMBA 3 AHB-Lite VIP
// Author      : Huy Le
// Description : AHB-Lite slave sequencer.
//               Sequences generate ahb_slave_response items that are passed
//               to the slave driver to answer bus transfers. Only used when
//               the slave agent runs in sequence mode (auto_gen_resp = 0).
//               This file is `included inside ahb_pkg.sv.
//=============================================================================

class ahb_slave_sequencer extends uvm_sequencer #(ahb_slave_response);

    `uvm_component_utils(ahb_slave_sequencer)

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction : new

endclass : ahb_slave_sequencer