//=============================================================================
// File        : ahb_agent_config.sv
// Project     : AMBA 3 AHB-Lite VIP
// Author      : Huy Le
// Description : Configuration object shared by the AHB-Lite master and slave
//               agents. Controls active/passive mode, coverage, master
//               back-to-back/backpressure, and slave response mode/timing.
//=============================================================================

class ahb_agent_config extends uvm_object;

    `uvm_object_utils(ahb_agent_config)

    //-------------------------------------------------------------------------
    // Agent mode
    //-------------------------------------------------------------------------
    //   UVM_ACTIVE  - driver + sequencer + monitor (drives traffic)
    //   UVM_PASSIVE - monitor only (passive observation)
    uvm_active_passive_enum is_active = UVM_ACTIVE;

    //-------------------------------------------------------------------------
    // Feature enables
    //-------------------------------------------------------------------------
    bit has_coverage = 1;       // Enable functional coverage collection

    // Master back-to-back: overlap next queued txn's beat-0 address phase
    // into the last data phase (no IDLE bubble). Driver always calls
    // item_done() when queued (pipelined) - wait on tr.done
    bit en_back_to_back = 1;

    // Master backpressure: max accepted-but-not-completed txns. Accept loop
    // stalls at this depth. 0 = unlimited
    int unsigned max_outstanding = 0;

    //-------------------------------------------------------------------------
    // Slave response mode (slave agent only)
    //-------------------------------------------------------------------------
    //   1 - slave driver auto-generates responses per the AHB-Lite spec
    //       (internal memory model, OKAY responses, ready_delay_min/max wait
    //       states). No sequencer traffic required.
    //   0 - slave driver pulls ahb_slave_response items from its sequencer;
    //       the sequence controls ready delay, HRESP, and HRDATA per beat.
    bit auto_gen_resp = 1;

    //-------------------------------------------------------------------------
    // Slave driver timing - back-pressure delays (slave agent only).
    // Applied only in auto-generate mode (auto_gen_resp = 1); ignored when
    // responses come from a sequence.
    //   max = 0 -> no delay (fastest response)
    //-------------------------------------------------------------------------
    int unsigned ready_delay_min = 0;   // Min cycles before HREADY
    int unsigned ready_delay_max = 0;   // Max cycles before HREADY

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(string name = "ahb_agent_config");
        super.new(name);
    endfunction : new

endclass : ahb_agent_config