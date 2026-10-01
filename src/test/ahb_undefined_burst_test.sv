//=============================================================================
// File        : ahb_undefined_burst_test.sv
// Project     : AMBA 3 AHB-Lite VIP
// Author      : Huy Le
// Description : Undefined-length INCR burst test (ahb_undefined_burst_seq):
//               1-256 beats, mid-burst BUSY, termination after BUSY.
//               vplan: AHB_BST_002, AHB_TRN_009, AHB_WAI_006.
//=============================================================================

`ifndef AHB_UNDEFINED_BURST_TEST_INCLUDED_
`define AHB_UNDEFINED_BURST_TEST_INCLUDED_

class ahb_undefined_burst_test extends ahb_base_test;

    `uvm_component_utils(ahb_undefined_burst_test)

    // Bursts (+NUM_ITER=<n>)
    int unsigned num_iter = 8;

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction : new

    //-------------------------------------------------------------------------
    // Build phase - wait states for BUSY under HREADY=0 (BUSY_WAIT_TRANSITION)
    //-------------------------------------------------------------------------
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        env_cfg.slave_agent_cfg.auto_gen_resp   = 1;
        env_cfg.slave_agent_cfg.ready_delay_min = 0;
        env_cfg.slave_agent_cfg.ready_delay_max = 2;

        void'($value$plusargs("NUM_ITER=%d", num_iter));
    endfunction : build_phase

    //-------------------------------------------------------------------------
    // Run phase - longer drain time for 256-beat bursts
    //-------------------------------------------------------------------------
    task run_phase(uvm_phase phase);
        ahb_undefined_burst_seq seq;

        phase.raise_objection(this, "undefined burst test running");
        phase.phase_done.set_drain_time(this, 500ns);

        seq = ahb_undefined_burst_seq::type_id::create("seq");
        seq.num_iter = num_iter;
        seq.start(env.master_agent.sqr);

        phase.drop_objection(this, "undefined burst test done");
    endtask : run_phase

endclass : ahb_undefined_burst_test

`endif // AHB_UNDEFINED_BURST_TEST_INCLUDED_
