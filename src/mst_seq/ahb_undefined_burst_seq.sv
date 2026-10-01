//=============================================================================
// File        : ahb_undefined_burst_seq.sv
// Project     : AMBA 3 AHB-Lite VIP
// Author      : Huy Le
// Description : Undefined-length INCR bursts (1-256 beats) with mid-burst BUSY
//               and, on every other burst, trailing BUSY.
//               Requires auto-response slave.
//=============================================================================

`ifndef AHB_UNDEFINED_BURST_SEQ_INCLUDED_
`define AHB_UNDEFINED_BURST_SEQ_INCLUDED_

class ahb_undefined_burst_seq extends ahb_base_seq;

    `uvm_object_utils(ahb_undefined_burst_seq)

    //-------------------------------------------------------------------------
    // Knobs
    //-------------------------------------------------------------------------
    int unsigned num_iter = 8;

    bit [AHB_ADDR_WIDTH-1:0] base_addr = 32'h0000_5000;

    // 1KB slot (256 x 4B), 1KB aligned
    localparam int unsigned SLOT_SIZE = 1024;

    // BUSY before every Nth beat
    localparam int unsigned BUSY_EVERY = 8;

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(string name = "ahb_undefined_burst_seq");
        super.new(name);
    endfunction : new

    //-------------------------------------------------------------------------
    // Body - num_iter x (write, read back, compare)
    //-------------------------------------------------------------------------
    virtual task body();
        ahb_transaction          wr;
        bit [AHB_ADDR_WIDTH-1:0] slot;
        int unsigned             pin_beats;
        bit                      want_trailing;
        bit                      want_retract;
        bit                      want_pipeline;
        bit                      pipe_toggle;

        `uvm_info(get_type_name(),
                  $sformatf("Starting undefined-length INCR bursts: %0d iterations from 0x%08h",
                            num_iter, base_addr), UVM_LOW)

        for (int unsigned i = 0; i < num_iter; i++) begin
            slot = base_addr + i * SLOT_SIZE;

            // First two bursts: 1 and 256 beats
            case (i)
                0:       pin_beats = 1;
                1:       pin_beats = 256;
                default: pin_beats = 0;     // free length
            endcase

            // Trailing BUSY on odd bursts
            want_trailing = ((i % 2) == 1);

            // Period 4: all trailing/retract combinations
            want_retract = (((i / 2) % 2) == 1);

            // Trailing BUSY + retract: alternate pipelined (BUSY->NONSEQ)
            // and not pipelined (BUSY->IDLE)
            want_pipeline = 1'b0;
            if (want_trailing && want_retract) begin
                want_pipeline = pipe_toggle;
                pipe_toggle   = !pipe_toggle;
            end

            wr = ahb_transaction::type_id::create("wr");
            if (!wr.randomize() with {
                    write == AHB_WRITE;
                    burst == AHB_BURST_INCR;
                    size inside {AHB_SIZE_8B, AHB_SIZE_16B, AHB_SIZE_32B};

                    (pin_beats != 0) -> (num_beats == pin_beats);
                    (pin_beats == 0) -> (num_beats inside {[2:64]});

                    // Burst stays inside its slot
                    addr inside {[slot : slot + SLOT_SIZE - 1]};
                    addr + num_beats * (1 << size) <= slot + SLOT_SIZE;

                    foreach (busy_cycles[k]) {
                        if (k > 0 && (k % BUSY_EVERY) == 0) busy_cycles[k] inside {[1:2]};
                        else                                busy_cycles[k] == 0;
                    }
                    want_trailing  -> (trailing_busy_cycles inside {[1:3]});
                    !want_trailing -> (trailing_busy_cycles == 0);

                    busy_retract_in_wait == want_retract;
                })
                `uvm_fatal(get_type_name(),
                           $sformatf("Write randomization failed @slot 0x%08h", slot))

            `uvm_info(get_type_name(),
                      $sformatf("INCR %0d beats, %s @0x%08h, trailing_busy=%0d, retract=%0b, pipelined=%0b",
                                wr.num_beats, wr.size.name(), wr.addr,
                                wr.trailing_busy_cycles, wr.busy_retract_in_wait,
                                want_pipeline),
                      UVM_MEDIUM)

            write_read_burst(wr, want_pipeline);
        end

        `uvm_info(get_type_name(),
                  $sformatf("Undefined-length INCR bursts done: beats=%0d mismatch=%0d",
                            beats_checked, beats_mismatch),
                  (beats_mismatch == 0) ? UVM_LOW : UVM_NONE)
    endtask : body

endclass : ahb_undefined_burst_seq

`endif // AHB_UNDEFINED_BURST_SEQ_INCLUDED_
