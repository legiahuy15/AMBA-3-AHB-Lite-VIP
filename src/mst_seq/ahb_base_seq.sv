//=============================================================================
// File        : ahb_base_seq.sv
// Project     : AMBA 3 AHB-Lite VIP
// Author      : Huy Le
// Description : Base master sequence. Provides the send-and-wait helper that
//               all AHB-Lite master sequences use.
//               This file is `included inside ahb_seq_pkg.sv.
//=============================================================================

`ifndef AHB_BASE_SEQ_INCLUDED_
`define AHB_BASE_SEQ_INCLUDED_

class ahb_base_seq extends uvm_sequence #(ahb_transaction);

    `uvm_object_utils(ahb_base_seq)

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(string name = "ahb_base_seq");
        super.new(name);
    endfunction : new

    //-------------------------------------------------------------------------
    // send_and_wait - send one item and block until the bus transfer finishes.
    //   The driver is pipelined: item_done() fires when the item is queued, so
    //   finish_item() returns before the transfer completes. rdata[]/resp[] are
    //   valid only after done_event.ev.
    //   Returns 0 if a reset flushed the item (rdata[]/resp[] invalid).
    //-------------------------------------------------------------------------
    virtual task send_and_wait(ahb_transaction tr, output bit ok);
        start_item(tr);
        finish_item(tr);
        // Safe to arm here: the driver needs at least one clock edge to
        // complete the transfer, finish_item() returns in the same time step
        @(tr.done_event.ev);
        ok = !tr.aborted;
        if (!ok)
            `uvm_warning(get_type_name(),
                         $sformatf("Transaction aborted by reset: %s 0x%08h",
                                   tr.write.name(), tr.addr))
    endtask : send_and_wait

endclass : ahb_base_seq

`endif // AHB_BASE_SEQ_INCLUDED_
