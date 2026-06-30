//==============================================================================
// File        : ahb_agent_config.sv
// Project     : AMBA 3 AHB-Lite VIP
// Author      : Huy Le
// Description : Configuration object for AHB-Lite agents.
//               Controls active/passive mode, coverage enable, and slave
//               driver timing delays. Shared by both master and slave agents.
//               This file is `included inside ahb_pkg.sv.
//==============================================================================

class ahb_agent_config extends uvm_object;

    `uvm_object_utils(ahb_agent_config)

    // =========================================================================
    // Agent mode
    // =========================================================================
    //   UVM_ACTIVE  — agent has driver + sequencer + monitor (drives traffic)
    //   UVM_PASSIVE — agent has monitor only (passive observation)
    uvm_active_passive_enum is_active = UVM_ACTIVE;

    // =========================================================================
    // Feature enables
    // =========================================================================
    bit has_coverage = 1;       // Enable functional coverage collection

    // =========================================================================
    // Slave driver timing — back-pressure delays
    //   Only used by slave agent. Ignored by master agent.
    //   When max = 0, no delay is inserted (fastest response).
    // =========================================================================
    int unsigned ready_delay_min = 0;   // Min cycles before HREADY
    int unsigned ready_delay_max = 0;   // Max cycles before HREADY

    // =========================================================================
    // Constructor
    // =========================================================================
    function new(string name = "ahb_agent_config");
        super.new(name);
    endfunction : new

endclass : ahb_agent_config