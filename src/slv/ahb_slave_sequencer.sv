//=============================================================================
// File        : ahb_slave_sequencer.sv
// Project     : AMBA 3 AHB-Lite VIP
// Author      : Huy Le
// Description : AHB-Lite slave sequencer. Feeds ahb_slave_response items to the
//               slave driver. Used only in sequence mode (auto_gen_resp = 0).
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