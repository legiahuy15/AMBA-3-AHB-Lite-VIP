//==============================================================================
// File        : ahb_slave_response.sv
// Project     : AMBA 3 AHB-Lite VIP
// Author      : Huy Le
// Description : Slave response item for one data phase: wait states, HRESP,
//               HRDATA. Sequence mode only (auto_gen_resp = 0).
//==============================================================================

class ahb_slave_response extends uvm_sequence_item;

    //-------------------------------------------------------------------------
    // Response fields (one data phase / beat)
    //-------------------------------------------------------------------------

    // Wait states before completion
    rand int unsigned             ready_delay;

    // Response (ERROR driven as two cycles)
    rand ahb_resp_e               resp;

    // HRDATA (reads only)
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

    // Default: zero-wait
    constraint c_ready_delay_default {
        soft ready_delay == 0;
        ready_delay <= 16;
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
        resp = AHB_RESP_OKAY;
    endfunction : new

    //-------------------------------------------------------------------------
    // convert2string - debug summary
    //-------------------------------------------------------------------------
    function string convert2string();
        return $sformatf("SLAVE_RESP: ready_delay=%0d resp=%s rdata=0x%08h",
                         ready_delay, resp.name(), rdata);
    endfunction : convert2string

endclass : ahb_slave_response