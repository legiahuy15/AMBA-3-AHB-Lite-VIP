//=============================================================================
// File        : ahb_incr_burst_seq.sv
// Project     : AMBA 3 AHB-Lite VIP
// Author      : Huy Le
// Description : INCR4/8/16 write/read-back bursts, all legal sizes.
//               Requires auto-response slave.
//=============================================================================

`ifndef AHB_INCR_BURST_SEQ_INCLUDED_
`define AHB_INCR_BURST_SEQ_INCLUDED_

class ahb_incr_burst_seq extends ahb_base_seq;

    `uvm_object_utils(ahb_incr_burst_seq)

    //-------------------------------------------------------------------------
    // Knobs
    //-------------------------------------------------------------------------
    int unsigned num_iter = 16;

    // 1KB aligned (every 16th slot starts a 1KB page)
    bit [AHB_ADDR_WIDTH-1:0] base_addr = 32'h0000_3000;

    // Address slot per burst: largest burst (16 x 4B)
    localparam int unsigned SLOT_SIZE = 64;

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(string name = "ahb_incr_burst_seq");
        super.new(name);
    endfunction : new

    //-------------------------------------------------------------------------
    // Body - num_iter x (write, read back, compare)
    //-------------------------------------------------------------------------
    virtual task body();
        ahb_transaction          wr;
        bit [AHB_ADDR_WIDTH-1:0] slot;
        bit                      pin_top;

        `uvm_info(get_type_name(),
                  $sformatf("Starting INCR bursts: %0d iterations from 0x%08h",
                            num_iter, base_addr), UVM_LOW)

        for (int unsigned i = 0; i < num_iter; i++) begin
            slot = base_addr + i * SLOT_SIZE;

            // Every 4th burst ends at the top of its slot, which includes the
            // last bytes before each 1KB boundary (INCR_1KB_BOUNDARY)
            pin_top = ((i % 4) == 3);

            wr = ahb_transaction::type_id::create("wr");
            if (!wr.randomize() with {
                    write == AHB_WRITE;
                    burst inside {AHB_BURST_INCR4, AHB_BURST_INCR8, AHB_BURST_INCR16};
                    size inside {AHB_SIZE_8B, AHB_SIZE_16B, AHB_SIZE_32B};
                    // Burst stays inside its slot
                    addr inside {[slot : slot + SLOT_SIZE - 1]};
                    addr + num_beats * (1 << size) <= slot + SLOT_SIZE;
                    pin_top -> (addr + num_beats * (1 << size) == slot + SLOT_SIZE);
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