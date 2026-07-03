//=============================================================================
// File        : ahb_master_driver.sv
// Project     : AMBA 3 AHB-Lite VIP
// Author      : Huy Le
// Description : AHB-Lite master driver.
//               Receives transactions from the sequencer and drives them
//               onto the AHB-Lite bus via the master clocking block.
//               Implements pipelined address/data phases per IHI0033A:
//                 Address phase of beat N+1 overlaps data phase of beat N.
//                 HREADY=1 completes both phases simultaneously.
//               This file is `included inside ahb_pkg.sv.
//=============================================================================

class ahb_master_driver extends uvm_driver #(ahb_transaction);

    `uvm_component_utils(ahb_master_driver)

    // Virtual interface handle
    virtual ahb_if vif;

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
        super.build_phase(phase);
        if(!uvm_config_db#(virtual ahb_if)::get(this, "", "vif", vif))
            `uvm_fatal(get_type_name(), "Virtual interface not found in config_db")
    endfunction: build_phase

    //-------------------------------------------------------------------------
    // Run phase - main driver loop
    //-------------------------------------------------------------------------
    virtual task run_phase(uvm_phase phase);
        forever begin
            reset_signals();
            @(posedge vif.rst_n);
            `uvm_info(get_type_name(), "Reset deasserted - master driver active", UVM_MEDIUM)

            fork
                begin : drive_loop
                    forever begin
                        ahb_transaction tr;
                        seq_item_port.get_next_item(tr);
                        `uvm_info(get_type_name(),
                                  $sformatf("Driving [%s]: HADDR=0x%08h, HBURST=%s, HSIZE=%s, %0d beats",
                                             tr.write.name(), tr.addr, tr.burst.name(),
                                             tr.size.name(), tr.get_num_beats()), UVM_MEDIUM)
                        drive_transaction(tr);
                        seq_item_port.item_done();
                    end
                end
                begin : rst_watch
                    @(negedge vif.rst_n);
                    `uvm_info(get_type_name(), "Reset asserted - aborting", UVM_MEDIUM)
                end
            join_any
            disable fork;
        end
    endtask : run_phase

    //-------------------------------------------------------------------------
    // Drive transaction — pipelined address/data phases per IHI0033A
    //
    //   The address phase of beat N+1 overlaps the data phase of beat N.
    //   When HREADY=1 at a clock edge:
    //     - Data phase of the current beat completes
    //     - Address phase of the current beat is accepted
    //
    //   Timing for 4-beat WRITE (no wait states):
    //     T1: Drive A0, NONSEQ
    //     T2: HREADY=1 → A0 accepted. Drive A1, SEQ, D0
    //     T3: HREADY=1 → D0 done, A1 accepted. Drive A2, SEQ, D1
    //     T4: HREADY=1 → D1 done, A2 accepted. Drive A3, SEQ, D2
    //     T5: HREADY=1 → D2 done, A3 accepted. Drive IDLE, D3
    //     T6: HREADY=1 → D3 done. Complete.
    //-------------------------------------------------------------------------
    task drive_transaction(ahb_transaction tr);
        int num_beats;
        bit [AHB_ADDR_WIDTH-1:0] beat_addr[];

        num_beats = tr.get_num_beats();

        // Pre-calculate all beat addresses
        beat_addr = new[num_beats];
        beat_addr[0] = tr.addr;
        for (int i = 1; i < num_beats; i++)
            beat_addr[i] = calc_next_addr(tr, beat_addr[i-1]);

        //-----------------------------------------------------------------
        // Initial address phase (beat 0) — no data yet
        //-----------------------------------------------------------------
        @(vif.master_cb);
        vif.master_cb.HADDR     <= beat_addr[0];
        vif.master_cb.HBURST    <= tr.burst;
        vif.master_cb.HMASTLOCK <= tr.lock;
        vif.master_cb.HPROT     <= tr.prot;
        vif.master_cb.HSIZE     <= tr.size;
        vif.master_cb.HTRANS    <= tr.trans[0];
        vif.master_cb.HWRITE    <= tr.write;

        // Wait for address phase to be accepted
        do begin
            @(vif.master_cb);
        end while (vif.master_cb.HREADY !== 1'b1);

        //-----------------------------------------------------------------
        // Pipelined data[i] + address[i+1] phases
        //-----------------------------------------------------------------
        for (int i = 0; i < num_beats; i++) begin

            // Drive write data for beat i
            if (tr.write == AHB_WRITE)
                vif.master_cb.HWDATA <= tr.wdata[i];

            // Drive address for next beat, or IDLE after last beat
            if (i < num_beats - 1) begin
                vif.master_cb.HADDR  <= beat_addr[i+1];
                vif.master_cb.HTRANS <= tr.trans[i+1];
            end else begin
                vif.master_cb.HTRANS <= AHB_TRANS_IDLE;
            end

            // Wait for data phase to complete (HREADY=1)
            do begin
                @(vif.master_cb);
            end while (vif.master_cb.HREADY !== 1'b1);

            // Sample slave response
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
        end

        `uvm_info(get_type_name(),
                  $sformatf("Transaction complete: %s 0x%08h, %0d beats, burst=%s",
                            tr.write.name(), tr.addr, num_beats, tr.burst.name()),
                  UVM_MEDIUM)
    endtask : drive_transaction

    //-------------------------------------------------------------------------
    // Calculate next beat address per IHI0033A
    //   INCR:   addr += 2^HSIZE
    //   WRAP:   addr wraps at boundary = num_beats * 2^HSIZE
    //   SINGLE: no increment
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
            AHB_BURST_SINGLE: begin
                return current_addr;
            end

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
    // Reset — deassert all master-driven signals
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