//=============================================================================
// File        : ahb_slave_sequencer.sv
// Project     : AMBA 3 AHB-Lite VIP
// Author      : Huy Le
// Description : AHB-Lite slave sequencer. Sequence mode only
//               (auto_gen_resp = 0).
//=============================================================================

class ahb_slave_sequencer extends uvm_sequencer #(ahb_slave_response);

    `uvm_component_utils(ahb_slave_sequencer)

    //-------------------------------------------------------------------------
    // Current address phase (set by the driver; valid after start_item())
    //-------------------------------------------------------------------------
    bit [AHB_ADDR_WIDTH-1:0] req_addr;
    ahb_dir_e                req_write;

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction : new

endclass : ahb_slave_sequencer