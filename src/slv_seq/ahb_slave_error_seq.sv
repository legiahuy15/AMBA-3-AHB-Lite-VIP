//=============================================================================
// File        : ahb_slave_error_seq.sv
// Project     : AMBA 3 AHB-Lite VIP
// Author      : Huy Le
// Description : Slave error injection. One response per active beat: ERROR in
//               the unmapped region, ERROR at error_rate_pct elsewhere.
//               Runs forever. Requires auto_gen_resp = 0.
//=============================================================================

`ifndef AHB_SLAVE_ERROR_SEQ_INCLUDED_
`define AHB_SLAVE_ERROR_SEQ_INCLUDED_

class ahb_slave_error_seq extends uvm_sequence #(ahb_slave_response);

    `uvm_object_utils(ahb_slave_error_seq)
    `uvm_declare_p_sequencer(ahb_slave_sequencer)

    //-------------------------------------------------------------------------
    // Knobs
    //-------------------------------------------------------------------------
    int unsigned error_rate_pct  = 25;   // ERROR rate (%) outside unmapped region
    int unsigned ready_delay_max = 2;    // max wait states per beat

    // Unmapped region: always ERROR
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
    // Body - fields assigned directly (randomize() would keep the soft
    // zero-wait OKAY defaults)
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

            // Returns after the driver publishes the address phase
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
