//=============================================================================
// File        : ahb_transfer_size_test.sv
// Project     : AMBA 3 AHB-Lite VIP
// Author      : Huy Le
// Description : Transfer-size test (ahb_size_seq). Sweeps legal HSIZE values
//               and alignments in SINGLE and multi-beat bursts; checks that
//               sizes wider than the bus fail randomization.
//               vplan: AHB_SIZ_001..006.
//=============================================================================

`ifndef AHB_TRANSFER_SIZE_TEST_INCLUDED_
`define AHB_TRANSFER_SIZE_TEST_INCLUDED_

class ahb_transfer_size_test extends ahb_base_test;

    `uvm_component_utils(ahb_transfer_size_test)

    // Bursts (+NUM_ITER=<n>). 12 per full sweep
    int unsigned num_iter = 24;

    // Illegal HSIZE randomization check (+CHK_SIZE_ENCODINGS=0 to disable)
    int unsigned chk_size_encodings = 1;

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
        void'($value$plusargs("CHK_SIZE_ENCODINGS=%d", chk_size_encodings));
    endfunction : build_phase

    //-------------------------------------------------------------------------
    // Run phase
    //-------------------------------------------------------------------------
    task run_phase(uvm_phase phase);
        ahb_size_seq seq;

        phase.raise_objection(this, "transfer size test running");
        phase.phase_done.set_drain_time(this, 200ns);

        seq                    = ahb_size_seq::type_id::create("seq");
        seq.num_iter           = num_iter;
        seq.chk_size_encodings = (chk_size_encodings != 0);
        seq.start(env.master_agent.sqr);

        phase.drop_objection(this, "transfer size test done");
    endtask : run_phase

endclass : ahb_transfer_size_test

`endif // AHB_TRANSFER_SIZE_TEST_INCLUDED_
