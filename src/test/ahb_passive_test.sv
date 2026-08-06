//=============================================================================
// File        : ahb_passive_test.sv
// Project     : AMBA 3 AHB-Lite VIP
// Description : Verifies slave-agent passive mode. The master drives traffic;
//               the passive slave creates only its monitor and observes it.
//=============================================================================

`ifndef AHB_PASSIVE_TEST_INCLUDED_
`define AHB_PASSIVE_TEST_INCLUDED_

class ahb_passive_test extends ahb_base_test;

    `uvm_component_utils(ahb_passive_test)

    int unsigned num_iter = 12;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction : new

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        env_cfg.slave_agent_cfg.is_active = UVM_PASSIVE;
        void'($value$plusargs("NUM_ITER=%d", num_iter));
    endfunction : build_phase

    function void end_of_elaboration_phase(uvm_phase phase);
        super.end_of_elaboration_phase(phase);

        if (env.slave_agent.mon == null)
            `uvm_fatal(get_type_name(), "Passive slave monitor was not created")
        if (env.slave_agent.drv != null || env.slave_agent.sqr != null)
            `uvm_fatal(get_type_name(),
                       "Passive slave unexpectedly created a driver or sequencer")
    endfunction : end_of_elaboration_phase

    task run_phase(uvm_phase phase);
        ahb_passive_seq seq;

        phase.raise_objection(this, "passive test running");
        phase.phase_done.set_drain_time(this, 200ns);

        seq = ahb_passive_seq::type_id::create("seq");
        seq.num_iter = num_iter;
        seq.start(env.master_agent.sqr);

        phase.drop_objection(this, "passive test done");
    endtask : run_phase

endclass : ahb_passive_test

`endif // AHB_PASSIVE_TEST_INCLUDED_
