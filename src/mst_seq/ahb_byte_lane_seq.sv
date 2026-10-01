//=============================================================================
// File        : ahb_byte_lane_seq.sv
// Project     : AMBA 3 AHB-Lite VIP
// Author      : Huy Le
// Description : Byte-lane walk for narrow transfers (little endian, IHI0033A
//               6.1.3). Active lanes carry an address-derived pattern, inactive
//               lanes its inverse. Only active lanes are compared. Lane order
//               is randomized. Requires auto-response slave.
//=============================================================================

`ifndef AHB_BYTE_LANE_SEQ_INCLUDED_
`define AHB_BYTE_LANE_SEQ_INCLUDED_

class ahb_byte_lane_seq extends ahb_base_seq;

    `uvm_object_utils(ahb_byte_lane_seq)

    //-------------------------------------------------------------------------
    // Knobs
    //-------------------------------------------------------------------------
    // Size rotates per iteration: >= NUM_SIZE for a full walk
    int unsigned num_iter = 12;

    bit [AHB_ADDR_WIDTH-1:0] base_addr = 32'h0000_E000;

    localparam int unsigned BUS_BYTES = AHB_DATA_WIDTH / 8;

    // Slot layout: SINGLE walk in the first word, INCR4 from BURST_OFFS.
    // One size per slot
    localparam int unsigned SLOT_SIZE  = 32;
    localparam int unsigned BURST_OFFS = 16;

    localparam int unsigned NUM_SIZE = 3;

    //-------------------------------------------------------------------------
    // Statistics
    //-------------------------------------------------------------------------
    int unsigned lane_hits[BUS_BYTES];   // beats per start lane
    int unsigned num_singles;
    int unsigned num_bursts;

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(string name = "ahb_byte_lane_seq");
        super.new(name);
    endfunction : new

    //-------------------------------------------------------------------------
    // get_size - size for slot idx
    //-------------------------------------------------------------------------
    function ahb_size_e get_size(int unsigned idx);
        case (idx % NUM_SIZE)
            0:       return AHB_SIZE_8B;
            1:       return AHB_SIZE_16B;
            default: return AHB_SIZE_32B;
        endcase
    endfunction : get_size

    //-------------------------------------------------------------------------
    // byte_val - address-derived data byte
    //-------------------------------------------------------------------------
    function bit [7:0] byte_val(bit [AHB_ADDR_WIDTH-1:0] a);
        return a[7:0] ^ 8'hA5;
    endfunction : byte_val

    //-------------------------------------------------------------------------
    // lane_pattern - HWDATA for a beat at address a:
    //   active lanes   : byte_val
    //   inactive lanes : ~byte_val
    //-------------------------------------------------------------------------
    function bit [AHB_DATA_WIDTH-1:0] lane_pattern(bit [AHB_ADDR_WIDTH-1:0] a,
                                                   int unsigned             bytes);
        bit [AHB_DATA_WIDTH-1:0] w;
        int unsigned             lane      = a % BUS_BYTES;
        bit [AHB_ADDR_WIDTH-1:0] word_base = a - lane;

        for (int unsigned l = 0; l < BUS_BYTES; l++)
            w[l*8 +: 8] = ~byte_val(word_base + l);
        for (int unsigned b = 0; b < bytes; b++)
            w[(lane + b)*8 +: 8] = byte_val(a + b);

        return w;
    endfunction : lane_pattern

    //-------------------------------------------------------------------------
    // Body - per slot (shuffled order): SINGLE at every legal offset of the
    // first word, then INCR4 from a rotating start lane
    //-------------------------------------------------------------------------
    virtual task body();
        int unsigned             order[];
        int unsigned             offs[];
        int unsigned             idx;
        bit [AHB_ADDR_WIDTH-1:0] slot;
        ahb_size_e               sz;
        int unsigned             bytes;
        int unsigned             burst_offs;

        `uvm_info(get_type_name(),
                  $sformatf("Starting byte-lane walk: %0d iterations from 0x%08h, %0d lanes on a %0d-bit bus",
                            num_iter, base_addr, BUS_BYTES, AHB_DATA_WIDTH), UVM_LOW)

        // Shuffle slot order; same lanes covered for every seed
        order = new[num_iter];
        foreach (order[j]) order[j] = j;
        order.shuffle();

        foreach (order[j]) begin
            idx   = order[j];
            slot  = base_addr + idx * SLOT_SIZE;
            sz    = get_size(idx);
            bytes = 1 << sz;

            // Legal offsets in one bus word (shuffled)
            offs = new[BUS_BYTES / bytes];
            foreach (offs[k]) offs[k] = k * bytes;
            offs.shuffle();

            foreach (offs[k]) begin
                lane_transfer(AHB_BURST_SINGLE, slot + offs[k], sz);
                num_singles++;
            end

            // INCR4 in the upper half; start lane rotates with the slot
            burst_offs = BURST_OFFS + ((idx % BUS_BYTES) & ~(bytes - 1));
            lane_transfer(AHB_BURST_INCR4, slot + burst_offs, sz);
            num_bursts++;
        end

        report_walk();
    endtask : body

    //-------------------------------------------------------------------------
    // lane_transfer - write/read-back pair, wdata set from lane_pattern
    //-------------------------------------------------------------------------
    protected task lane_transfer(ahb_burst_e              burst_type,
                                 bit [AHB_ADDR_WIDTH-1:0] tgt_addr,
                                 ahb_size_e               sz);
        ahb_transaction          wr;
        bit [AHB_ADDR_WIDTH-1:0] a;
        int unsigned             bytes;

        bytes = 1 << sz;

        wr = ahb_transaction::type_id::create("wr");
        if (!wr.randomize() with {
                write == AHB_WRITE;
                burst == burst_type;
                size  == sz;
                addr  == tgt_addr;
            })
            `uvm_fatal(get_type_name(),
                       $sformatf("Write randomization failed (%s %s @0x%08h)",
                                 burst_type.name(), sz.name(), tgt_addr))

        foreach (wr.wdata[k]) begin
            a           = beat_address(wr, k);
            wr.wdata[k] = lane_pattern(a, bytes);
            lane_hits[a % BUS_BYTES]++;
        end

        `uvm_info(get_type_name(),
                  $sformatf("%s %s @0x%08h: %0d beats, start lane %0d, HWDATA[0]=0x%08h",
                            burst_type.name(), sz.name(), tgt_addr,
                            wr.get_num_beats(), tgt_addr % BUS_BYTES, wr.wdata[0]),
                  UVM_MEDIUM)

        write_read_burst(wr);
    endtask : lane_transfer

    //-------------------------------------------------------------------------
    // report_walk - summary; error if a lane was never used
    //-------------------------------------------------------------------------
    protected function void report_walk();
        `uvm_info(get_type_name(),
                  $sformatf("Byte-lane walk done: singles=%0d bursts=%0d beats=%0d mismatch=%0d",
                            num_singles, num_bursts, beats_checked, beats_mismatch),
                  (beats_mismatch == 0) ? UVM_LOW : UVM_NONE)

        foreach (lane_hits[l]) begin
            `uvm_info(get_type_name(),
                      $sformatf("  lane %0d -> %0d beats", l, lane_hits[l]),
                      UVM_MEDIUM)
            if (lane_hits[l] == 0)
                `uvm_error(get_type_name(),
                           $sformatf("byte lane %0d never carried an active transfer - raise +NUM_ITER (at least %0d needed)",
                                     l, NUM_SIZE))
        end
    endfunction : report_walk

endclass : ahb_byte_lane_seq

`endif // AHB_BYTE_LANE_SEQ_INCLUDED_
