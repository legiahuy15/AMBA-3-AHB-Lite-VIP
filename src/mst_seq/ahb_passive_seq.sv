//=============================================================================
// File        : ahb_passive_seq.sv
// Project     : AMBA 3 AHB-Lite VIP
// Description : Generates legal write traffic while the slave agent is
//               passive. No read-back is used because a passive slave does not
//               provide a memory model or drive response data.
//=============================================================================

`ifndef AHB_PASSIVE_SEQ_INCLUDED_
`define AHB_PASSIVE_SEQ_INCLUDED_

class ahb_passive_seq extends ahb_base_seq;

    `uvm_object_utils(ahb_passive_seq)

    int unsigned num_iter = 12;
    bit [AHB_ADDR_WIDTH-1:0] base_addr = 32'h0000_A000;

    function new(string name = "ahb_passive_seq");
        super.new(name);
    endfunction : new

    virtual task body();
        ahb_transaction tr;
        bit             ok;

        `uvm_info(get_type_name(),
                  $sformatf("Starting passive-slave traffic: %0d transfers", num_iter),
                  UVM_LOW)

        for (int unsigned i = 0; i < num_iter; i++) begin
            tr = ahb_transaction::type_id::create($sformatf("tr_%0d", i));
            if (!tr.randomize() with {
                    write == AHB_WRITE;
                    burst inside {AHB_BURST_SINGLE, AHB_BURST_INCR4};
                    size inside {AHB_SIZE_8B, AHB_SIZE_16B, AHB_SIZE_32B};
                    addr inside {[base_addr + i * 32 : base_addr + i * 32 + 15]};
                })
                `uvm_fatal(get_type_name(),
                           $sformatf("Randomization failed at iteration %0d", i))

            send_and_wait(tr, ok);
            if (!ok)
                `uvm_error(get_type_name(),
                           $sformatf("Transfer %0d was aborted", i))
        end

        `uvm_info(get_type_name(),
                  $sformatf("Passive-slave traffic complete: %0d transfers", num_iter),
                  UVM_LOW)
    endtask : body

endclass : ahb_passive_seq

`endif // AHB_PASSIVE_SEQ_INCLUDED_
