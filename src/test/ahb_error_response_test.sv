//=============================================================================
// File        : ahb_error_response_test.sv
// Project     : AMBA 3 AHB-Lite VIP
// Author      : Huy Le
// Description : ERROR response test. Slave in sequence mode
//               (ahb_slave_error_seq); master runs ahb_error_seq on all burst
//               types with cancel and continue policies.
//               vplan: AHB_RSP_003..008, AHB_BST_014, AHB_BST_015, AHB_ENV_003.
//=============================================================================

`ifndef AHB_ERROR_RESPONSE_TEST_INCLUDED_
`define AHB_ERROR_RESPONSE_TEST_INCLUDED_

class ahb_error_response_test extends ahb_base_test;

    `uvm_component_utils(ahb_error_response_test)

    // Bursts (+NUM_ITER=<n>)
    int unsigned num_iter = 16;

    // ERROR rate in percent (+ERROR_RATE=<n>)
    int unsigned error_rate_pct = 25;

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction : new

    //-------------------------------------------------------------------------
    // Build phase - slave sequence mode
    //-------------------------------------------------------------------------
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        env_cfg.slave_agent_cfg.auto_gen_resp = 0;

        void'($value$plusargs("NUM_ITER=%d", num_iter));
        void'($value$plusargs("ERROR_RATE=%d", error_rate_pct));
    endfunction : build_phase

    //-------------------------------------------------------------------------
    // Run phase - slave sequence runs forever (join_none); objection held by
    // the master sequence only
    //-------------------------------------------------------------------------
    task run_phase(uvm_phase phase);
        ahb_error_seq       mst_seq;
        ahb_slave_error_seq slv_seq;

        phase.raise_objection(this, "error response test running");
        phase.phase_done.set_drain_time(this, 200ns);

        mst_seq          = ahb_error_seq::type_id::create("mst_seq");
        mst_seq.num_iter = num_iter;

        // Same unmapped region as the master sequence
        slv_seq                = ahb_slave_error_seq::type_id::create("slv_seq");
        slv_seq.error_rate_pct = error_rate_pct;
        slv_seq.unmapped_base  = mst_seq.unmapped_base;

        fork
            slv_seq.start(env.slave_agent.sqr);
        join_none

        mst_seq.start(env.master_agent.sqr);

        `uvm_info(get_type_name(),
                  $sformatf("Slave answered %0d beats: %0d ERROR, %0d in the unmapped region",
                            slv_seq.num_rsp, slv_seq.num_error, slv_seq.num_unmapped), UVM_LOW)

        phase.drop_objection(this, "error response test done");
    endtask : run_phase

endclass : ahb_error_response_test

`endif // AHB_ERROR_RESPONSE_TEST_INCLUDED_
