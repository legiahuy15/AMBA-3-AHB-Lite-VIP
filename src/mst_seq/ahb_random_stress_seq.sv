//=============================================================================
// File        : ahb_random_stress_seq.sv
// Project     : AMBA 3 AHB-Lite VIP
// Description : Constrained-random mixed burst stress with read-back checking.
//=============================================================================

`ifndef AHB_RANDOM_STRESS_SEQ_INCLUDED_
`define AHB_RANDOM_STRESS_SEQ_INCLUDED_

class ahb_random_stress_seq extends ahb_base_seq;

    `uvm_object_utils(ahb_random_stress_seq)

    int unsigned num_iter = 100;
    int unsigned wait_max = 7;
    bit [AHB_ADDR_WIDTH-1:0] base_addr = 32'h0002_0000;

    ahb_slave_driver slv_drv;

    localparam int unsigned SLOT_SIZE = 128;

    int unsigned num_pipelined;
    int unsigned num_busy;
    int unsigned burst_count[8];
    int unsigned size_count[3];

    function new(string name = "ahb_random_stress_seq");
        super.new(name);
    endfunction : new

    virtual task body();
        ahb_transaction          wr;
        bit [AHB_ADDR_WIDTH-1:0] slot;
        int unsigned             wait_lo;
        int unsigned             wait_hi;
        bit                      pipelined;
        bit                      has_busy;

        `uvm_info(get_type_name(),
                  $sformatf("Starting random stress: iterations=%0d base=0x%08h wait_max=%0d",
                            num_iter, base_addr, wait_max), UVM_LOW)

        for (int unsigned i = 0; i < num_iter; i++) begin
            slot = base_addr + i * SLOT_SIZE;

            // Change slave timing only after the preceding pair has drained.
            wait_lo = $urandom_range(wait_max, 0);
            wait_hi = $urandom_range(wait_max, wait_lo);
            if (slv_drv != null) begin
                slv_drv.ready_delay_min = wait_lo;
                slv_drv.ready_delay_max = wait_hi;
            end

            pipelined = $urandom_range(1, 0);

            wr = ahb_transaction::type_id::create($sformatf("wr_%0d", i));
            if (!wr.randomize() with {
                    write == AHB_WRITE;
                    size inside {AHB_SIZE_8B, AHB_SIZE_16B, AHB_SIZE_32B};
                    burst inside {AHB_BURST_SINGLE, AHB_BURST_INCR,
                                  AHB_BURST_WRAP4, AHB_BURST_INCR4,
                                  AHB_BURST_WRAP8, AHB_BURST_INCR8,
                                  AHB_BURST_WRAP16, AHB_BURST_INCR16};
                    (burst == AHB_BURST_INCR) -> (num_beats inside {[1:16]});
                    addr inside {[slot : slot + SLOT_SIZE - 1]};
                    (burst inside {AHB_BURST_INCR, AHB_BURST_INCR4,
                                   AHB_BURST_INCR8, AHB_BURST_INCR16}) ->
                        (addr + num_beats * (1 << size) <= slot + SLOT_SIZE);
                    foreach (busy_cycles[k])
                        busy_cycles[k] dist {0 := 80, [1:3] := 20};
                    trailing_busy_cycles dist {0 := 85, [1:3] := 15};
                })
                `uvm_fatal(get_type_name(),
                           $sformatf("Randomization failed at iteration %0d, slot 0x%08h",
                                     i, slot))

            has_busy = (wr.trailing_busy_cycles != 0);
            foreach (wr.busy_cycles[k])
                has_busy |= (wr.busy_cycles[k] != 0);

            burst_count[int'(wr.burst)]++;
            size_count[int'(wr.size)]++;
            if (pipelined) num_pipelined++;
            if (has_busy)  num_busy++;

            `uvm_info(get_type_name(),
                      $sformatf("iter=%0d %s %s addr=0x%08h beats=%0d waits=%0d:%0d pipeline=%0b busy=%0b",
                                i, wr.burst.name(), wr.size.name(), wr.addr,
                                wr.num_beats, wait_lo, wait_hi,
                                pipelined, has_busy), UVM_MEDIUM)

            write_read_burst(wr, pipelined);
        end

        `uvm_info(get_type_name(),
                  $sformatf("Random stress done: pairs=%0d pipelined=%0d busy=%0d beats=%0d mismatch=%0d",
                            num_iter, num_pipelined, num_busy,
                            beats_checked, beats_mismatch),
                  (beats_mismatch == 0) ? UVM_LOW : UVM_NONE)
    endtask : body

endclass : ahb_random_stress_seq

`endif // AHB_RANDOM_STRESS_SEQ_INCLUDED_
