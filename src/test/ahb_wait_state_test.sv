//=============================================================================
// File        : ahb_wait_state_test.sv
// Project     : AMBA 3 AHB-Lite VIP
// Author      : Huy Le
// Description : Wait-state test (ahb_wait_state_seq). Sweeps slave wait states
//               from 0 to 16 (IHI0033A 5.1.2).
//               vplan: AHB_WAI_001..004, AHB_WAI_009, AHB_BAS_005, AHB_BAS_006,
//               AHB_RSP_002, AHB_DAT_001.
//=============================================================================

`ifndef AHB_WAIT_STATE_TEST_INCLUDED_
`define AHB_WAIT_STATE_TEST_INCLUDED_

class ahb_wait_state_test extends ahb_base_test;

    `uvm_component_utils(ahb_wait_state_test)

    // Bursts (+NUM_ITER=<n>)
    int unsigned num_iter = 24;

    // Max wait states in the sweep (+WAIT_MAX=<n>)
    int unsigned wait_max = 16;

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction : new

    //-------------------------------------------------------------------------
    // Build phase - auto-response slave; ready_delay_min/max set by the
    // sequence
    //-------------------------------------------------------------------------
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        env_cfg.slave_agent_cfg.auto_gen_resp   = 1;
        env_cfg.slave_agent_cfg.ready_delay_min = 0;
        env_cfg.slave_agent_cfg.ready_delay_max = 0;

        // Address phase during wait states; IDLE->NONSEQ in wait (AHB_WAI_004)
        env_cfg.master_agent_cfg.en_back_to_back          = 1;
        env_cfg.master_agent_cfg.en_idle_to_nonseq_in_wait = 1;

        void'($value$plusargs("NUM_ITER=%d", num_iter));
        void'($value$plusargs("WAIT_MAX=%d", wait_max));
    endfunction : build_phase

    //-------------------------------------------------------------------------
    // Run phase - drain time > longest beat (17 cycles)
    //-------------------------------------------------------------------------
    task run_phase(uvm_phase phase);
        ahb_wait_state_seq seq;

        phase.raise_objection(this, "wait state test running");
        phase.phase_done.set_drain_time(this, 500ns);

        seq          = ahb_wait_state_seq::type_id::create("seq");
        seq.num_iter = num_iter;
        seq.wait_max = wait_max;

        // Null if the slave agent is passive (no sweep)
        seq.slv_drv = env.slave_agent.drv;

        seq.start(env.master_agent.sqr);

        phase.drop_objection(this, "wait state test done");
    endtask : run_phase

endclass : ahb_wait_state_test

`endif // AHB_WAIT_STATE_TEST_INCLUDED_
