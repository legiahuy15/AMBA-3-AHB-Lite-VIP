//=============================================================================
// File        : ahb_byte_lane_test.sv
// Project     : AMBA 3 AHB-Lite VIP
// Author      : Huy Le
// Description : Byte-lane test. Runs ahb_byte_lane_seq: narrow transfers on
//               every byte lane, inverted data on unused lanes.
//               vplan: AHB_DAT_003, AHB_DAT_004.
//=============================================================================

`ifndef AHB_BYTE_LANE_TEST_INCLUDED_
`define AHB_BYTE_LANE_TEST_INCLUDED_

class ahb_byte_lane_test extends ahb_base_test;

    `uvm_component_utils(ahb_byte_lane_test)

    // Slots (+NUM_ITER=<n>). >= 3 to reach every lane (size rotates per slot)
    int unsigned num_iter = 12;

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
        ahb_byte_lane_seq seq;

        phase.raise_objection(this, "byte lane test running");
        phase.phase_done.set_drain_time(this, 200ns);

        seq          = ahb_byte_lane_seq::type_id::create("seq");
        seq.num_iter = num_iter;
        seq.start(env.master_agent.sqr);

        phase.drop_objection(this, "byte lane test done");
    endtask : run_phase

endclass : ahb_byte_lane_test

`endif // AHB_BYTE_LANE_TEST_INCLUDED_
