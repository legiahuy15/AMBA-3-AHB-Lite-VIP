//=============================================================================
// File        : ahb_master_driver.sv
// Project     : AMBA 3 AHB-Lite VIP
// Author      : Huy Le
// Description : AHB-Lite master driver.
//               Receives transactions from the sequencer and drives them
//               onto the AHB-Lite bus via the master clocking block.
//               Address phase: drive HADDR, HBURST, HSIZE, HTRANS, HWRITE
//               Data phase   : drive HWDATA (write) / sample HRDATA (read)
//               HREADY=0 extends both phases (wait states from slave)
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
    // Drive transaction — drive a complete burst onto the bus
    //
    // AHB-Lite uses pipelined address/data phases:
    //   Beat 0: Address phase on clk N, data phase on clk N+1
    //   Beat 1: Address phase on clk N+1 (overlaps beat 0 data), etc.
    //
    // For simplicity and correctness in a VIP without DUT pipeline,
    // we use a non-pipelined approach: each beat does address then data
    // sequentially. This is spec-compliant (slave sees correct timing).
    //-------------------------------------------------------------------------
    task drive_transaction(ahb_transaction tr);
        int num_beats;
        bit [AHB_ADDR_WIDTH-1:0] beat_addr;

        num_beats = tr.get_num_beats();
        beat_addr = tr.addr;

        for (int i = 0; i < num_beats; i++) begin

            //-----------------------------------------------------------------
            // Address phase: drive control signals, wait for HREADY
            //-----------------------------------------------------------------
            @(vif.master_cb);
            vif.master_cb.HADDR     <= beat_addr;
            vif.master_cb.HBURST    <= tr.burst;
            vif.master_cb.HMASTLOCK <= tr.lock;
            vif.master_cb.HPROT     <= tr.prot;
            vif.master_cb.HSIZE     <= tr.size;
            vif.master_cb.HTRANS    <= (i < tr.trans.size()) ? tr.trans[i] : AHB_TRANS_SEQ;
            vif.master_cb.HWRITE    <= tr.write;

            // Wait for slave to accept address phase (HREADY == 1)
            do begin
                @(vif.master_cb);
            end while (vif.master_cb.HREADY !== 1'b1);

            //-----------------------------------------------------------------
            // Data phase: drive HWDATA (write) or sample HRDATA (read)
            //-----------------------------------------------------------------
            if (tr.write == AHB_WRITE) begin
                vif.master_cb.HWDATA <= (i < tr.wdata.size()) ? tr.wdata[i] : '0;
            end

            // Wait for slave to complete data phase (HREADY == 1)
            do begin
                @(vif.master_cb);
            end while (vif.master_cb.HREADY !== 1'b1);

            // Sample read data and response from slave
            if (tr.write == AHB_READ) begin
                if (i < tr.rdata.size())
                    tr.rdata[i] = vif.master_cb.HRDATA;
                else begin
                    tr.rdata = new[i+1](tr.rdata);
                    tr.rdata[i] = vif.master_cb.HRDATA;
                end
            end

            // Sample response
            if (i < tr.resp.size())
                tr.resp[i] = ahb_resp_e'(vif.master_cb.HRESP);
            else begin
                tr.resp = new[i+1](tr.resp);
                tr.resp[i] = ahb_resp_e'(vif.master_cb.HRESP);
            end

            // Log beat completion
            `uvm_info(get_type_name(),
                      $sformatf("Beat[%0d/%0d] addr=0x%08h trans=%s resp=%s %s=0x%08h",
                                i, num_beats, beat_addr,
                                ((i < tr.trans.size()) ? tr.trans[i].name() : "SEQ"),
                                tr.resp[i].name(),
                                (tr.write == AHB_WRITE) ? "wdata" : "rdata",
                                (tr.write == AHB_WRITE) ?
                                    ((i < tr.wdata.size()) ? tr.wdata[i] : '0) :
                                    tr.rdata[i]),
                      UVM_HIGH)

            //-----------------------------------------------------------------
            // Calculate next beat address
            //-----------------------------------------------------------------
            beat_addr = calc_next_addr(tr, beat_addr, i);

        end // for each beat

        // Drive IDLE after burst completes
        @(vif.master_cb);
        vif.master_cb.HTRANS <= AHB_TRANS_IDLE;

        `uvm_info(get_type_name(),
                  $sformatf("Transaction complete: %s 0x%08h, %0d beats, burst=%s",
                            tr.write.name(), tr.addr, num_beats, tr.burst.name()),
                  UVM_MEDIUM)
    endtask : drive_transaction

    //-------------------------------------------------------------------------
    // Calculate next beat address
    //   INCR bursts:  addr += 2^HSIZE (incrementing, no wrap)
    //   WRAP bursts:  addr wraps at boundary = num_beats * 2^HSIZE
    //   SINGLE:       no next address needed
    //-------------------------------------------------------------------------
    function bit [AHB_ADDR_WIDTH-1:0] calc_next_addr(
        ahb_transaction tr,
        bit [AHB_ADDR_WIDTH-1:0] current_addr,
        int beat_idx
    );
        int unsigned bytes_per_beat;
        int unsigned wrap_boundary;
        bit [AHB_ADDR_WIDTH-1:0] next_addr;

        bytes_per_beat = 1 << tr.size;
        next_addr = current_addr + bytes_per_beat;

        case (tr.burst)
            AHB_BURST_SINGLE: begin
                return current_addr;    // No increment for single
            end

            AHB_BURST_INCR,
            AHB_BURST_INCR4,
            AHB_BURST_INCR8,
            AHB_BURST_INCR16: begin
                return next_addr;       // Simple increment
            end

            AHB_BURST_WRAP4,
            AHB_BURST_WRAP8,
            AHB_BURST_WRAP16: begin
                // Wrap boundary = num_beats * bytes_per_beat
                wrap_boundary = tr.get_num_beats() * bytes_per_beat;
                // If next_addr crosses the wrap boundary, wrap around
                if ((next_addr % wrap_boundary) == 0)
                    next_addr = next_addr - wrap_boundary;
                return next_addr;
            end

            default: return next_addr;
        endcase
    endfunction : calc_next_addr

    //------------------------------------------------------------------------
    // Reset — deassert all master-driven signals
    //------------------------------------------------------------------------
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