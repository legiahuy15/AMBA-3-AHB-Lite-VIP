//=============================================================================
// File        : ahb_wait_state_seq.sv
// Project     : AMBA 3 AHB-Lite VIP
// Author      : Huy Le
// Description : Wait-state sweep from 0 to 16 (IHI0033A 5.1.2) with
//               write/read-back pairs; every other pair pipelined.
//               Requires auto-response slave.
//=============================================================================

`ifndef AHB_WAIT_STATE_SEQ_INCLUDED_
`define AHB_WAIT_STATE_SEQ_INCLUDED_

class ahb_wait_state_seq extends ahb_base_seq;

    `uvm_object_utils(ahb_wait_state_seq)

    //-------------------------------------------------------------------------
    // Knobs
    //-------------------------------------------------------------------------
    int unsigned num_iter = 24;

    bit [AHB_ADDR_WIDTH-1:0] base_addr = 32'h0000_D000;

    // Upper limit for every window
    int unsigned wait_max = 16;

    // Slave driver for the sweep (set by the test). Null: no sweep
    ahb_slave_driver slv_drv;

    localparam int unsigned NUM_WINDOWS = 8;

    // Address slot per burst (16 x 4B), 64B aligned
    localparam int unsigned SLOT_SIZE = 64;

    //-------------------------------------------------------------------------
    // Statistics
    //-------------------------------------------------------------------------
    int unsigned iter_per_window[NUM_WINDOWS];   // bursts per window
    int unsigned num_pipelined;                  // pipelined pairs
    int unsigned deepest_window;                 // largest max wait applied

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(string name = "ahb_wait_state_seq");
        super.new(name);
    endfunction : new

    //-------------------------------------------------------------------------
    // get_window - wait-state range [lo:hi] per beat:
    //   0        - zero wait
    //   1, 2, 3  - fixed
    //   1:7, 8:15- random per beat
    //   16       - maximum, IHI0033A 5.1.2 (AHB_WAI_009)
    //   0:16     - full range
    //-------------------------------------------------------------------------
    function void get_window(input  int unsigned idx,
                             output int unsigned lo,
                             output int unsigned hi);
        case (idx % NUM_WINDOWS)
            0:       begin lo = 0;  hi = 0;  end
            1:       begin lo = 1;  hi = 1;  end
            2:       begin lo = 2;  hi = 2;  end
            3:       begin lo = 3;  hi = 3;  end
            4:       begin lo = 1;  hi = 7;  end
            5:       begin lo = 8;  hi = 15; end
            6:       begin lo = 16; hi = 16; end
            default: begin lo = 0;  hi = 16; end
        endcase

        // Clamp to wait_max
        if (hi > wait_max) hi = wait_max;
        if (lo > hi)       lo = hi;
    endfunction : get_window

    //-------------------------------------------------------------------------
    // apply_window - set slave wait states; called between transfers
    //-------------------------------------------------------------------------
    function void apply_window(int unsigned lo, int unsigned hi);
        if (slv_drv == null) return;
        slv_drv.ready_delay_min = lo;
        slv_drv.ready_delay_max = hi;
        if (hi > deepest_window) deepest_window = hi;
    endfunction : apply_window

    //-------------------------------------------------------------------------
    // Body - num_iter x (write, read back, compare)
    //-------------------------------------------------------------------------
    virtual task body();
        ahb_transaction          wr;
        bit [AHB_ADDR_WIDTH-1:0] slot;
        int unsigned             lo, hi;
        bit                      deep;
        bit                      pipelined;

        if (slv_drv == null)
            `uvm_warning(get_type_name(),
                         "No slave driver handle - the wait-state window is not swept, traffic runs at the configured back-pressure")

        `uvm_info(get_type_name(),
                  $sformatf("Starting wait-state sweep: %0d bursts from 0x%08h, up to %0d wait states per beat",
                            num_iter, base_addr, wait_max), UVM_LOW)

        for (int unsigned i = 0; i < num_iter; i++) begin
            slot = base_addr + i * SLOT_SIZE;

            get_window(i, lo, hi);
            apply_window(lo, hi);
            iter_per_window[i % NUM_WINDOWS]++;

            // Short bursts only for deep windows (runtime)
            deep = (hi > 7);

            // Odd iterations pipelined: read address phase during the write's
            // wait states (AHB_WAI_002..004)
            pipelined = ((i % 2) == 1);
            if (pipelined) num_pipelined++;

            wr = ahb_transaction::type_id::create("wr");
            if (!wr.randomize() with {
                    write == AHB_WRITE;
                    size inside {AHB_SIZE_8B, AHB_SIZE_16B, AHB_SIZE_32B};

                    deep  -> (burst inside {AHB_BURST_SINGLE, AHB_BURST_INCR4,
                                            AHB_BURST_WRAP4});
                    !deep -> (burst inside {AHB_BURST_SINGLE, AHB_BURST_INCR,
                                            AHB_BURST_INCR4,  AHB_BURST_INCR8,
                                            AHB_BURST_WRAP4,  AHB_BURST_WRAP8});
                    (burst == AHB_BURST_INCR) -> (num_beats inside {[2:8]});

                    // No BUSY
                    foreach (busy_cycles[k]) busy_cycles[k] == 0;
                    trailing_busy_cycles == 0;

                    // Burst stays inside its slot
                    addr inside {[slot : slot + SLOT_SIZE - 1]};
                    (burst inside {AHB_BURST_INCR,  AHB_BURST_INCR4,
                                   AHB_BURST_INCR8, AHB_BURST_INCR16}) ->
                        (addr + num_beats * (1 << size) <= slot + SLOT_SIZE);
                })
                `uvm_fatal(get_type_name(),
                           $sformatf("Randomization failed @slot 0x%08h (window %0d:%0d)",
                                     slot, lo, hi))

            `uvm_info(get_type_name(),
                      $sformatf("%s %s @0x%08h, %0d beats, waits=%0d:%0d, pipelined=%0b",
                                wr.burst.name(), wr.size.name(), wr.addr,
                                wr.num_beats, lo, hi, pipelined), UVM_MEDIUM)

            write_read_burst(wr, pipelined);
        end

        `uvm_info(get_type_name(),
                  $sformatf("Wait-state sweep done: deepest window=%0d, pipelined pairs=%0d, beats=%0d mismatch=%0d",
                            deepest_window, num_pipelined,
                            beats_checked, beats_mismatch),
                  (beats_mismatch == 0) ? UVM_LOW : UVM_NONE)

        for (int unsigned w = 0; w < NUM_WINDOWS; w++) begin
            get_window(w, lo, hi);
            `uvm_info(get_type_name(),
                      $sformatf("  window %0d:%0d -> %0d bursts",
                                lo, hi, iter_per_window[w]), UVM_MEDIUM)
        end
    endtask : body

endclass : ahb_wait_state_seq

`endif // AHB_WAIT_STATE_SEQ_INCLUDED_
