//=============================================================================
// File        : ahb_incr_burst_seq.sv
// Project     : AMBA 3 AHB-Lite VIP
// Author      : Huy Le
// Description : Fixed-length incrementing bursts (INCR4, INCR8, INCR16) over
//               every legal size. Each iteration writes one burst and reads it
//               back beat for beat at the same address.
//               Requires the slave agent in auto-response mode (memory model).
//               This file is `included inside ahb_seq_pkg.sv.
//=============================================================================

`ifndef AHB_INCR_BURST_SEQ_INCLUDED_
`define AHB_INCR_BURST_SEQ_INCLUDED_

class ahb_incr_burst_seq extends ahb_base_seq;

    `uvm_object_utils(ahb_incr_burst_seq)

    //-------------------------------------------------------------------------
    // Knobs
    //-------------------------------------------------------------------------
    int unsigned num_iter = 16;

    // 1KB aligned: with a 64-byte slot the 16th iteration of every page ends
    // flush against the 1KB boundary, which is where INCR_1KB_BOUNDARY bites
    bit [AHB_ADDR_WIDTH-1:0] base_addr = 32'h0000_3000;

    // Slot holds the largest burst this sequence issues (16 beats x 4 bytes).
    // The burst is placed at a random aligned offset but always fits inside,
    // so slots never alias in the scoreboard reference memory and no burst can
    // cross a 1KB boundary
    localparam int unsigned SLOT_SIZE = 64;

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(string name = "ahb_incr_burst_seq");
        super.new(name);
    endfunction : new

    //-------------------------------------------------------------------------
    // Body - num_iter x (INCR write burst, INCR read burst, compare)
    //-------------------------------------------------------------------------
    virtual task body();
        ahb_transaction          wr;
        bit [AHB_ADDR_WIDTH-1:0] slot;

        `uvm_info(get_type_name(),
                  $sformatf("Starting INCR bursts: %0d iterations from 0x%08h",
                            num_iter, base_addr), UVM_LOW)

        for (int unsigned i = 0; i < num_iter; i++) begin
            slot = base_addr + i * SLOT_SIZE;

            wr = ahb_transaction::type_id::create("wr");
            if (!wr.randomize() with {
                    write == AHB_WRITE;
                    burst inside {AHB_BURST_INCR4, AHB_BURST_INCR8, AHB_BURST_INCR16};
                    size inside {AHB_SIZE_8B, AHB_SIZE_16B, AHB_SIZE_32B};
                    addr >= slot;
                    addr + num_beats * (1 << size) <= slot + SLOT_SIZE;
                })
                `uvm_fatal(get_type_name(),
                           $sformatf("Write randomization failed @slot 0x%08h", slot))

            write_read_burst(wr);
        end

        `uvm_info(get_type_name(),
                  $sformatf("INCR bursts done: beats=%0d mismatch=%0d",
                            beats_checked, beats_mismatch),
                  (beats_mismatch == 0) ? UVM_LOW : UVM_NONE)
    endtask : body

endclass : ahb_incr_burst_seq

`endif // AHB_INCR_BURST_SEQ_INCLUDED_
