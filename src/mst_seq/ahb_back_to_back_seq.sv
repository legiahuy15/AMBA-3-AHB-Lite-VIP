//=============================================================================
// File        : ahb_back_to_back_seq.sv
// Project     : AMBA 3 AHB-Lite VIP
// Author      : Huy Le
// Description : Back-to-back traffic. Batches of write/read-back bursts are
//               queued without waiting so beat 0 of each transfer overlaps the
//               previous data phase (IHI0033A 3.1). max_outstanding is swept
//               per batch. Requires auto-response slave.
//=============================================================================

`ifndef AHB_BACK_TO_BACK_SEQ_INCLUDED_
`define AHB_BACK_TO_BACK_SEQ_INCLUDED_

class ahb_back_to_back_seq extends ahb_base_seq;

    `uvm_object_utils(ahb_back_to_back_seq)

    //-------------------------------------------------------------------------
    // Knobs
    //-------------------------------------------------------------------------
    int unsigned num_iter = 32;                 // write/read pairs

    bit [AHB_ADDR_WIDTH-1:0] base_addr = 32'h0001_0000;

    // Pairs queued per batch before drain and check
    int unsigned batch_pairs = 4;

    // Driver whose max_outstanding is swept (set by the test). Null: no sweep
    ahb_master_driver mst_drv;

    localparam int unsigned NUM_WINDOWS = 4;

    // Address slot per pair: 64B aligned, 2x the longest burst (8 x 4B)
    localparam int unsigned SLOT_SIZE = 64;

    //-------------------------------------------------------------------------
    // Statistics
    //-------------------------------------------------------------------------
    int unsigned num_queued;                        // transfers queued
    int unsigned deepest_outstanding;               // whole run
    int unsigned deepest_per_window[NUM_WINDOWS];   // per limit
    int unsigned limit_violations;                  // accepted beyond the limit

    // Accepted, not yet complete (FIFO order)
    protected ahb_transaction pend[$];

    // Limit sweep active (mst_drv != null)
    protected bit sweep_on;

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(string name = "ahb_back_to_back_seq");
        super.new(name);
    endfunction : new

    //-------------------------------------------------------------------------
    // max_outstanding sweep (AHB_ENV_004):
    //   0 - unlimited
    //   4 - deep pipeline
    //   2 - one successor (minimum for overlap)
    //   1 - serialized, no overlap
    //-------------------------------------------------------------------------
    function int unsigned get_limit(int unsigned idx);
        case (idx % NUM_WINDOWS)
            0:       return 0;
            1:       return 4;
            2:       return 2;
            default: return 1;
        endcase
    endfunction : get_limit

    //-------------------------------------------------------------------------
    // apply_limit - set driver limit; called between batches (pipeline empty)
    //-------------------------------------------------------------------------
    function void apply_limit(int unsigned lim);
        if (mst_drv == null) return;
        mst_drv.max_outstanding = lim;
    endfunction : apply_limit

    //-------------------------------------------------------------------------
    // limit_str - limit for log messages
    //-------------------------------------------------------------------------
    function string limit_str(int unsigned lim);
        if (lim == 0) return "unlimited";
        return $sformatf("%0d", lim);
    endfunction : limit_str

    //-------------------------------------------------------------------------
    // queue_tracked - queue one transfer and check pipeline depth against the
    // limit (queue_item() returns when the driver accepts the item)
    //-------------------------------------------------------------------------
    task queue_tracked(ahb_transaction tr, int unsigned lim, int unsigned win);
        queue_item(tr);
        pend.push_back(tr);
        num_queued++;

        // Retire completed transfers
        while (pend.size() > 0 && pend[0].done)
            void'(pend.pop_front());

        if (pend.size() > deepest_outstanding)
            deepest_outstanding = pend.size();
        if (pend.size() > deepest_per_window[win])
            deepest_per_window[win] = pend.size();

        if (sweep_on && lim != 0 && pend.size() > lim) begin
            limit_violations++;
            `uvm_error(get_type_name(),
                       $sformatf("Outstanding limit exceeded: %0d transfers in flight, max_outstanding=%0d",
                                 pend.size(), lim))
        end
    endtask : queue_tracked

    //-------------------------------------------------------------------------
    // Body
    //-------------------------------------------------------------------------
    virtual task body();
        ahb_transaction          wr_q[$];
        ahb_transaction          rd_q[$];
        ahb_transaction          wr, rd;
        bit [AHB_ADDR_WIDTH-1:0] slot;
        int unsigned             pair_idx;
        int unsigned             num_batches;
        int unsigned             this_batch;
        int unsigned             win;
        int unsigned             lim;

        if (batch_pairs == 0) batch_pairs = 1;

        sweep_on = (mst_drv != null);
        if (!sweep_on)
            `uvm_warning(get_type_name(),
                         "No master driver handle - the outstanding limit is not swept, traffic runs at the configured limit")

        num_batches = (num_iter + batch_pairs - 1) / batch_pairs;

        `uvm_info(get_type_name(),
                  $sformatf("Starting back-to-back traffic: %0d pairs from 0x%08h, %0d batches of %0d",
                            num_iter, base_addr, num_batches, batch_pairs), UVM_LOW)

        pair_idx = 0;
        for (int unsigned b = 0; b < num_batches; b++) begin
            win = b % NUM_WINDOWS;
            lim = get_limit(win);
            apply_limit(lim);

            this_batch = num_iter - pair_idx;
            if (this_batch > batch_pairs) this_batch = batch_pairs;

            `uvm_info(get_type_name(),
                      $sformatf("Batch %0d/%0d: %0d pairs, max_outstanding=%s",
                                b + 1, num_batches, this_batch,
                                limit_str(lim)), UVM_MEDIUM)

            wr_q.delete();
            rd_q.delete();

            //-----------------------------------------------------------------
            // Queue the whole batch without waiting
            //-----------------------------------------------------------------
            for (int unsigned k = 0; k < this_batch; k++) begin
                slot = base_addr + pair_idx * SLOT_SIZE;

                wr = ahb_transaction::type_id::create("wr");
                if (!wr.randomize() with {
                        write == AHB_WRITE;
                        burst inside {AHB_BURST_SINGLE, AHB_BURST_INCR,
                                      AHB_BURST_INCR4,  AHB_BURST_INCR8,
                                      AHB_BURST_WRAP4,  AHB_BURST_WRAP8};
                        size inside {AHB_SIZE_8B, AHB_SIZE_16B, AHB_SIZE_32B};
                        (burst == AHB_BURST_INCR) -> (num_beats inside {[2:8]});

                        // No BUSY
                        foreach (busy_cycles[i]) busy_cycles[i] == 0;
                        trailing_busy_cycles == 0;

                        // Burst stays inside its slot
                        addr inside {[slot : slot + SLOT_SIZE - 1]};
                        (burst inside {AHB_BURST_INCR, AHB_BURST_INCR4,
                                       AHB_BURST_INCR8}) ->
                            (addr + num_beats * (1 << size) <= slot + SLOT_SIZE);
                    })
                    `uvm_fatal(get_type_name(),
                               $sformatf("Write randomization failed @slot 0x%08h", slot))

                rd = build_read_back(wr);

                wr_q.push_back(wr);
                rd_q.push_back(rd);

                queue_tracked(wr, lim, win);
                queue_tracked(rd, lim, win);

                pair_idx++;
            end

            //-----------------------------------------------------------------
            // Drain and check
            //-----------------------------------------------------------------
            foreach (rd_q[k]) begin
                wr = wr_q[k];
                rd = rd_q[k];
                wait (wr.done);
                wait (rd.done);

                if (wr.aborted || rd.aborted) begin
                    `uvm_warning(get_type_name(),
                                 $sformatf("Pair aborted by reset: %s 0x%08h",
                                           wr.burst.name(), wr.addr))
                    continue;
                end

                compare_burst(wr, rd);
            end

            pend.delete();      // batch drained
        end

        //---------------------------------------------------------------------
        // Limits other than 1 must reach depth >= 2 (AHB_BAS_004)
        //---------------------------------------------------------------------
        for (int unsigned w = 0; w < NUM_WINDOWS; w++) begin
            lim = get_limit(w);
            if (deepest_per_window[w] == 0) continue;       // window never ran

            `uvm_info(get_type_name(),
                      $sformatf("  max_outstanding=%s -> deepest pipeline %0d transfers",
                                limit_str(lim), deepest_per_window[w]), UVM_MEDIUM)

            if (sweep_on && lim != 1 && deepest_per_window[w] < 2)
                `uvm_error(get_type_name(),
                           $sformatf("max_outstanding=%0d never held more than %0d transfer(s) - no overlap was possible",
                                     lim, deepest_per_window[w]))
        end

        `uvm_info(get_type_name(),
                  $sformatf("Back-to-back done: pairs=%0d transfers=%0d deepest=%0d limit_violations=%0d beats=%0d mismatch=%0d",
                            num_iter, num_queued, deepest_outstanding,
                            limit_violations, beats_checked, beats_mismatch),
                  (beats_mismatch == 0 && limit_violations == 0) ? UVM_LOW : UVM_NONE)
    endtask : body

endclass : ahb_back_to_back_seq

`endif // AHB_BACK_TO_BACK_SEQ_INCLUDED_
