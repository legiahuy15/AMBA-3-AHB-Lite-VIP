//=============================================================================
// File        : ahb_back_to_back_test.sv
// Project     : AMBA 3 AHB-Lite VIP
// Author      : Huy Le
// Description : Back-to-back transfer test. Runs ahb_back_to_back_seq
//               (pipelined bursts, max_outstanding sweep) and counts NONSEQ
//               starts with no IDLE before them.
//               vplan: AHB_BAS_003, AHB_BAS_004, AHB_ENV_004.
//=============================================================================

`ifndef AHB_BACK_TO_BACK_TEST_INCLUDED_
`define AHB_BACK_TO_BACK_TEST_INCLUDED_

class ahb_back_to_back_test extends ahb_base_test;

    `uvm_component_utils(ahb_back_to_back_test)

    // Write/read pairs (+NUM_ITER=<n>)
    int unsigned num_iter = 32;

    // Pairs queued per batch (+BATCH_PAIRS=<n>)
    int unsigned batch_pairs = 4;

    //-------------------------------------------------------------------------
    // Bus statistics (watch_bus)
    //-------------------------------------------------------------------------
    protected int unsigned num_bursts;      // NONSEQ address phases accepted
    protected int unsigned num_b2b_starts;  // NONSEQ with no IDLE before
    protected int unsigned num_idle_cycles; // IDLE accepted

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction : new

    //-------------------------------------------------------------------------
    // Build phase - immediate overlap, 0-1 wait states. max_outstanding is
    // swept by the sequence
    //-------------------------------------------------------------------------
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        env_cfg.master_agent_cfg.en_back_to_back           = 1;
        env_cfg.master_agent_cfg.en_idle_to_nonseq_in_wait = 0;
        env_cfg.master_agent_cfg.max_outstanding           = 0;

        env_cfg.slave_agent_cfg.auto_gen_resp   = 1;    // memory-model loopback
        env_cfg.slave_agent_cfg.ready_delay_min = 0;
        env_cfg.slave_agent_cfg.ready_delay_max = 1;

        void'($value$plusargs("NUM_ITER=%d", num_iter));
        void'($value$plusargs("BATCH_PAIRS=%d", batch_pairs));
    endfunction : build_phase

    //-------------------------------------------------------------------------
    // watch_bus - count NONSEQ accepted right after NONSEQ/SEQ
    // (AHB_BAS_003, AHB_BAS_004)
    //-------------------------------------------------------------------------
    task watch_bus();
        virtual ahb_if vif;
        ahb_trans_e    prev_t;
        ahb_trans_e    cur_t;

        vif    = env_cfg.master_vif;
        prev_t = AHB_TRANS_IDLE;

        forever begin
            @(vif.monitor_cb);

            if (!vif.rst_n) begin
                prev_t = AHB_TRANS_IDLE;
                continue;
            end

            // Accepted address phases only
            if (vif.monitor_cb.HREADY !== 1'b1) continue;

            cur_t = ahb_trans_e'(vif.monitor_cb.HTRANS);
            case (cur_t)
                AHB_TRANS_NONSEQ: begin
                    num_bursts++;
                    if (prev_t inside {AHB_TRANS_NONSEQ, AHB_TRANS_SEQ})
                        num_b2b_starts++;
                end
                AHB_TRANS_IDLE: num_idle_cycles++;
                default: ;      // SEQ, BUSY
            endcase
            prev_t = cur_t;
        end
    endtask : watch_bus

    //-------------------------------------------------------------------------
    // Run phase - watch_bus never returns; join_any ends on the sequence
    //-------------------------------------------------------------------------
    task run_phase(uvm_phase phase);
        ahb_back_to_back_seq seq;

        phase.raise_objection(this, "back-to-back test running");
        phase.phase_done.set_drain_time(this, 200ns);

        seq             = ahb_back_to_back_seq::type_id::create("seq");
        seq.num_iter    = num_iter;
        seq.batch_pairs = batch_pairs;

        // Null if the master agent is passive (no sweep)
        seq.mst_drv = env.master_agent.drv;

        fork
            watch_bus();
            seq.start(env.master_agent.sqr);
        join_any
        disable fork;

        // At least one back-to-back start required
        `uvm_info(get_type_name(),
                  $sformatf("Bus: %0d bursts, %0d back-to-back starts, %0d IDLE cycles",
                            num_bursts, num_b2b_starts, num_idle_cycles),
                  (num_b2b_starts > 0) ? UVM_LOW : UVM_NONE)

        if (num_b2b_starts == 0)
            `uvm_error(get_type_name(),
                       "No back-to-back burst start observed - every transfer opened after an IDLE bubble")

        phase.drop_objection(this, "back-to-back test done");
    endtask : run_phase

endclass : ahb_back_to_back_test

`endif // AHB_BACK_TO_BACK_TEST_INCLUDED_
