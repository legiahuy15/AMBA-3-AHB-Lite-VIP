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
    //   UVM_ACTIVE  — driver + sequencer + monitor (drives traffic)
    //   UVM_PASSIVE — monitor only (passive observation)
    uvm_active_passive_enum is_active = UVM_ACTIVE;

    // =========================================================================
    // Feature enables
    // =========================================================================
    bit has_coverage = 1;       // Enable functional coverage collection

    // Master back-to-back: overlap next queued txn's beat-0 address phase
    // into the last data phase (no IDLE bubble). Driver always calls
    // item_done() when queued (pipelined) - wait on tr.done_event.ev
    bit en_back_to_back = 1;

    // Master backpressure: max accepted-but-not-completed txns. Accept loop
    // stalls at this depth. 0 = unlimited
    int unsigned max_outstanding = 0;

    // =========================================================================
    // Slave driver timing — back-pressure delays (slave agent only).
    //   max = 0 -> no delay (fastest response)
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