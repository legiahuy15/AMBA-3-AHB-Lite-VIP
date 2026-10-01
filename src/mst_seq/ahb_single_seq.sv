//=============================================================================
// File        : ahb_single_seq.sv
// Project     : AMBA 3 AHB-Lite VIP
// Author      : Huy Le
// Description : Random SINGLE write/read-back, all legal sizes and alignments.
//               Requires auto-response slave.
//=============================================================================

`ifndef AHB_SINGLE_SEQ_INCLUDED_
`define AHB_SINGLE_SEQ_INCLUDED_

class ahb_single_seq extends ahb_base_seq;

    `uvm_object_utils(ahb_single_seq)

    //-------------------------------------------------------------------------
    // Knobs
    //-------------------------------------------------------------------------
    int unsigned num_iter = 20;

    bit [AHB_ADDR_WIDTH-1:0] base_addr = 32'h0000_2000;

    // One word per iteration, random aligned offset
    localparam int unsigned SLOT_SIZE = 4;

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(string name = "ahb_single_seq");
        super.new(name);
    endfunction : new

    //-------------------------------------------------------------------------
    // Body - num_iter x (SINGLE write, SINGLE read-back, compare)
    //-------------------------------------------------------------------------
    virtual task body();
        ahb_transaction          wr;
        bit [AHB_ADDR_WIDTH-1:0] slot;

        `uvm_info(get_type_name(),
                  $sformatf("Starting SINGLE transfers: %0d iterations from 0x%08h",
                            num_iter, base_addr), UVM_LOW)

        for (int unsigned i = 0; i < num_iter; i++) begin
            slot = base_addr + i * SLOT_SIZE;

            wr = ahb_transaction::type_id::create("wr");
            if (!wr.randomize() with {
                    write == AHB_WRITE;
                    burst == AHB_BURST_SINGLE;
                    size inside {AHB_SIZE_8B, AHB_SIZE_16B, AHB_SIZE_32B};
                    addr inside {[slot : slot + SLOT_SIZE - 1]};
                })
                `uvm_fatal(get_type_name(),
                           $sformatf("Write randomization failed @slot 0x%08h", slot))

            write_read_burst(wr);
        end

        `uvm_info(get_type_name(),
                  $sformatf("SINGLE transfers done: beats=%0d mismatch=%0d",
                            beats_checked, beats_mismatch),
                  (beats_mismatch == 0) ? UVM_LOW : UVM_NONE)
    endtask : body

endclass : ahb_single_seq

`endif // AHB_SINGLE_SEQ_INCLUDED_