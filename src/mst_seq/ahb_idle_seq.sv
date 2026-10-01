//=============================================================================
// File        : ahb_idle_seq.sv
// Project     : AMBA 3 AHB-Lite VIP
// Author      : Huy Le
// Description : IDLE transfer sequence. Inserts IDLE runs (1..max_gap cycles)
//               around write/read-back pairs, in three phases:
//                 1) gap     - zero wait states (AHB_TRN_001, AHB_TRN_006)
//                 2) busy    - bursts with BUSY (AHB_WAI_010)
//                 3) in-wait - IDLE with HREADY=0, then NONSEQ to a new
//                              address (AHB_WAI_007)
//               Requires auto-response slave.
//=============================================================================

`ifndef AHB_IDLE_SEQ_INCLUDED_
`define AHB_IDLE_SEQ_INCLUDED_

class ahb_idle_seq extends ahb_base_seq;

    `uvm_object_utils(ahb_idle_seq)

    //-------------------------------------------------------------------------
    // Knobs
    //-------------------------------------------------------------------------
    int unsigned num_iter = 24;                 // write/read pairs (total)

    bit [AHB_ADDR_WIDTH-1:0] base_addr = 32'h0000_F000;

    // Max requested IDLE cycles between transfers (driver adds its own IDLE)
    int unsigned max_gap = 4;

    //-------------------------------------------------------------------------
    // Handles supplied by the test
    //-------------------------------------------------------------------------

    // Clock for IDLE gap timing. Null: no extra IDLE cycles
    virtual ahb_if vif;

    // Slave driver for per-phase wait states. Null: configured wait states
    ahb_slave_driver slv_drv;

    localparam int unsigned NUM_PHASES = 3;

    // Address slot per pair: 64B aligned, 2x the longest burst (8 x 4B)
    localparam int unsigned SLOT_SIZE = 64;

    //-------------------------------------------------------------------------
    // Statistics
    //-------------------------------------------------------------------------
    int unsigned iter_per_phase[NUM_PHASES];    // pairs per phase
    int unsigned num_gaps;                      // IDLE runs requested
    int unsigned num_gap_cycles;                // total IDLE cycles requested
    int unsigned longest_gap;                   // longest run requested

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(string name = "ahb_idle_seq");
        super.new(name);
    endfunction : new

    //-------------------------------------------------------------------------
    // apply_window - set slave wait states; called between transfers
    //-------------------------------------------------------------------------
    function void apply_window(int unsigned lo, int unsigned hi);
        if (slv_drv == null) return;
        slv_drv.ready_delay_min = lo;
        slv_drv.ready_delay_max = hi;
    endfunction : apply_window

    //-------------------------------------------------------------------------
    // idle_gap - wait n bus cycles with the driver queue empty (bus IDLE)
    //-------------------------------------------------------------------------
    task idle_gap(int unsigned n);
        if (n == 0) return;

        num_gaps++;
        num_gap_cycles += n;
        if (n > longest_gap) longest_gap = n;

        if (vif == null) return;
        repeat (n) @(vif.monitor_cb);
    endtask : idle_gap

    //-------------------------------------------------------------------------
    // random_gap - 1..max_gap cycles
    //-------------------------------------------------------------------------
    function int unsigned random_gap();
        if (max_gap == 0) return 1;
        return $urandom_range(max_gap, 1);
    endfunction : random_gap

    //-------------------------------------------------------------------------
    // Body - three phases, separate address ranges
    //-------------------------------------------------------------------------
    virtual task body();
        int unsigned n_gap, n_busy, n_wait;

        if (num_iter < NUM_PHASES) num_iter = NUM_PHASES;   // >= 1 pair per phase

        if (vif == null)
            `uvm_warning(get_type_name(),
                         "No bus interface handle - IDLE runs are not extended, the bus only idles for the cycle the driver inserts itself")
        if (slv_drv == null)
            `uvm_warning(get_type_name(),
                         "No slave driver handle - the wait-state window is not set per phase, traffic runs at the configured back-pressure")

        n_gap  = (num_iter + 2) / NUM_PHASES;
        n_busy = (num_iter + 1) / NUM_PHASES;
        n_wait = num_iter - n_gap - n_busy;

        `uvm_info(get_type_name(),
                  $sformatf("Starting IDLE traffic: %0d pairs from 0x%08h, IDLE runs up to %0d cycles (gap=%0d busy=%0d in-wait=%0d)",
                            num_iter, base_addr, max_gap, n_gap, n_busy, n_wait),
                  UVM_LOW)

        run_gap_phase    (n_gap,  base_addr);
        run_busy_phase   (n_busy, base_addr + n_gap  * SLOT_SIZE);
        run_in_wait_phase(n_wait, base_addr + (n_gap + n_busy) * SLOT_SIZE);

        `uvm_info(get_type_name(),
                  $sformatf("IDLE traffic done: pairs=%0d gaps=%0d idle_cycles_requested=%0d longest=%0d beats=%0d mismatch=%0d",
                            num_iter, num_gaps, num_gap_cycles, longest_gap,
                            beats_checked, beats_mismatch),
                  (beats_mismatch == 0) ? UVM_LOW : UVM_NONE)

        for (int unsigned p = 0; p < NUM_PHASES; p++) begin
            `uvm_info(get_type_name(),
                      $sformatf("  phase %0d -> %0d pairs", p, iter_per_phase[p]),
                      UVM_MEDIUM)
        end
    endtask : body

    //-------------------------------------------------------------------------
    // Phase 1 - zero wait states; IDLE runs before, between and after each
    // write/read pair (AHB_TRN_001, AHB_TRN_006)
    //-------------------------------------------------------------------------
    task run_gap_phase(int unsigned n, bit [AHB_ADDR_WIDTH-1:0] base);
        ahb_transaction          wr, rd;
        bit [AHB_ADDR_WIDTH-1:0] slot;
        bit                      ok;

        apply_window(0, 0);

        for (int unsigned i = 0; i < n; i++) begin
            slot = base + i * SLOT_SIZE;
            iter_per_phase[0]++;

            wr = ahb_transaction::type_id::create("wr");
            if (!wr.randomize() with {
                    write == AHB_WRITE;
                    burst inside {AHB_BURST_SINGLE, AHB_BURST_INCR,
                                  AHB_BURST_INCR4,  AHB_BURST_INCR8,
                                  AHB_BURST_WRAP4,  AHB_BURST_WRAP8};
                    size inside {AHB_SIZE_8B, AHB_SIZE_16B, AHB_SIZE_32B};
                    (burst == AHB_BURST_INCR) -> (num_beats inside {[2:8]});

                    // No BUSY
                    foreach (busy_cycles[k]) busy_cycles[k] == 0;
                    trailing_busy_cycles == 0;

                    // Burst stays inside its slot
                    addr inside {[slot : slot + SLOT_SIZE - 1]};
                    (burst inside {AHB_BURST_INCR, AHB_BURST_INCR4,
                                   AHB_BURST_INCR8}) ->
                        (addr + num_beats * (1 << size) <= slot + SLOT_SIZE);
                })
                `uvm_fatal(get_type_name(),
                           $sformatf("Gap-phase randomization failed @slot 0x%08h", slot))

            rd = build_read_back(wr);

            idle_gap(random_gap());
            send_and_wait(wr, ok);
            if (!ok) continue;

            idle_gap(random_gap());
            send_and_wait(rd, ok);
            if (!ok) continue;

            idle_gap(random_gap());

            `uvm_info(get_type_name(),
                      $sformatf("[gap] %s %s @0x%08h, %0d beats",
                                wr.burst.name(), wr.size.name(), wr.addr,
                                wr.num_beats), UVM_MEDIUM)

            compare_burst(wr, rd);
        end
    endtask : run_gap_phase

    //-------------------------------------------------------------------------
    // Phase 2 - IDLE runs plus BUSY inside bursts (AHB_WAI_010, AHB_TRN_006)
    //-------------------------------------------------------------------------
    task run_busy_phase(int unsigned n, bit [AHB_ADDR_WIDTH-1:0] base);
        ahb_transaction          wr, rd;
        bit [AHB_ADDR_WIDTH-1:0] slot;
        bit                      ok;

        apply_window(0, 2);

        for (int unsigned i = 0; i < n; i++) begin
            slot = base + i * SLOT_SIZE;
            iter_per_phase[1]++;

            wr = ahb_transaction::type_id::create("wr");
            if (!wr.randomize() with {
                    write == AHB_WRITE;
                    // Multi-beat only (no BUSY on SINGLE)
                    burst inside {AHB_BURST_INCR,  AHB_BURST_INCR4,
                                  AHB_BURST_INCR8, AHB_BURST_WRAP4,
                                  AHB_BURST_WRAP8};
                    size inside {AHB_SIZE_8B, AHB_SIZE_16B, AHB_SIZE_32B};
                    (burst == AHB_BURST_INCR) -> (num_beats inside {[2:8]});

                    // 1-2 BUSY cycles before every beat except the first
                    foreach (busy_cycles[k]) {
                        if (k > 0) busy_cycles[k] inside {[1:2]};
                        else       busy_cycles[k] == 0;
                    }

                    trailing_busy_cycles == 0;

                    // Burst stays inside its slot
                    addr inside {[slot : slot + SLOT_SIZE - 1]};
                    (burst inside {AHB_BURST_INCR, AHB_BURST_INCR4,
                                   AHB_BURST_INCR8}) ->
                        (addr + num_beats * (1 << size) <= slot + SLOT_SIZE);
                })
                `uvm_fatal(get_type_name(),
                           $sformatf("Busy-phase randomization failed @slot 0x%08h", slot))

            rd = build_read_back(wr);

            idle_gap(random_gap());
            send_and_wait(wr, ok);
            if (!ok) continue;

            idle_gap(random_gap());
            send_and_wait(rd, ok);
            if (!ok) continue;

            `uvm_info(get_type_name(),
                      $sformatf("[busy] %s %s @0x%08h, %0d beats",
                                wr.burst.name(), wr.size.name(), wr.addr,
                                wr.num_beats), UVM_MEDIUM)

            compare_burst(wr, rd);
        end
    endtask : run_busy_phase

    //-------------------------------------------------------------------------
    // Phase 3 - IDLE during a wait state. Pipelined write/read pair with
    // en_idle_to_nonseq_in_wait and 1-3 wait states: IDLE with HREADY=0, then
    // NONSEQ with a new HADDR (AHB_WAI_007). Multi-beat only, so the read
    // address differs from the last write beat
    //-------------------------------------------------------------------------
    task run_in_wait_phase(int unsigned n, bit [AHB_ADDR_WIDTH-1:0] base);
        ahb_transaction          wr;
        bit [AHB_ADDR_WIDTH-1:0] slot;

        apply_window(1, 3);     // every beat has wait states

        for (int unsigned i = 0; i < n; i++) begin
            slot = base + i * SLOT_SIZE;
            iter_per_phase[2]++;

            wr = ahb_transaction::type_id::create("wr");
            if (!wr.randomize() with {
                    write == AHB_WRITE;
                    burst inside {AHB_BURST_INCR,  AHB_BURST_INCR4,
                                  AHB_BURST_INCR8, AHB_BURST_WRAP4,
                                  AHB_BURST_WRAP8};
                    size inside {AHB_SIZE_8B, AHB_SIZE_16B, AHB_SIZE_32B};
                    (burst == AHB_BURST_INCR) -> (num_beats inside {[2:8]});

                    // No BUSY
                    foreach (busy_cycles[k]) busy_cycles[k] == 0;
                    trailing_busy_cycles == 0;

                    // Burst stays inside its slot
                    addr inside {[slot : slot + SLOT_SIZE - 1]};
                    (burst inside {AHB_BURST_INCR, AHB_BURST_INCR4,
                                   AHB_BURST_INCR8}) ->
                        (addr + num_beats * (1 << size) <= slot + SLOT_SIZE);
                })
                `uvm_fatal(get_type_name(),
                           $sformatf("In-wait-phase randomization failed @slot 0x%08h", slot))

            `uvm_info(get_type_name(),
                      $sformatf("[in-wait] %s %s @0x%08h, %0d beats",
                                wr.burst.name(), wr.size.name(), wr.addr,
                                wr.num_beats), UVM_MEDIUM)

            write_read_burst(wr, 1'b1);

            idle_gap(random_gap());
        end
    endtask : run_in_wait_phase

endclass : ahb_idle_seq

`endif // AHB_IDLE_SEQ_INCLUDED_
