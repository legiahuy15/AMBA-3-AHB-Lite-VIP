//=============================================================================
// File        : ahb_sanity_test.sv
// Project     : AMBA 3 AHB-Lite VIP
// Author      : Huy Le
// Description : Smoke test - the first thing to run after any VIP change.
//               Runs ahb_sanity_seq against the slave memory model with zero
//               wait states, so every transfer is one address cycle plus one
//               data cycle. That keeps the bus on its simplest legal timing and
//               makes any SVA firing here a real protocol break rather than a
//               corner case.
//               Covers AHB_RST_001 (single clock edge operation) and
//               AHB_TRN_004 (NONSEQ for a single transfer and for the first
//               beat of a burst) in doc/ahb_lite_vplan.xlsx.
//               This file is `included inside ahb_test_pkg.sv.
//=============================================================================

`ifndef AHB_SANITY_TEST_INCLUDED_
`define AHB_SANITY_TEST_INCLUDED_

class ahb_sanity_test extends ahb_base_test;

    `uvm_component_utils(ahb_sanity_test)

    // Address slots to walk, overridable: +NUM_ITER=<n>
    int unsigned num_iter = 4;

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction : new

    //-------------------------------------------------------------------------
    // Build phase - base test builds env_cfg; pin the slave to the simplest
    // legal timing here. Zero wait states is what makes this a smoke test:
    // no extended data phases, so the driver pipeline is exercised on the
    // straight path only
    //-------------------------------------------------------------------------
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        env_cfg.slave_agent_cfg.auto_gen_resp   = 1;    // memory-model loopback
        env_cfg.slave_agent_cfg.ready_delay_min = 0;
        env_cfg.slave_agent_cfg.ready_delay_max = 0;    // zero wait states

        void'($value$plusargs("NUM_ITER=%d", num_iter));
    endfunction : build_phase

    //-------------------------------------------------------------------------
    // Run phase - start the sanity sequence on the master sequencer
    //-------------------------------------------------------------------------
    task run_phase(uvm_phase phase);
        ahb_sanity_seq seq;

        phase.raise_objection(this, "sanity test running");
        // Let the monitors publish the last burst before the phase ends
        phase.phase_done.set_drain_time(this, 200ns);

        seq = ahb_sanity_seq::type_id::create("seq");
        seq.num_iter = num_iter;
        seq.start(env.master_agent.sqr);

        phase.drop_objection(this, "sanity test done");
    endtask : run_phase

endclass : ahb_sanity_test

`endif // AHB_SANITY_TEST_INCLUDED_
