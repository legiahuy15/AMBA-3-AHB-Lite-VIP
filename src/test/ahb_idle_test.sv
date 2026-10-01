//=============================================================================
// File        : ahb_idle_test.sv
// Project     : AMBA 3 AHB-Lite VIP
// Author      : Huy Le
// Description : IDLE transfer test. Runs ahb_idle_seq and checks on the bus:
//               zero-wait OKAY for IDLE/BUSY, only IDLE/NONSEQ after IDLE,
//               HADDR change under a waited IDLE.
//               vplan: AHB_TRN_001, AHB_TRN_006, AHB_WAI_007, AHB_WAI_010.
//=============================================================================

`ifndef AHB_IDLE_TEST_INCLUDED_
`define AHB_IDLE_TEST_INCLUDED_

class ahb_idle_test extends ahb_base_test;

    `uvm_component_utils(ahb_idle_test)

    // Write/read pairs (+NUM_ITER=<n>)
    int unsigned num_iter = 24;

    // Max IDLE run between transfers (+MAX_GAP=<n>)
    int unsigned max_gap = 4;

    //-------------------------------------------------------------------------
    // Bus statistics (watch_bus)
    //-------------------------------------------------------------------------
    protected int unsigned num_idle_accepted;   // IDLE with HREADY=1
    protected int unsigned num_idle_waited;     // IDLE with HREADY=0
    protected int unsigned num_busy_accepted;   // BUSY with HREADY=1
    protected int unsigned num_bursts;          // NONSEQ accepted
    protected int unsigned longest_idle_run;    // consecutive accepted IDLEs

    // HADDR changed under IDLE with HREADY=0 (AHB_WAI_007)
    protected int unsigned num_idle_wait_addr_change;

    // Violations
    protected int unsigned num_resp_viol;       // IDLE/BUSY not zero-wait OKAY
    protected int unsigned num_order_viol;      // SEQ/BUSY after IDLE

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction : new

    //-------------------------------------------------------------------------
    // Build phase - auto-response slave (memory model for read-back), deferred
    // overlap so IDLE can be presented with HREADY=0. Wait states set per
    // phase by the sequence
    //-------------------------------------------------------------------------
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        env_cfg.slave_agent_cfg.auto_gen_resp   = 1;
        env_cfg.slave_agent_cfg.ready_delay_min = 0;
        env_cfg.slave_agent_cfg.ready_delay_max = 0;

        env_cfg.master_agent_cfg.en_back_to_back           = 1;
        env_cfg.master_agent_cfg.en_idle_to_nonseq_in_wait = 1;

        void'($value$plusargs("NUM_ITER=%d", num_iter));
        void'($value$plusargs("MAX_GAP=%d", max_gap));
    endfunction : build_phase

    //-------------------------------------------------------------------------
    // watch_bus - classify each cycle, check IDLE rules on the next cycle
    //-------------------------------------------------------------------------
    task watch_bus();
        virtual ahb_if           vif;
        ahb_trans_e              prev_t;
        bit                      prev_ready;
        bit                      prev_valid;    // prev_* holds a sampled cycle
        bit [AHB_ADDR_WIDTH-1:0] prev_addr;
        ahb_trans_e              cur_t;
        bit                      cur_ready;
        ahb_resp_e               cur_resp;
        int unsigned             run;           // accepted IDLEs in a row

        vif        = env_cfg.master_vif;
        prev_valid = 0;
        run        = 0;

        forever begin
            @(vif.monitor_cb);

            if (!vif.rst_n) begin
                prev_valid = 0;
                run        = 0;
                continue;
            end

            cur_t     = ahb_trans_e'(vif.monitor_cb.HTRANS);
            cur_ready = (vif.monitor_cb.HREADY === 1'b1);
            cur_resp  = ahb_resp_e'(vif.monitor_cb.HRESP);

            //-----------------------------------------------------------------
            // Checks on the previous cycle
            //-----------------------------------------------------------------
            if (prev_valid) begin
                // Accepted IDLE/BUSY -> zero-wait OKAY (AHB_TRN_001, AHB_WAI_010)
                if (prev_ready && prev_t inside {AHB_TRANS_IDLE, AHB_TRANS_BUSY}
                    && (!cur_ready || cur_resp != AHB_RESP_OKAY)) begin
                    num_resp_viol++;
                    `uvm_error(get_type_name(),
                               $sformatf("%s transfer not answered zero-wait OKAY: HREADY=%0b HRESP=%s",
                                         prev_t.name(), cur_ready, cur_resp.name()))
                end

                // Accepted IDLE -> IDLE or NONSEQ only (AHB_TRN_006)
                if (prev_ready && prev_t == AHB_TRANS_IDLE &&
                    !(cur_t inside {AHB_TRANS_IDLE, AHB_TRANS_NONSEQ})) begin
                    num_order_viol++;
                    `uvm_error(get_type_name(),
                               $sformatf("%s followed an accepted IDLE (only IDLE or NONSEQ allowed)",
                                         cur_t.name()))
                end

                // HADDR change under a waited IDLE - legal, counted (AHB_WAI_007)
                if (!prev_ready && prev_t == AHB_TRANS_IDLE &&
                    vif.monitor_cb.HADDR !== prev_addr)
                    num_idle_wait_addr_change++;
            end

            //-----------------------------------------------------------------
            // Cycle classification
            //-----------------------------------------------------------------
            case (cur_t)
                AHB_TRANS_IDLE: begin
                    if (cur_ready) begin
                        num_idle_accepted++;
                        run++;
                        if (run > longest_idle_run) longest_idle_run = run;
                    end else begin
                        num_idle_waited++;
                    end
                end
                AHB_TRANS_BUSY: begin
                    run = 0;
                    if (cur_ready) num_busy_accepted++;
                end
                AHB_TRANS_NONSEQ: begin
                    run = 0;
                    if (cur_ready) num_bursts++;
                end
                default: run = 0;   // SEQ
            endcase

            prev_t     = cur_t;
            prev_ready = cur_ready;
            prev_addr  = vif.monitor_cb.HADDR;
            prev_valid = 1;
        end
    endtask : watch_bus

    //-------------------------------------------------------------------------
    // Run phase - watch_bus never returns; join_any ends on the sequence
    //-------------------------------------------------------------------------
    task run_phase(uvm_phase phase);
        ahb_idle_seq seq;

        phase.raise_objection(this, "idle test running");
        phase.phase_done.set_drain_time(this, 200ns);

        seq          = ahb_idle_seq::type_id::create("seq");
        seq.num_iter = num_iter;
        seq.max_gap  = max_gap;

        // Clock for IDLE gap timing
        seq.vif = env_cfg.master_vif;

        // Null if the slave agent is passive (fixed back-pressure)
        seq.slv_drv = env.slave_agent.drv;

        fork
            watch_bus();
            seq.start(env.master_agent.sqr);
        join_any
        disable fork;

        check_bus();

        phase.drop_objection(this, "idle test done");
    endtask : run_phase

    //-------------------------------------------------------------------------
    // check_bus - required scenarios were exercised
    //-------------------------------------------------------------------------
    function void check_bus();
        `uvm_info(get_type_name(),
                  $sformatf("Bus: %0d bursts, %0d IDLE accepted (longest run %0d), %0d IDLE waited, %0d BUSY accepted, %0d address moves under a waited IDLE",
                            num_bursts, num_idle_accepted, longest_idle_run,
                            num_idle_waited, num_busy_accepted,
                            num_idle_wait_addr_change),
                  (num_resp_viol == 0 && num_order_viol == 0) ? UVM_LOW : UVM_NONE)

        if (num_idle_accepted == 0)
            `uvm_error(get_type_name(),
                       "No IDLE transfer was accepted - the bus never went idle")

        if (longest_idle_run < 2)
            `uvm_error(get_type_name(),
                       $sformatf("Longest IDLE run was %0d cycle(s) - back-to-back IDLE transfers were never exercised",
                                 longest_idle_run))

        if (num_busy_accepted == 0)
            `uvm_error(get_type_name(),
                       "No BUSY transfer was accepted - the zero-wait OKAY rule was only checked for IDLE")

        if (num_idle_waited == 0)
            `uvm_error(get_type_name(),
                       "IDLE was never presented with HREADY low - the pipelined slot never opened inside a wait state")

        if (num_idle_wait_addr_change == 0)
            `uvm_error(get_type_name(),
                       "The address never moved under a waited IDLE - AHB_WAI_007 was not exercised")
    endfunction : check_bus

endclass : ahb_idle_test

`endif // AHB_IDLE_TEST_INCLUDED_
