//=============================================================================
// File        : ahb_reset_test.sv
// Project     : AMBA 3 AHB-Lite VIP
// Author      : Huy Le
// Description : Mid-simulation reset test (ahb_reset_seq). Reset asserted
//               during bursts, then traffic must recover with no unmatched
//               scoreboard entries.
//               vplan: AHB_RST_002..007.
//=============================================================================

`ifndef AHB_RESET_TEST_INCLUDED_
`define AHB_RESET_TEST_INCLUDED_

class ahb_reset_test extends ahb_base_test;

    `uvm_component_utils(ahb_reset_test)

    // Bursts (+NUM_ITER=<n>)
    int unsigned num_iter = 18;

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
    // Run phase - drain time > reset pulse (8 clocks)
    //-------------------------------------------------------------------------
    task run_phase(uvm_phase phase);
        ahb_reset_seq seq;

        phase.raise_objection(this, "reset test running");
        phase.phase_done.set_drain_time(this, 500ns);

        seq = ahb_reset_seq::type_id::create("seq");
        seq.num_iter = num_iter;
        seq.start(env.master_agent.sqr);

        phase.drop_objection(this, "reset test done");
    endtask : run_phase

endclass : ahb_reset_test

`endif // AHB_RESET_TEST_INCLUDED_
