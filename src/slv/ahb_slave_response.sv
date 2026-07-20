//==============================================================================
// File        : ahb_slave_response.sv
// Project     : AMBA 3 AHB-Lite VIP
// Author      : Huy Le
// Description : AHB-Lite slave response item (sequence item).
//               One item describes how the slave driver answers a SINGLE
//               data phase (beat): how many wait states to insert, the
//               transfer response, and the read data to return.
//               Used only when the slave agent runs in sequence mode
//               (ahb_agent_config.auto_gen_resp = 0). In auto-generate mode
//               the slave driver builds responses itself and never pulls
//               these items.
//               This file is `included inside ahb_pkg.sv.
//==============================================================================

class ahb_slave_response extends uvm_sequence_item;

    //-------------------------------------------------------------------------
    // Response fields (one data phase / beat)
    //-------------------------------------------------------------------------

    // Wait states: number of cycles HREADY is held low before the beat
    // completes. 0 = zero-wait (HREADY high immediately)
    rand int unsigned             ready_delay;

    // Transfer response for this beat. ERROR is driven as the spec-mandated
    // two-cycle response by the driver (HREADY low + HRESP high, then
    // HREADY high + HRESP high)
    rand ahb_resp_e               resp;

    // Read data returned on HRDATA (used when the observed transfer is a read)
    rand bit [AHB_DATA_WIDTH-1:0] rdata;

    //-------------------------------------------------------------------------
    // UVM utility macro
    //-------------------------------------------------------------------------
    `uvm_object_utils_begin(ahb_slave_response)
        `uvm_field_int (              ready_delay, UVM_ALL_ON)
        `uvm_field_enum(ahb_resp_e,   resp,        UVM_ALL_ON)
        `uvm_field_int (              rdata,       UVM_ALL_ON)
    `uvm_object_utils_end

    //-------------------------------------------------------------------------
    // Constraints
    //-------------------------------------------------------------------------

    // Default: zero-wait so a bare sequence still makes forward progress
    constraint c_ready_delay_default {
        soft ready_delay == 0;
        ready_delay <= 16;              // keep directed randomization bounded
    }

    // Default: successful transfer
    constraint c_resp_default {
        soft resp == AHB_RESP_OKAY;
    }

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(string name = "ahb_slave_response");
        super.new(name);
        resp = AHB_RESP_OKAY;           // sane default for non-randomized items
    endfunction : new

    //-------------------------------------------------------------------------
    // convert2string - human-readable summary for debug
    //-------------------------------------------------------------------------
    function string convert2string();
        return $sformatf("SLAVE_RESP: ready_delay=%0d resp=%s rdata=0x%08h",
                         ready_delay, resp.name(), rdata);
    endfunction : convert2string

endclass : ahb_slave_response