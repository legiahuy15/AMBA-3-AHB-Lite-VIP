//=============================================================================
// File        : ahb_base_seq.sv
// Project     : AMBA 3 AHB-Lite VIP
// Author      : Huy Le
// Description : Base master sequence. Provides the send-and-wait helper that
//               all AHB-Lite master sequences use, plus a write/read-back
//               burst check shared by the burst sequences.
//               This file is `included inside ahb_seq_pkg.sv.
//=============================================================================

`ifndef AHB_BASE_SEQ_INCLUDED_
`define AHB_BASE_SEQ_INCLUDED_

class ahb_base_seq extends uvm_sequence #(ahb_transaction);

    `uvm_object_utils(ahb_base_seq)

    //-------------------------------------------------------------------------
    // Beat-level statistics, accumulated by write_read_burst()
    //-------------------------------------------------------------------------
    int unsigned beats_checked;
    int unsigned beats_mismatch;

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(string name = "ahb_base_seq");
        super.new(name);
    endfunction : new

    //-------------------------------------------------------------------------
    // send_and_wait - send one item and block until the bus transfer finishes.
    // The driver is pipelined, so finish_item() returns before the transfer
    // completes; rdata[]/resp[] are valid only after tr.done.
    // ok = 0 when a reset flushed the item
    //-------------------------------------------------------------------------
    virtual task send_and_wait(ahb_transaction tr, output bit ok);
        start_item(tr);
        // Arm before the item reaches the driver
        tr.done    = 1'b0;
        tr.aborted = 1'b0;
        finish_item(tr);
        // Level-sensitive: returns immediately if the driver already completed
        wait (tr.done);
        ok = !tr.aborted;
        if (!ok)
            `uvm_warning(get_type_name(),
                         $sformatf("Transaction aborted by reset: %s 0x%08h",
                                   tr.write.name(), tr.addr))
    endtask : send_and_wait

    //-------------------------------------------------------------------------
    // beat_address - address of beat i, honouring INCR increment and WRAP.
    // Mirrors the scoreboard so both agree on where a beat landed
    //-------------------------------------------------------------------------
    function bit [AHB_ADDR_WIDTH-1:0] beat_address(ahb_transaction tr, int i);
        int unsigned bytes = 1 << tr.size;
        int unsigned len   = tr.get_num_beats();
        int unsigned wrap_bytes;
        bit [AHB_ADDR_WIDTH-1:0] base;

        case (tr.burst)
            AHB_BURST_WRAP4, AHB_BURST_WRAP8, AHB_BURST_WRAP16: begin
                wrap_bytes = len * bytes;
                base       = tr.addr - (tr.addr % wrap_bytes);
                return base + ((tr.addr + i * bytes) % wrap_bytes);
            end
            default: return tr.addr + i * bytes;
        endcase
    endfunction : beat_address

    //-------------------------------------------------------------------------
    // write_read_burst - send an already randomized write burst, then read the
    // same address with identical control and compare every beat.
    // Only the active byte lanes are compared: a narrow transfer leaves the
    // remaining lanes undefined, so a full-word compare would be wrong
    //-------------------------------------------------------------------------
    virtual task write_read_burst(ahb_transaction wr);
        ahb_transaction          rd;
        bit                      ok;
        bit [AHB_ADDR_WIDTH-1:0] a;
        int unsigned             bytes;
        int unsigned             lane;
        bit [7:0]                exp_b, got_b;
        bit                      beat_bad;

        send_and_wait(wr, ok);
        if (!ok) return;                    // reset flush - skip the pair

        rd = ahb_transaction::type_id::create("rd");
        if (!rd.randomize() with {
                write     == AHB_READ;
                burst     == wr.burst;
                size      == wr.size;
                addr      == wr.addr;
                num_beats == wr.num_beats;
            })
            `uvm_fatal(get_type_name(),
                       $sformatf("Read randomization failed (%s @0x%08h)",
                                 wr.burst.name(), wr.addr))

        send_and_wait(rd, ok);
        if (!ok) return;

        bytes = 1 << wr.size;
        foreach (rd.rdata[k]) begin
            a        = beat_address(rd, k);
            lane     = a % (AHB_DATA_WIDTH / 8);
            beat_bad = 0;
            beats_checked++;

            // Nothing here asks for an ERROR, so any non-OKAY is a failure
            if (wr.resp[k] != AHB_RESP_OKAY || rd.resp[k] != AHB_RESP_OKAY) begin
                beats_mismatch++;
                `uvm_error(get_type_name(),
                           $sformatf("%s %s beat %0d @0x%08h: unexpected response (wr=%s rd=%s)",
                                     wr.burst.name(), wr.size.name(), k, a,
                                     wr.resp[k].name(), rd.resp[k].name()))
                continue;
            end

            for (int b = 0; b < bytes; b++) begin
                exp_b = wr.wdata[k][(lane + b)*8 +: 8];
                got_b = rd.rdata[k][(lane + b)*8 +: 8];
                if (got_b !== exp_b) begin
                    beat_bad = 1;
                    `uvm_error(get_type_name(),
                               $sformatf("%s %s beat %0d @0x%08h byte %0d: wrote 0x%02h, read 0x%02h",
                                         wr.burst.name(), wr.size.name(), k, a, b, exp_b, got_b))
                end
            end

            if (beat_bad) begin
                beats_mismatch++;
            end else begin
                `uvm_info(get_type_name(),
                          $sformatf("%s %s beat %0d @0x%08h ok",
                                    wr.burst.name(), wr.size.name(), k, a), UVM_HIGH)
            end
        end
    endtask : write_read_burst

endclass : ahb_base_seq

`endif // AHB_BASE_SEQ_INCLUDED_