//=============================================================================
// File        : ahb_size_seq.sv
// Project     : AMBA 3 AHB-Lite VIP
// Author      : Huy Le
// Description : Transfer-size sweep. Walks HSIZE over every encoding legal on
//               the data bus, each one at every alignment it allows, and issues
//               them as SINGLE and as multi-beat bursts so HSIZE also has to
//               hold constant for a whole burst. A negative check confirms the
//               transaction constraints reject any HSIZE wider than the bus.
//               Requires the slave agent in auto-response mode (memory model).
//               This file is `included inside ahb_seq_pkg.sv.
//=============================================================================

`ifndef AHB_SIZE_SEQ_INCLUDED_
`define AHB_SIZE_SEQ_INCLUDED_

class ahb_size_seq extends ahb_base_seq;

    `uvm_object_utils(ahb_size_seq)

    //-------------------------------------------------------------------------
    // Knobs
    //-------------------------------------------------------------------------
    int unsigned num_iter = 24;

    bit [AHB_ADDR_WIDTH-1:0] base_addr = 32'h0000_6000;

    // Negative check on the illegal HSIZE encodings, run once before the sweep
    bit chk_illegal_size = 1'b1;

    // One slot per iteration, holding the widest burst issued here (8 beats x
    // 4 bytes) plus the largest start offset (3 bytes) - 35 of 64 bytes. Slots
    // are never reused, so transfers of different sizes cannot alias in the
    // scoreboard reference memory, and a 64-byte stride keeps every burst clear
    // of a 1KB boundary
    localparam int unsigned SLOT_SIZE = 64;

    localparam int unsigned BUS_BYTES = AHB_DATA_WIDTH / 8;

    // Sweep periods: 3 sizes and 4 burst types are coprime with the 4-lane
    // offset walk, so 12 iterations cover every size/burst pair and every
    // size/alignment pair
    localparam int unsigned NUM_SIZE  = 3;
    localparam int unsigned NUM_BURST = 4;

    //-------------------------------------------------------------------------
    // Statistics
    //-------------------------------------------------------------------------
    int unsigned iter_per_size[NUM_SIZE];    // bursts issued at each HSIZE
    int unsigned iter_per_lane[BUS_BYTES];   // bursts starting on each byte lane
    int unsigned num_illegal_rejected;       // wide HSIZE encodings refused

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(string name = "ahb_size_seq");
        super.new(name);
    endfunction : new

    //-------------------------------------------------------------------------
    // Sweep tables - HSIZE encodings legal on a 32-bit bus, and the burst
    // types they are issued with. The multi-beat entries are what exercise
    // "HSIZE constant for the whole burst" (AHB_SIZ_006)
    //-------------------------------------------------------------------------
    function ahb_size_e get_size(int unsigned idx);
        case (idx % NUM_SIZE)
            0:       return AHB_SIZE_8B;
            1:       return AHB_SIZE_16B;
            default: return AHB_SIZE_32B;
        endcase
    endfunction : get_size

    function ahb_burst_e get_burst(int unsigned idx);
        case (idx % NUM_BURST)
            0:       return AHB_BURST_SINGLE;
            1:       return AHB_BURST_INCR4;
            2:       return AHB_BURST_WRAP4;
            default: return AHB_BURST_INCR8;
        endcase
    endfunction : get_burst

    //-------------------------------------------------------------------------
    // Body - num_iter x (write burst, read-back, compare) over the sweep
    //-------------------------------------------------------------------------
    virtual task body();
        ahb_transaction          wr;
        bit [AHB_ADDR_WIDTH-1:0] slot;
        ahb_size_e               sz;
        ahb_burst_e              bt;
        int unsigned             bytes;
        int unsigned             offset;

        `uvm_info(get_type_name(),
                  $sformatf("Starting transfer-size sweep: %0d iterations from 0x%08h",
                            num_iter, base_addr), UVM_LOW)

        if (chk_illegal_size) check_illegal_sizes();

        for (int unsigned i = 0; i < num_iter; i++) begin
            slot  = base_addr + i * SLOT_SIZE;
            sz    = get_size(i);                // period 3
            bt    = get_burst(i / NUM_SIZE);    // period 12 - all size/burst pairs
            bytes = 1 << sz;

            // Every alignment the size allows: the raw offset walks all four
            // byte lanes and is rounded down to the size boundary, so a byte
            // transfer starts on lanes 0-3, a halfword on lanes 0 and 2, and a
            // word only on lane 0 (AHB_SIZ_005)
            offset = (i % BUS_BYTES) & ~(bytes - 1);

            wr = ahb_transaction::type_id::create("wr");
            if (!wr.randomize() with {
                    write == AHB_WRITE;
                    burst == bt;
                    size  == sz;
                    addr  == slot + offset;
                })
                `uvm_fatal(get_type_name(),
                           $sformatf("Write randomization failed (%s %s @0x%08h)",
                                     bt.name(), sz.name(), slot + offset))

            iter_per_size[i % NUM_SIZE]++;
            iter_per_lane[offset]++;

            `uvm_info(get_type_name(),
                      $sformatf("%s %s @0x%08h (lane %0d), %0d beats",
                                bt.name(), sz.name(), wr.addr, offset,
                                wr.get_num_beats()), UVM_MEDIUM)

            write_read_burst(wr);
        end

        report_sweep();
    endtask : body

    //-------------------------------------------------------------------------
    // AHB_SIZ_004 - 2^HSIZE must never exceed the width of the data bus. The
    // transaction constraint owns that rule (c_size_max), so the check is
    // negative: every wider encoding must leave the solver with no solution.
    // The simulator prints its own "no solution" note per attempt - those are
    // the expected result, not a failure
    //-------------------------------------------------------------------------
    protected function void check_illegal_sizes();
        ahb_transaction tr;
        ahb_size_e      sz;
        int unsigned    num_attempted;

        tr = ahb_transaction::type_id::create("size_probe");

        for (int unsigned s = 0; s < 8; s++) begin
            sz = ahb_size_e'(s);
            if ((1 << s) <= BUS_BYTES) continue;    // legal on this bus width

            num_attempted++;
            if (tr.randomize() with { size == sz; })
                `uvm_error(get_type_name(),
                           $sformatf("%s (%0d bytes) accepted on a %0d-bit bus - c_size_max did not reject it",
                                     sz.name(), 1 << s, AHB_DATA_WIDTH))
            else
                num_illegal_rejected++;
        end

        `uvm_info(get_type_name(),
                  $sformatf("Illegal HSIZE check: %0d of %0d wide encodings rejected on a %0d-bit bus",
                            num_illegal_rejected, num_attempted, AHB_DATA_WIDTH),
                  UVM_LOW)
    endfunction : check_illegal_sizes

    //-------------------------------------------------------------------------
    // End-of-sequence tally. A size or a lane that never came up means the
    // sweep was cut short - the run proves less than the test claims
    //-------------------------------------------------------------------------
    protected function void report_sweep();
        ahb_size_e sz;

        `uvm_info(get_type_name(),
                  $sformatf("Transfer-size sweep done: beats=%0d mismatch=%0d",
                            beats_checked, beats_mismatch),
                  (beats_mismatch == 0) ? UVM_LOW : UVM_NONE)

        foreach (iter_per_size[s]) begin
            sz = get_size(s);
            `uvm_info(get_type_name(),
                      $sformatf("  %s -> %0d bursts", sz.name(),
                                iter_per_size[s]), UVM_MEDIUM)
            if (iter_per_size[s] == 0)
                `uvm_warning(get_type_name(),
                             $sformatf("%s never issued - raise +NUM_ITER (%0d needed for a full sweep)",
                                       sz.name(), NUM_SIZE * NUM_BURST))
        end

        foreach (iter_per_lane[l]) begin
            `uvm_info(get_type_name(),
                      $sformatf("  start lane %0d -> %0d bursts", l,
                                iter_per_lane[l]), UVM_MEDIUM)
            if (iter_per_lane[l] == 0)
                `uvm_warning(get_type_name(),
                             $sformatf("lane %0d never used as a start address - raise +NUM_ITER (%0d needed for a full sweep)",
                                       l, NUM_SIZE * NUM_BURST))
        end
    endfunction : report_sweep

endclass : ahb_size_seq

`endif // AHB_SIZE_SEQ_INCLUDED_
