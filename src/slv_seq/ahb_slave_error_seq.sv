//=============================================================================
// File        : ahb_slave_error_seq.sv
// Project     : AMBA 3 AHB-Lite VIP
// Author      : Huy Le
// Description : Slave response sequence for error injection. Feeds one
//               ahb_slave_response per active beat: every access inside the
//               unmapped region gets ERROR the way a default slave would, and
//               a configurable share of the remaining beats gets ERROR too.
//               Runs forever - the test ends it by dropping its objection.
//               Requires auto_gen_resp = 0 on the slave agent.
//               This file is `included inside ahb_seq_pkg.sv.
//=============================================================================

`ifndef AHB_SLAVE_ERROR_SEQ_INCLUDED_
`define AHB_SLAVE_ERROR_SEQ_INCLUDED_

class ahb_slave_error_seq extends uvm_sequence #(ahb_slave_response);

    `uvm_object_utils(ahb_slave_error_seq)
    `uvm_declare_p_sequencer(ahb_slave_sequencer)

    //-------------------------------------------------------------------------
    // Knobs
    //-------------------------------------------------------------------------
    int unsigned error_rate_pct  = 25;   // share of mapped beats given ERROR
    int unsigned ready_delay_max = 2;    // wait states inserted before a response

    // Region with no slave behind it. Every active beat here is answered with
    // ERROR, which is what a default slave does. IDLE and BUSY never reach
    // this sequence - the driver answers them zero-wait OKAY on its own
    bit [AHB_ADDR_WIDTH-1:0] unmapped_base = 32'h0000_9000;
    bit [AHB_ADDR_WIDTH-1:0] unmapped_size = 32'h0000_1000;

    //-------------------------------------------------------------------------
    // Statistics
    //-------------------------------------------------------------------------
    int unsigned num_rsp;
    int unsigned num_error;
    int unsigned num_unmapped;

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(string name = "ahb_slave_error_seq");
        super.new(name);
    endfunction : new

    //-------------------------------------------------------------------------
    // Body - one response per active beat, for as long as the test runs.
    //   Fields are assigned rather than randomized on purpose: the item's
    //   c_ready_delay_default and c_resp_default are soft equalities to 0 and
    //   OKAY, and an inline dist does not conflict with a satisfiable soft
    //   constraint, so randomize() would quietly return zero-wait OKAY forever
    //-------------------------------------------------------------------------
    virtual task body();
        ahb_slave_response       rsp;
        bit [AHB_ADDR_WIDTH-1:0] addr;
        bit                      unmapped;

        `uvm_info(get_type_name(),
                  $sformatf("Slave error injection active: %0d%% ERROR, up to %0d wait states, unmapped [0x%08h : 0x%08h]",
                            error_rate_pct, ready_delay_max,
                            unmapped_base, unmapped_base + unmapped_size - 1), UVM_LOW)

        forever begin
            rsp = ahb_slave_response::type_id::create("rsp");

            // Blocks until the driver asks for an item, which is after it has
            // published the address phase it is answering
            start_item(rsp);

            addr     = p_sequencer.req_addr;
            unmapped = (addr >= unmapped_base) &&
                       (addr <  unmapped_base + unmapped_size);

            rsp.ready_delay = $urandom_range(ready_delay_max, 0);
            rsp.rdata       = $urandom();
            rsp.resp        = (unmapped || ($urandom_range(99, 0) < error_rate_pct))
                              ? AHB_RESP_ERROR : AHB_RESP_OKAY;

            num_rsp++;
            if (rsp.resp == AHB_RESP_ERROR) num_error++;
            if (unmapped)                   num_unmapped++;

            `uvm_info(get_type_name(),
                      $sformatf("Response %0d: %s @0x%08h -> %s, %0d wait states%s",
                                num_rsp, p_sequencer.req_write.name(), addr,
                                rsp.resp.name(), rsp.ready_delay,
                                unmapped ? " (unmapped)" : ""), UVM_HIGH)

            finish_item(rsp);
        end
    endtask : body

endclass : ahb_slave_error_seq

`endif // AHB_SLAVE_ERROR_SEQ_INCLUDED_
