//=============================================================================
// File        : ahb_master_driver.sv
// Project     : AMBA 3 AHB-Lite VIP
// Author      : Huy Le
// Description : AHB-Lite master driver. Pipelined address/data phases, BUSY,
//               ERROR handling, back-to-back overlap, outstanding limit.
//=============================================================================

class ahb_master_driver extends uvm_driver #(ahb_transaction);

    `uvm_component_utils(ahb_master_driver)

    // Virtual interface handle
    virtual ahb_if vif;

    // See ahb_agent_config
    bit en_back_to_back = 1;
    bit en_idle_to_nonseq_in_wait = 0;
    int unsigned max_outstanding = 0;

    // Accepted, not yet driven
    protected ahb_transaction drive_queue[$];

    // Next txn with beat-0 address phase already on the bus
    protected ahb_transaction next_tr;

    // Txn on the bus (for reset flush)
    protected ahb_transaction active_tr;

    // Objection tracking
    protected uvm_phase run_phase_handle;
    protected int unsigned active_objections_cnt = 0;

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction : new

    //-------------------------------------------------------------------------
    // Build phase - vif and agent config
    //-------------------------------------------------------------------------
    function void build_phase(uvm_phase phase);
        ahb_agent_config cfg;
        super.build_phase(phase);
        if(!uvm_config_db#(virtual ahb_if)::get(this, "", "vif", vif))
            `uvm_fatal(get_type_name(), "Virtual interface not found in config_db")
        // Optional
        if (uvm_config_db#(ahb_agent_config)::get(this, "", "cfg", cfg)) begin
            en_back_to_back           = cfg.en_back_to_back;
            en_idle_to_nonseq_in_wait = cfg.en_idle_to_nonseq_in_wait;
            max_outstanding           = cfg.max_outstanding;
        end
    endfunction: build_phase

    //-------------------------------------------------------------------------
    // Run phase - accept loop and bus loop in parallel; restart on reset
    //-------------------------------------------------------------------------
    virtual task run_phase(uvm_phase phase);
        run_phase_handle = phase;
        forever begin
            reset_signals();
            if (!vif.rst_n) @(posedge vif.rst_n);
            `uvm_info(get_type_name(), "Reset deasserted - master driver active", UVM_MEDIUM)

            fork
                begin : accept_loop
                    forever begin
                        ahb_transaction tr;
                        // Outstanding limit
                        if (max_outstanding != 0)
                            wait (active_objections_cnt < max_outstanding);
                        seq_item_port.get_next_item(tr);
                        `uvm_info(get_type_name(),
                                  $sformatf("Queueing [%s]: HADDR=0x%08h, HBURST=%s, HSIZE=%s, %0d beats",
                                            tr.write.name(), tr.addr, tr.burst.name(),
                                            tr.size.name(), tr.get_num_beats()), UVM_MEDIUM)

                        raise_driver_objection("Pending AHB transaction");
                        drive_queue.push_back(tr);

                        seq_item_port.item_done();
                    end
                end
                bus_drive_loop();
                begin : rst_watch
                    @(negedge vif.rst_n);
                    `uvm_info(get_type_name(),
                              "Reset asserted - aborting transaction", UVM_MEDIUM)
                end
            join_any
            disable fork;
        end
    endtask : run_phase

    //-------------------------------------------------------------------------
    // bus_drive_loop - drive queued txns in order. next_tr first if set
    // (beat-0 address phase already accepted)
    //-------------------------------------------------------------------------
    task bus_drive_loop();
        forever begin
            ahb_transaction tr;
            bit addr_in_flight;

            if (next_tr != null) begin
                tr = next_tr;
                next_tr = null;
                addr_in_flight = 1;
            end else begin
                wait(drive_queue.size() > 0);
                tr = drive_queue.pop_front();
                addr_in_flight = 0;
            end

            `uvm_info(get_type_name(),
                      $sformatf("Driving [%s]: HADDR=0x%08h, HBURST=%s, HSIZE=%s, %0d beats%s",
                                 tr.write.name(), tr.addr, tr.burst.name(),
                                 tr.size.name(), tr.get_num_beats(),
                                 addr_in_flight ? " (back-to-back)" : ""), UVM_MEDIUM)

            active_tr = tr;
            drive_transaction(tr, addr_in_flight);
            active_tr = null;

            drop_driver_objection("AHB transaction completed");
            complete_txn(tr, 1'b0);
        end
    endtask : bus_drive_loop

    //-------------------------------------------------------------------------
    // complete_txn - set aborted and done in the same time step
    //-------------------------------------------------------------------------
    function void complete_txn(ahb_transaction tr, bit is_aborted);
        tr.aborted = is_aborted;
        tr.done    = 1'b1;
    endfunction : complete_txn

    //-------------------------------------------------------------------------
    // Objection helpers
    //-------------------------------------------------------------------------
    function void raise_driver_objection(string desc = "");
        if (run_phase_handle != null) begin
            run_phase_handle.raise_objection(this, desc);
            active_objections_cnt++;
        end
    endfunction

    function void drop_driver_objection(string desc = "");
        if (run_phase_handle != null && active_objections_cnt > 0) begin
            run_phase_handle.drop_objection(this, desc);
            active_objections_cnt--;
        end
    endfunction

    //-------------------------------------------------------------------------
    // flush_pending - abort active, next and queued txns
    //-------------------------------------------------------------------------
    function void flush_pending(string reason = "");
        ahb_transaction tr;
        if (active_tr != null) begin
            complete_txn(active_tr, 1'b1);
            active_tr = null;
        end
        if (next_tr != null) begin
            complete_txn(next_tr, 1'b1);
            next_tr = null;
        end
        while (drive_queue.size() > 0) begin
            tr = drive_queue.pop_front();
            complete_txn(tr, 1'b1);
        end
        if (reason != "")
            `uvm_info(get_type_name(),
                      $sformatf("Flushed pending transactions (%s)", reason), UVM_MEDIUM)
    endfunction

    function void clear_objections();
        if (run_phase_handle != null) begin
            repeat (active_objections_cnt) begin
                run_phase_handle.drop_objection(this, "Reset cleanup");
            end
        end
        active_objections_cnt = 0;
    endfunction

    //-------------------------------------------------------------------------
    // drive_transaction - addr[i+1] overlaps data[i]. Handles BUSY, trailing
    // BUSY, ERROR policy, back-to-back overlap.
    // addr_in_flight = 1: beat 0 already accepted
    //-------------------------------------------------------------------------
    task drive_transaction(ahb_transaction tr, bit addr_in_flight = 0);
        int num_beats;
        int n_busy;
        bit pipelined_own;   // address slot belongs to this burst
        bit busy_retracted;  // BUSY replaced during this wait
        bit idle_slot;       // IDLE in slot, may change to NONSEQ
        bit [AHB_ADDR_WIDTH-1:0] beat_addr[];

        num_beats     = tr.get_num_beats();
        tr.beats_done = 0;

        // Beat addresses
        beat_addr = new[num_beats];
        beat_addr[0] = tr.addr;
        for (int i = 1; i < num_beats; i++)
            beat_addr[i] = calc_next_addr(tr, beat_addr[i-1]);

        if (!addr_in_flight) begin
            // Beat 0 address phase, wait for HREADY
            @(vif.master_cb);
            drive_addr_phase0(tr);

            do begin
                @(vif.master_cb);
            end while (vif.master_cb.HREADY !== 1'b1);
        end

        // Per beat: data[i], then next address phase (BUSY, addr[i+1], or
        // overlap/IDLE after the last beat)
        for (int i = 0; i < num_beats; i++) begin

            // Write data for beat i
            if (tr.write == AHB_WRITE)
                vif.master_cb.HWDATA <= tr.wdata[i];

            // BUSY before beat i+1, or trailing BUSY after the last beat
            if (i < num_beats - 1)
                n_busy = (i+1 < tr.busy_cycles.size()) ? tr.busy_cycles[i+1] : 0;
            else
                n_busy = tr.trailing_busy_cycles;

            // Next address phase (BUSY carries the next address)
            pipelined_own = 1'b1;
            idle_slot     = 1'b0;
            if (n_busy > 0) begin
                vif.master_cb.HTRANS <= AHB_TRANS_BUSY;
                vif.master_cb.HADDR  <= (i < num_beats - 1)
                                        ? beat_addr[i+1]
                                        : calc_next_addr(tr, beat_addr[i]);
            end else if (i < num_beats - 1) begin
                vif.master_cb.HADDR  <= beat_addr[i+1];
                vif.master_cb.HTRANS <= tr.trans[i+1];
            end else begin
                // Last beat: next txn's NONSEQ, else IDLE. With
                // en_idle_to_nonseq_in_wait, NONSEQ is set in the wait loop
                if (en_back_to_back && !en_idle_to_nonseq_in_wait &&
                    drive_queue.size() > 0)
                    next_tr = drive_queue.pop_front();
                if (next_tr != null) begin
                    drive_addr_phase0(next_tr);
                    pipelined_own = 1'b0;
                end else begin
                    vif.master_cb.HTRANS <= AHB_TRANS_IDLE;
                    idle_slot = en_back_to_back && en_idle_to_nonseq_in_wait;
                end
            end

            // Wait for HREADY
            busy_retracted = 1'b0;
            forever begin
                @(vif.master_cb);
                if (vif.master_cb.HREADY === 1'b1) break;

                // ERROR first cycle: cancel own slot to IDLE
                if (vif.master_cb.HRESP === AHB_RESP_ERROR &&
                    tr.abort_on_error && pipelined_own) begin
                    vif.master_cb.HTRANS <= AHB_TRANS_IDLE;
                    // Optional address change (IHI0033A 3.6.2)
                    if (tr.addr_change_on_error)
                        vif.master_cb.HADDR <= (drive_queue.size() > 0)
                                               ? drive_queue[0].addr : '0;
                end
                // Replace BUSY once, then hold until HREADY
                else if (tr.busy_retract_in_wait && n_busy > 0 && !busy_retracted) begin
                    busy_retracted = 1'b1;
                    n_busy         = 0;
                    if (i < num_beats - 1) begin
                        // BUSY -> SEQ
                        vif.master_cb.HTRANS <= tr.trans[i+1];
                    end else begin
                        // End of INCR: BUSY -> NONSEQ (next txn) or IDLE
                        if (en_back_to_back && drive_queue.size() > 0)
                            next_tr = drive_queue.pop_front();
                        if (next_tr != null) begin
                            drive_addr_phase0(next_tr);
                            pipelined_own = 1'b0;
                        end else begin
                            vif.master_cb.HTRANS <= AHB_TRANS_IDLE;
                        end
                    end
                end
                // IDLE -> NONSEQ during wait (not on ERROR), once
                else if (idle_slot && drive_queue.size() > 0 &&
                         vif.master_cb.HRESP === AHB_RESP_OKAY) begin
                    idle_slot     = 1'b0;
                    next_tr       = drive_queue.pop_front();
                    drive_addr_phase0(next_tr);
                    pipelined_own = 1'b0;
                end
            end

            // Sample response
            if (tr.write == AHB_READ)
                tr.rdata[i] = vif.master_cb.HRDATA;
            tr.resp[i]    = ahb_resp_e'(vif.master_cb.HRESP);
            tr.beats_done = i + 1;

            `uvm_info(get_type_name(),
                      $sformatf("Beat[%0d/%0d] addr=0x%08h trans=%s resp=%s %s=0x%08h",
                                i, num_beats, beat_addr[i],
                                tr.trans[i].name(),
                                tr.resp[i].name(),
                                (tr.write == AHB_WRITE) ? "wdata" : "rdata",
                                (tr.write == AHB_WRITE) ? tr.wdata[i] : tr.rdata[i]),
                      UVM_HIGH)

            // ERROR: abort_on_error=1 -> stop (own slot IDLE), 0 -> continue
            if (tr.resp[i] == AHB_RESP_ERROR) begin
                if (tr.abort_on_error) begin
                    `uvm_info(get_type_name(),
                              $sformatf("ERROR response on beat %0d/%0d%s",
                                        i, num_beats,
                                        (i < num_beats - 1) ? " - cancelling remaining burst" : ""),
                              UVM_MEDIUM)
                    if (pipelined_own)
                        vif.master_cb.HTRANS <= AHB_TRANS_IDLE;
                    break;
                end
                `uvm_info(get_type_name(),
                          $sformatf("ERROR response on beat %0d/%0d - continuing burst (abort_on_error=0)",
                                    i, num_beats), UVM_MEDIUM)
            end

            // Remaining BUSY cycles, then SEQ or IDLE
            if (n_busy > 0) begin
                repeat (n_busy - 1) begin
                    do @(vif.master_cb); while (vif.master_cb.HREADY !== 1'b1);
                end
                if (i < num_beats - 1) begin
                    vif.master_cb.HADDR  <= beat_addr[i+1];
                    vif.master_cb.HTRANS <= tr.trans[i+1];
                end else begin
                    // Trailing BUSY -> IDLE
                    vif.master_cb.HTRANS <= AHB_TRANS_IDLE;
                end
                do @(vif.master_cb); while (vif.master_cb.HREADY !== 1'b1);
            end
        end

        // Clear HWDATA if no overlapped txn
        if (next_tr == null)
            vif.master_cb.HWDATA <= '0;

        `uvm_info(get_type_name(),
                  $sformatf("Transaction complete: %s 0x%08h, %0d beats, burst=%s",
                            tr.write.name(), tr.addr, num_beats, tr.burst.name()),
                  UVM_MEDIUM)
    endtask : drive_transaction

    //-------------------------------------------------------------------------
    // drive_addr_phase0 - beat-0 address/control
    //-------------------------------------------------------------------------
    task drive_addr_phase0(ahb_transaction tr);
        vif.master_cb.HADDR     <= tr.addr;
        vif.master_cb.HBURST    <= tr.burst;
        vif.master_cb.HMASTLOCK <= tr.lock;
        vif.master_cb.HPROT     <= tr.prot;
        vif.master_cb.HSIZE     <= tr.size;
        vif.master_cb.HTRANS    <= tr.trans[0];
        vif.master_cb.HWRITE    <= tr.write;
    endtask : drive_addr_phase0

    //-------------------------------------------------------------------------
    // calc_next_addr - next beat address
    //   INCR: addr + 2^HSIZE
    //   WRAP: wraps at num_beats * 2^HSIZE
    //-------------------------------------------------------------------------
    function bit [AHB_ADDR_WIDTH-1:0] calc_next_addr(
        ahb_transaction tr,
        bit [AHB_ADDR_WIDTH-1:0] current_addr
    );
        int unsigned bytes_per_beat;
        int unsigned wrap_boundary;
        bit [AHB_ADDR_WIDTH-1:0] next_addr;
        bit [AHB_ADDR_WIDTH-1:0] wrap_mask;

        bytes_per_beat = 1 << tr.size;
        next_addr = current_addr + bytes_per_beat;

        case (tr.burst)
            AHB_BURST_INCR,
            AHB_BURST_INCR4,
            AHB_BURST_INCR8,
            AHB_BURST_INCR16: begin
                return next_addr;
            end

            AHB_BURST_WRAP4,
            AHB_BURST_WRAP8,
            AHB_BURST_WRAP16: begin
                wrap_boundary = tr.get_num_beats() * bytes_per_beat;
                wrap_mask = wrap_boundary - 1;
                return (current_addr & ~wrap_mask) | (next_addr & wrap_mask);
            end

            default: return next_addr;
        endcase
    endfunction : calc_next_addr

    //-------------------------------------------------------------------------
    // reset_signals - drive reset values, flush txns, drop objections
    //-------------------------------------------------------------------------
    task reset_signals();
        @(vif.master_cb);
        vif.master_cb.HTRANS    <= AHB_TRANS_IDLE;
        vif.master_cb.HMASTLOCK <= 1'b0;
        vif.master_cb.HADDR     <= '0;
        vif.master_cb.HBURST    <= '0;
        vif.master_cb.HPROT     <= '0;
        vif.master_cb.HSIZE     <= '0;
        vif.master_cb.HWRITE    <= 1'b0;
        vif.master_cb.HWDATA    <= '0;

        flush_pending("reset");
        clear_objections();
    endtask : reset_signals

endclass : ahb_master_driver