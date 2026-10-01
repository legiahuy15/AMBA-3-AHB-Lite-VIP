//=============================================================================
// File        : ahb_wrap_burst_test.sv
// Project     : AMBA 3 AHB-Lite VIP
// Author      : Huy Le
// Description : WRAP4/8/16 burst test (ahb_wrap_burst_seq), all legal sizes,
//               aligned and unaligned to the wrap boundary.
//               vplan: AHB_BST_006..008, AHB_BST_010, AHB_DAT_006.
//=============================================================================

`ifndef AHB_WRAP_BURST_TEST_INCLUDED_
`define AHB_WRAP_BURST_TEST_INCLUDED_

class ahb_wrap_burst_test extends ahb_base_test;

    `uvm_component_utils(ahb_wrap_burst_test)

    // Bursts (+NUM_ITER=<n>)
    int unsigned num_iter = 16;

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction : new

    //-------------------------------------------------------------------------
    // Build phase - auto-response slave, 0-2 wait states
    //-------------------------------------------------------------------------
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        env_cfg.slave_agent_cfg.auto_gen_resp   = 1;
        env_cfg.slave_agent_cfg.ready_delay_min = 0;
        env_cfg.slave_agent_cfg.ready_delay_max = 2;

        void'($value$plusargs("NUM_ITER=%d", num_iter));
    endfunction : build_phase

    //-------------------------------------------------------------------------
    // Run phase
    //-------------------------------------------------------------------------
    task run_phase(uvm_phase phase);
        ahb_wrap_burst_seq seq;

        phase.raise_objection(this, "wrap burst test running");
        phase.phase_done.set_drain_time(this, 200ns);

        seq = ahb_wrap_burst_seq::type_id::create("seq");
        seq.num_iter = num_iter;
        seq.start(env.master_agent.sqr);

        phase.drop_objection(this, "wrap burst test done");
    endtask : run_phase

endclass : ahb_wrap_burst_test

`endif // AHB_WRAP_BURST_TEST_INCLUDED_