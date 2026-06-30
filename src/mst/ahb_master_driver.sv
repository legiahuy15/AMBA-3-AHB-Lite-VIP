//=============================================================================
// File        : ahb_master_driver.sv
// Project     : AMBA 3 AHB-Lite VIP
// Author      : Huy Le
// Description : AHB-Lite master driver.
//               Receives transactions from the sequencer and drives thems
//               onto the AHB-Lite bus via the master clocking block.
//               Write flow :
//               Read flow  :
//               This file is `included inside ahb_pkg.sv.
//=============================================================================

class ahb_master_driver extends uvm_driver #(ahb_transaction);

    `uvm_component_utils(ahb_master_driver)

    // Virtual interface handle
    virtual ahb_if vif;

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction : new

    //-------------------------------------------------------------------------
    // Build phase - get virtual interface from config_db
    //-------------------------------------------------------------------------
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if(!uvm_config_db#(virtual ahb_if)::get(this, "", "vif", vif))
            `uvm_fatal(get_type_name(), "Virtual interface not found in config_db")
    endfunction: build_phase

    //------------------------------------------------------------------------
    // Run phase - main driver loop
    //------------------------------------------------------------------------

