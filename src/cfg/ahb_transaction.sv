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
    rand bit                      lock;   // Always HIGH because VIP has only 1 master
    rand ahb_prot_e               prot;   // Not supported
    rand ahb_size_e               size;
    rand ahb_trans_e              trans[];
    rand ahb_dir_e                write;
    rand bit [AHB_DATA_WIDTH-1:0] wdata[];

    // Slave channel (beat-level signals)
    rand bit [AHB_DATA_WIDTH-1:0] rdata[];
    rand bit                      ready[];
    rand ahb_resp_e               resp[];

    //-------------------------------------------------------------------------
    // UVM utility macro
    //-------------------------------------------------------------------------
    `uvm_object_utils_begin(ahb_transaction)
        `uvm_field_int(                    addr,   UVM_ALL_ON)
        `uvm_field_enum(ahb_burst_e,       burst,  UVM_ALL_ON)
        `uvm_field_int(                    lock,   UVM_ALL_ON)
        `uvm_field_enum(ahb_prot_e,        prot,   UVM_ALL_ON)
        `uvm_field_enum(ahb_size_e,        size,   UVM_ALL_ON)
        `uvm_field_enum(ahb_dir_e,         write,  UVM_ALL_ON)
        `uvm_field_int(                    wdata,  UVM_ALL_ON)
        `uvm_field_int(                    rdata,  UVM_ALL_ON)
        `uvm_field_int(                    ready,  UVM_ALL_ON)
        // Note: trans[] & resp[] has no built-in macro for enum dynamic
        //       arrays, so do_copy/do_compare/do_print handle it manually.
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
    // do_copy - deep copy including enum arrays
    //-------------------------------------------------------------------------
    function void do_copy(uvm_object rhs);
        ahb_transaction rhs_t;
        super.do_copy(rhs);     // copies all `uvm_field_*` registered fields
        if (!$cast(rhs_t, rhs))
            `uvm_fatal(get_type_name(), "do_copy: cast failed")
        // Manual copy of trans[] & resp[]
        this.trans = new[rhs_t.trans.size()];
        this.resp  = new[rhs_t.resp.size()];
        foreach (rhs_t.trans[i])
            this.trans[i] = rhs_t.trans[i];
        foreach (rhs_t.resp[i])
            this.resp[i] = rhs_t.resp[i];
    endfunction : do_copy

    //-------------------------------------------------------------------------
    // do_compare - compare including enum arrays
    //-------------------------------------------------------------------------
    function bit do_compare(uvm_object rhs, uvm_comparer comparer);
        ahb_transaction rhs_t;
        bit result;
        result = super.do_compare(rhs, comparer);   // compare all registered fields
        if (!$cast(rhs_t, rhs))
            `uvm_fatal(get_type_name(), "do_compare: cast failed")
        // Compare trans[] sizes & elements
        if (this.trans.size() != rhs_t.trans.size()) begin
            `uvm_info(get_type_name(),
                      $sformatf("trans size mismatch: %0d vs %0d",
                                this.trans.size(), rhs_t.trans.size()), UVM_LOW)
            return 0;
        end
        foreach (this.trans[i]) begin
            if (this.trans[i] != rhs_t.trans[i]) begin
                `uvm_info(get_type_name(),
                          $sformatf("trans[%0d] mismatch: %s vs %s",
                                    i, this.trans[i].name(), rhs_t.trans[i].name()), UVM_LOW)
                result = 0;
            end
        end
        // Compare resp[] sizes & elements
        if (this.resp.size() != rhs_t.resp.size()) begin
            `uvm_info(get_type_name(),
                      $sformatf("resp size mismatch: %0d vs %0d",
                                this.resp.size(), rhs_t.resp.size()), UVM_LOW)
            return 0;
        end
        foreach (this.resp[i]) begin
            if (this.resp[i] != rhs_t.resp[i]) begin
                `uvm_info(get_type_name(),
                          $sformatf("resp[%0d] mismatch: %s vs %s",
                                    i, this.resp[i].name(), rhs_t.resp[i].name()), UVM_LOW)
                result = 0;
            end
        end
        return result;
    endfunction : do_compare

    //-------------------------------------------------------------------------
    // do_print - print UVM output
    //-------------------------------------------------------------------------
    function void do_print(uvm_printer printer);
        super.do_print(printer);    // prints all registered fields
        // Manually print trans[]
        printer.print_generic("trans.size()", "int", $bits(trans.size()),
                              $sformatf("%0d", trans.size()));
        foreach (trans[i])
            printer.print_generic($sformatf("trans[%0d]", i), "axi4_resp_e", 2,
                                  trans[i].name());
        // Manually print resp[]
        printer.print_generic("resp.size()", "int", $bits(resp.size()),
                              $sformatf("%0d", resp.size()));
        foreach (resp[i])
            printer.print_generic($sformatf("resp[%0d]", i), "axi4_resp_e", 2,
                                  resp[i].name());
    endfunction : do_print

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