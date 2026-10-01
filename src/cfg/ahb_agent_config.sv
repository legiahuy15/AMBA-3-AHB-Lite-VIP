//=============================================================================
// File        : ahb_agent_config.sv
// Project     : AMBA 3 AHB-Lite VIP
// Author      : Huy Le
// Description : Agent configuration (master and slave): active/passive,
//               coverage, master pipelining, slave response mode and timing.
//=============================================================================

class ahb_agent_config extends uvm_object;

    `uvm_object_utils(ahb_agent_config)

    //-------------------------------------------------------------------------
    // Agent mode
    //-------------------------------------------------------------------------
    //   UVM_ACTIVE  - driver + sequencer + monitor
    //   UVM_PASSIVE - monitor only
    uvm_active_passive_enum is_active = UVM_ACTIVE;

    //-------------------------------------------------------------------------
    // Feature enables
    //-------------------------------------------------------------------------
    bit has_coverage = 1;

    // Master: next txn's beat-0 address phase overlaps the last data phase
    bit en_back_to_back = 1;

    // Master: overlap slot starts as IDLE and changes to NONSEQ during the
    // wait state (IHI0033A 3.6.1). Requires en_back_to_back
    bit en_idle_to_nonseq_in_wait = 0;

    // Master: max accepted, not completed txns (0 = unlimited)
    int unsigned max_outstanding = 0;

    //-------------------------------------------------------------------------
    // Slave response mode (slave agent only)
    //-------------------------------------------------------------------------
    //   1 - internal memory model, OKAY, ready_delay_min/max wait states
    //   0 - ahb_slave_response items set wait states, HRESP, HRDATA per beat
    bit auto_gen_resp = 1;

    //-------------------------------------------------------------------------
    // Slave wait states (auto_gen_resp = 1 only)
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