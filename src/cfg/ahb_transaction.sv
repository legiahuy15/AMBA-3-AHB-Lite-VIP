//==============================================================================
// File        : ahb_transaction.sv
// Project     : AMBA 3 AHB-Lite VIP
// Author      : Huy Le
// Description : AHB-Lite sequence item (transaction object).
//               Contains all fields for a single AHB-Lite read/write transaction,
//               constraints per IHI0033A spec, and utility methods for debug.
//               This file is `included inside ahb_pkg.sv.
//==============================================================================

class ahb_transaction extends uvm_sequence_item;

    //-------------------------------------------------------------------------
    // Transaction fields
    //-------------------------------------------------------------------------

    // Master channel
    rand bit [AHB_ADDR_WIDTH-1:0] addr;
    rand ahb_burst_e              burst;
    rand bit                      lock;
    rand ahb_prot_e               prot;
    rand ahb_size_e               size;
    rand ahb_trans_e              trans;    // HTRANS (NONSEQ/IDLE)
    rand bit                      write;    // 0: read - 1: write
    rand bit [AHB_DATA_WIDTH-1:0] data[];   // 1 entry/beat
    rand int unsigned             num_busy_cycles[]; // BUSY cycles to insert after each beat

    // Slave channel (beat-level signals)
    rand bit [AHB_DATA_WIDTH-1:0] rdata[];
    rand bit                      resp[];            // 0:OKAY - 1:ERROR
    rand int unsigned             num_wait_states[]; // cycles HREADY=0

    // Bus completion event - triggered by driver when final beat completes.
    // Sequences can wait on this to implement back-pressure / ordering control.
    ahb_event_wrapper             done_event;

    //-------------------------------------------------------------------------
    // UVM utility macro
    //-------------------------------------------------------------------------
    `uvm_object_utils_begin(ahb_transaction)
        `uvm_field_int(                    addr,   UVM_ALL_ON)
        `uvm_field_enum(ahb_burst_e,       burst,  UVM_ALL_ON)
        `uvm_field_int(                    lock,   UVM_ALL_ON)
        `uvm_field_enum(ahb_prot_e,        prot,   UVM_ALL_ON)
        `uvm_field_enum(ahb_size_e,        size,   UVM_ALL_ON)
        `uvm_field_enum(ahb_trans_e,       trans,  UVM_ALL_ON)
        `uvm_field_int(                    write,  UVM_ALL_ON)
        `uvm_field_array_int(              data,   UVM_ALL_ON)
        `uvm_field_array_int(              num_busy_cycles, UVM_ALL_ON)
        `uvm_field_array_int(              rdata,  UVM_ALL_ON)
        `uvm_field_array_int(              resp,   UVM_ALL_ON)
        `uvm_field_array_int(              num_wait_states, UVM_ALL_ON)
    `uvm_object_utils_end

    //-------------------------------------------------------------------------
    // Constraints
    //-------------------------------------------------------------------------

    // Data array size must match burst length
    //   SINGLE = 1, INCRx/WRAPx = 4/8/16, INCR = [1:256]
    constraint c_data_size {
        if (burst == AHB_BURST_SINGLE) {
            data.size() == 1;
        } else if (burst == AHB_BURST_WRAP4 || burst == AHB_BURST_INCR4) {
            data.size() == 4;
        } else if (burst == AHB_BURST_WRAP8 || burst == AHB_BURST_INCR8) {
            data.size() == 8;
        } else if (burst == AHB_BURST_WRAP16 || burst == AHB_BURST_INCR16) {
            data.size() == 16;
        } else {
            // AHB_BURST_INCR: unspecified length
            data.size() inside {[1:256]};
        }
    }

    // Busy-cycles array size must match data array size (1 entry per beat)
    constraint c_busy_size {
        num_busy_cycles.size() == data.size();
    }

    // Burst size must not exceed data bus width
    // 2^size <= DATA_WIDTH / 8
    constraint c_size_max {
        (1 << size) <= (AHB_DATA_WIDTH / 8);
    }

    // Start address must be aligned to transfer size (2^HSIZE bytes)
    constraint c_addr_align {
        (addr % (1 << size)) == 0;
    }

    // WRAP burst: start address must be aligned to wrap boundary
    //   boundary = num_beats * 2^HSIZE
    constraint c_wrap_align {
        (burst == AHB_BURST_WRAP4)  -> (addr % (4  * (1 << size))) == 0;
        (burst == AHB_BURST_WRAP8)  -> (addr % (8  * (1 << size))) == 0;
        (burst == AHB_BURST_WRAP16) -> (addr % (16 * (1 << size))) == 0;
    }

    constraint c_resp_default {
        foreach (resp[i]) soft resp[i] == 1'b0;
    }

    // Default: NONSEQ (real transfer), no BUSY insertion
    constraint c_trans_default {
        trans == AHB_TRANS_NONSEQ;
    }

    constraint c_busy_default {
        foreach (num_busy_cycles[i]) soft num_busy_cycles[i] == 0;
    }

    // Default distribution: favour common burst types
    constraint c_burst_dist {
        burst dist {
            AHB_BURST_SINGLE := 40,
            AHB_BURST_INCR   := 15,
            AHB_BURST_INCR4  := 15,
            AHB_BURST_INCR8  := 10,
            AHB_BURST_INCR16 := 5,
            AHB_BURST_WRAP4  := 5,
            AHB_BURST_WRAP8  := 5,
            AHB_BURST_WRAP16 := 5
        };
    }

    // Default direction distribution
    constraint c_dir_dist {
        write dist {0 := 50, 1 := 50};
    }

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(string name = "ahb_transaction");
        super.new(name);
        done_event = new;
    endfunction : new

    //-------------------------------------------------------------------------
    // convert2string - human-readable transaction summary for debug
    //-------------------------------------------------------------------------
    function string convert2string();
        string s;
        s = $sformatf("\n---------- AHB-Lite Transaction ----------");
        s = {s, $sformatf("\n DIR    = %s",     write ? "WRITE" : "READ")};
        s = {s, $sformatf("\n ADDR   = 0x%08h", addr)};
        s = {s, $sformatf("\n BURST  = %s",     burst.name())};
        s = {s, $sformatf("\n SIZE   = %s (%0d bytes/beat)", size.name(), 1 << size)};
        s = {s, $sformatf("\n LOCK   = %0b",    lock)};
        s = {s, $sformatf("\n PROT   = %s",     prot.name())};
        s = {s, $sformatf("\n BEATS  = %0d",    data.size())};
        s = {s, $sformatf("\n TRANS  = %s",     trans.name())};
        s = {s, $sformatf("\n DATA[%0d] = {",   data.size())};
        foreach (data[i]) begin
            if (write)
                s = {s, $sformatf("\n   [%0d] WDATA=0x%08h  BUSY=%0d",
                                  i, data[i],
                                  (i < num_busy_cycles.size()) ? num_busy_cycles[i] : 0)};
            else
                s = {s, $sformatf("\n   [%0d] RDATA=0x%08h  RESP=%s  WAITS=%0d  BUSY=%0d",
                                  i,
                                  (i < rdata.size()) ? rdata[i] : '0,
                                  (i < resp.size())  ? (resp[i] ? "ERROR" : "OKAY") : "N/A",
                                  (i < num_wait_states.size()) ? num_wait_states[i] : 0,
                                  (i < num_busy_cycles.size()) ? num_busy_cycles[i] : 0)};
        end
        s = {s, "\n }"};
        s = {s, "\n------------------------------------------\n"};
        return s;
    endfunction : convert2string

endclass : ahb_transaction