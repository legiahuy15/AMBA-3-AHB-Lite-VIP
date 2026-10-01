//=============================================================================
// File        : ahb_reset_seq.sv
// Project     : AMBA 3 AHB-Lite VIP
// Author      : Huy Le
// Description : Reset recovery sequence. Asserts HRESETn during INCR16 bursts
//               via the global UVM event "ahb_reset_req" (tb_top), then runs
//               write/read pairs that must complete.
//=============================================================================

`ifndef AHB_RESET_SEQ_INCLUDED_
`define AHB_RESET_SEQ_INCLUDED_

class ahb_reset_seq extends ahb_base_seq;

    `uvm_object_utils(ahb_reset_seq)

    //-------------------------------------------------------------------------
    // Knobs
    //-------------------------------------------------------------------------
    int unsigned num_iter    = 18;   // bursts in the reset phase
    int unsigned num_recover = 4;    // write/read pairs in the recovery phase
    int unsigned reset_every = 3;    // reset on every Nth burst

    bit [AHB_ADDR_WIDTH-1:0] base_addr    = 32'h0000_A000;   // reset phase
    bit [AHB_ADDR_WIDTH-1:0] recover_addr = 32'h0000_B000;   // recovery phase

    localparam int unsigned SLOT_SIZE = 64;

    // Reset delay from burst start (INCR16 >= 160 ns)
    localparam int unsigned RESET_DELAY_MIN_NS = 50;
    localparam int unsigned RESET_DELAY_MAX_NS = 150;

    //-------------------------------------------------------------------------
    // Statistics
    //-------------------------------------------------------------------------
    int unsigned num_sent;
    int unsigned num_aborted;
    int unsigned num_resets;

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(string name = "ahb_reset_seq");
        super.new(name);
    endfunction : new

    //-------------------------------------------------------------------------
    // Body - reset phase, then recovery phase
    //-------------------------------------------------------------------------
    virtual task body();
        uvm_event                reset_ev;
        ahb_transaction          tr;
        bit [AHB_ADDR_WIDTH-1:0] slot;
        bit                      ok;
        int unsigned             delay_ns;

        reset_ev = uvm_event_pool::get_global("ahb_reset_req");

        `uvm_info(get_type_name(),
                  $sformatf("Reset phase: %0d bursts, reset on every %0dth",
                            num_iter, reset_every), UVM_LOW)

        //---------------------------------------------------------------------
        // Reset phase - aborts expected
        //---------------------------------------------------------------------
        expect_reset_abort = 1'b1;

        for (int unsigned i = 0; i < num_iter; i++) begin
            slot = base_addr + i * SLOT_SIZE;

            if ((i % reset_every) == (reset_every - 1)) begin
                delay_ns = $urandom_range(RESET_DELAY_MAX_NS, RESET_DELAY_MIN_NS);
                num_resets++;
                // Asynchronous reset, delay_ns after burst start
                fork
                    begin
                        #(delay_ns * 1ns);
                        `uvm_info(get_type_name(),
                                  $sformatf("Asserting reset %0d ns into burst %0d",
                                            delay_ns, i), UVM_MEDIUM)
                        reset_ev.trigger();
                    end
                join_none
            end

            tr = ahb_transaction::type_id::create("tr");
            if (!tr.randomize() with {
                    write == AHB_WRITE;
                    burst == AHB_BURST_INCR16;
                    size  == AHB_SIZE_32B;
                    addr  == slot;
                })
                `uvm_fatal(get_type_name(),
                           $sformatf("Randomization failed @slot 0x%08h", slot))

            send_and_wait(tr, ok);
            num_sent++;
            if (!ok) num_aborted++;
        end

        // Wait for pending resets
        wait fork;
        #500ns;

        //---------------------------------------------------------------------
        // Recovery phase - no resets; any abort is an error
        //---------------------------------------------------------------------
        expect_reset_abort = 1'b0;

        `uvm_info(get_type_name(),
                  $sformatf("Recovery phase: %0d write/read pairs", num_recover), UVM_LOW)

        for (int unsigned j = 0; j < num_recover; j++) begin
            slot = recover_addr + j * SLOT_SIZE;

            tr = ahb_transaction::type_id::create("tr");
            if (!tr.randomize() with {
                    write == AHB_WRITE;
                    burst == AHB_BURST_INCR4;
                    size  == AHB_SIZE_32B;
                    addr  == slot;
                })
                `uvm_fatal(get_type_name(), "Recovery write randomization failed")
            send_and_wait(tr, ok);
            if (!ok)
                `uvm_error(get_type_name(),
                           $sformatf("Write aborted after the last reset @0x%08h - recovery failed", slot))

            tr = ahb_transaction::type_id::create("tr");
            if (!tr.randomize() with {
                    write == AHB_READ;
                    burst == AHB_BURST_INCR4;
                    size  == AHB_SIZE_32B;
                    addr  == slot;
                })
                `uvm_fatal(get_type_name(), "Recovery read randomization failed")
            send_and_wait(tr, ok);
            if (!ok)
                `uvm_error(get_type_name(),
                           $sformatf("Read aborted after the last reset @0x%08h - recovery failed", slot))
        end

        `uvm_info(get_type_name(),
                  $sformatf("Reset sequence done: sent=%0d aborted=%0d resets=%0d",
                            num_sent, num_aborted, num_resets), UVM_LOW)

        // At least one reset must abort a transfer
        if (num_resets > 0 && num_aborted == 0)
            `uvm_error(get_type_name(),
                       "No transaction was aborted - reset never landed on an active transfer")
    endtask : body

endclass : ahb_reset_seq

`endif // AHB_RESET_SEQ_INCLUDED_