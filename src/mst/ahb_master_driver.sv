//=============================================================================
// File        : ahb_master_driver.sv
// Project     : AMBA 3 AHB-Lite VIP
// Author      : Huy Le
// Description : AHB-Lite master driver. Pulls sequence items and drives them
//               onto the bus via the master clocking block.
//               This file is `included inside ahb_pkg.sv.
//=============================================================================

class ahb_master_driver extends uvm_driver #(ahb_transaction);

    `uvm_component_utils(ahb_master_driver)

    // Virtual interface handle
    virtual ahb_if vif;

    // Back-to-back pipelining state
    bit             en_back_to_back = 1;  // overlap next txn's addr phase into last data phase
    ahb_transaction next_tr;              // prefetched item, beat-0 addr phase in flight
    bit             early_done;           // item_done() already called for current item

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction : new

    //-------------------------------------------------------------------------
    // Build phase - get virtual interface from config_db
    //-------------------------------------------------------------------------
    function void build_phase(uvm_phase phase);
        ahb_agent_config cfg;
        super.build_phase(phase);
        if(!uvm_config_db#(virtual ahb_if)::get(this, "", "vif", vif))
            `uvm_fatal(get_type_name(), "Virtual interface not found in config_db")
        // Agent config is optional - keep the default when absent
        if (uvm_config_db#(ahb_agent_config)::get(this, "", "cfg", cfg))
            en_back_to_back = cfg.en_back_to_back;
    endfunction: build_phase

    //-------------------------------------------------------------------------
    // Run phase - main driver loop
    //-------------------------------------------------------------------------
    virtual task run_phase(uvm_phase phase);
        forever begin
            reset_signals();
            // Wait until reset is de-asserted
            if (!vif.rst_n) @(posedge vif.rst_n);
            `uvm_info(get_type_name(), "Reset deasserted - master driver active", UVM_MEDIUM)

            forever begin
                ahb_transaction tr;
                bit addr_in_flight;

                // Prefetched item: beat-0 addr phase already driven & accepted
                if (next_tr != null) begin
                    tr = next_tr;
                    next_tr = null;
                    addr_in_flight = 1;
                end else begin
                    seq_item_port.get_next_item(tr);
                    addr_in_flight = 0;
                end
                early_done = 0;

                `uvm_info(get_type_name(),
                          $sformatf("Driving [%s]: HADDR=0x%08h, HBURST=%s, HSIZE=%s, %0d beats%s",
                                     tr.write.name(), tr.addr, tr.burst.name(),
                                     tr.size.name(), tr.get_num_beats(),
                                     addr_in_flight ? " (back-to-back)" : ""), UVM_MEDIUM)
                fork
                    begin : drive_item
                        drive_transaction(tr, addr_in_flight);
                    end
                    begin : rst_watch
                        // Fire now if reset already low, else on its falling edge
                        if (vif.rst_n) @(negedge vif.rst_n);
                        `uvm_info(get_type_name(),
                                  "Reset asserted - aborting transaction", UVM_MEDIUM)
                    end
                join_any
                disable fork;
                if (!early_done)
                    seq_item_port.item_done();

                if (!vif.rst_n) break;   // fall out to re-run reset_signals()
            end

            // Discard prefetched item aborted by reset (close its open handshake)
            if (next_tr != null) begin
                seq_item_port.item_done();
                next_tr = null;
            end
        end
    endtask : run_phase

    //-------------------------------------------------------------------------
    // Drive one transaction - pipelined: addr[i+1] overlaps data[i].
    // Handles BUSY insertion, INCR termination out of BUSY, ERROR policy
    // (abort/continue), and back-to-back overlap of the next transaction.
    // addr_in_flight=1: beat 0 already driven & accepted by previous overlap
    //-------------------------------------------------------------------------
    task drive_transaction(ahb_transaction tr, bit addr_in_flight = 0);
        int num_beats;
        int n_busy;
        bit pipelined_own;   // pipelined slot belongs to this burst (cancellable on ERROR)
        bit [AHB_ADDR_WIDTH-1:0] beat_addr[];

        num_beats = tr.get_num_beats();

        // Pre-compute beat addresses
        beat_addr = new[num_beats];
        beat_addr[0] = tr.addr;
        for (int i = 1; i < num_beats; i++)
            beat_addr[i] = calc_next_addr(tr, beat_addr[i-1]);

        if (!addr_in_flight) begin
            // Beat 0 address phase (burst starts with NONSEQ)
            @(vif.master_cb);
            drive_addr_phase0(tr);

            // Wait until the address phase is accepted
            do begin
                @(vif.master_cb);
            end while (vif.master_cb.HREADY !== 1'b1);
        end
        // else: beat 0 accepted at the previous txn's last data-phase edge

        // Per beat: drive data[i] + pipelined address phase
        // (BUSY run and/or address[i+1]; IDLE after the last beat)
        for (int i = 0; i < num_beats; i++) begin

            // Write data for beat i
            if (tr.write == AHB_WRITE)
                vif.master_cb.HWDATA <= tr.wdata[i];

            // BUSY count: before beat i+1, or trailing (INCR) after the last beat
            if (i < num_beats - 1)
                n_busy = (i+1 < tr.busy_cycles.size()) ? tr.busy_cycles[i+1] : 0;
            else
                n_busy = tr.trailing_busy_cycles;

            // Pipelined address phase; during BUSY addr/control show the
            // next transfer in the burst
            pipelined_own = 1'b1;
            if (n_busy > 0) begin
                vif.master_cb.HTRANS <= AHB_TRANS_BUSY;
                vif.master_cb.HADDR  <= (i < num_beats - 1)
                                        ? beat_addr[i+1]
                                        : calc_next_addr(tr, beat_addr[i]);
            end else if (i < num_beats - 1) begin
                vif.master_cb.HADDR  <= beat_addr[i+1];
                vif.master_cb.HTRANS <= tr.trans[i+1];
            end else begin
                // Last beat: overlap next txn's beat-0 addr phase, else IDLE.
                // A prefetched NONSEQ is a new burst - never cancelled here
                if (en_back_to_back)
                    prefetch_next();
                if (next_tr != null) begin
                    drive_addr_phase0(next_tr);
                    pipelined_own = 1'b0;
                end else begin
                    vif.master_cb.HTRANS <= AHB_TRANS_IDLE;
                end
            end

            // Wait HREADY; on ERROR cycle 1 cancel the pipelined transfer to
            // IDLE (only own slot, only when aborting)
            forever begin
                @(vif.master_cb);
                if (vif.master_cb.HREADY === 1'b1) break;
                if (vif.master_cb.HRESP === AHB_RESP_ERROR &&
                    tr.abort_on_error && pipelined_own)
                    vif.master_cb.HTRANS <= AHB_TRANS_IDLE;
            end

            // Sample response (valid on the HREADY=1 cycle)
            if (tr.write == AHB_READ)
                tr.rdata[i] = vif.master_cb.HRDATA;
            tr.resp[i] = ahb_resp_e'(vif.master_cb.HRESP);

            `uvm_info(get_type_name(),
                      $sformatf("Beat[%0d/%0d] addr=0x%08h trans=%s resp=%s %s=0x%08h",
                                i, num_beats, beat_addr[i],
                                tr.trans[i].name(),
                                tr.resp[i].name(),
                                (tr.write == AHB_WRITE) ? "wdata" : "rdata",
                                (tr.write == AHB_WRITE) ? tr.wdata[i] : tr.rdata[i]),
                      UVM_HIGH)

            // ERROR: abort=1 -> abandon burst (safety-net IDLE re-drive,
            // own slot only); abort=0 -> continue, both spec-legal
            if (tr.resp[i] == AHB_RESP_ERROR) begin
                if (tr.abort_on_error) begin
                    `uvm_warning(get_type_name(),
                                 $sformatf("ERROR response on beat %0d/%0d%s",
                                           i, num_beats,
                                           (i < num_beats - 1) ? " - cancelling remaining burst" : ""))
                    if (pipelined_own)
                        vif.master_cb.HTRANS <= AHB_TRANS_IDLE;
                    break;
                end
                `uvm_info(get_type_name(),
                          $sformatf("ERROR response on beat %0d/%0d - continuing burst (abort_on_error=0)",
                                    i, num_beats), UVM_MEDIUM)
            end

            // Remaining BUSY cycles (first one accepted with beat i's
            // completion; BUSY gets zero-wait OKAY), then the ending transfer
            if (n_busy > 0) begin
                repeat (n_busy - 1) begin
                    do @(vif.master_cb); while (vif.master_cb.HREADY !== 1'b1);
                end
                if (i < num_beats - 1) begin
                    vif.master_cb.HADDR  <= beat_addr[i+1];
                    vif.master_cb.HTRANS <= tr.trans[i+1];
                end else begin
                    // INCR terminated out of BUSY -> IDLE (no overlap on this path)
                    vif.master_cb.HTRANS <= AHB_TRANS_IDLE;
                end
                do @(vif.master_cb); while (vif.master_cb.HREADY !== 1'b1);
            end
        end

        `uvm_info(get_type_name(),
                  $sformatf("Transaction complete: %s 0x%08h, %0d beats, burst=%s",
                            tr.write.name(), tr.addr, num_beats, tr.burst.name()),
                  UVM_MEDIUM)
    endtask : drive_transaction

    //-------------------------------------------------------------------------
    // Beat-0 address phase: all address & control signals.
    // Used at transaction start and for the back-to-back overlap slot
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
    // Prefetch the next item for back-to-back overlap. item_done() runs one
    // data phase early (sequencer handshake requires it before try_next_item),
    // so the last beat's rdata/resp are not yet valid at finish_item() return.
    // try_next_item() null -> caller drives IDLE
    //-------------------------------------------------------------------------
    task prefetch_next();
        early_done = 1;
        seq_item_port.item_done();
        seq_item_port.try_next_item(next_tr);
    endtask : prefetch_next

    //-------------------------------------------------------------------------
    // Next beat address (beats 1..N-1 only; SINGLE never reaches here)
    //   INCR: addr + 2^HSIZE    WRAP: wraps at num_beats * 2^HSIZE
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
                // Keep upper bits, wrap lower bits
                return (current_addr & ~wrap_mask) | (next_addr & wrap_mask);
            end

            default: return next_addr;
        endcase
    endfunction : calc_next_addr

    //-------------------------------------------------------------------------
    // Reset - deassert all master-driven signals
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
    endtask : reset_signals

endclass : ahb_master_driver