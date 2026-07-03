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
    rand ahb_trans_e              trans[];
    rand ahb_dir_e                write;     // 0: Read, 1: Write
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
    // Constraints (IHI0033A compliant)
    //-------------------------------------------------------------------------

    // Wdata array size must match burst length
    //   SINGLE = 1, INCRx/WRAPx = 4/8/16, INCR = [1:256]
    constraint c_wdata_size {
        if (burst == AHB_BURST_SINGLE) {
            wdata.size() == 1;
        } else if (burst == AHB_BURST_WRAP4 || burst == AHB_BURST_INCR4) {
            wdata.size() == 4;
        } else if (burst == AHB_BURST_WRAP8 || burst == AHB_BURST_INCR8) {
            wdata.size() == 8;
        } else if (burst == AHB_BURST_WRAP16 || burst == AHB_BURST_INCR16) {
            wdata.size() == 16;
        } else {
            // AHB_BURST_INCR: unspecified length
            wdata.size() inside {[1:256]};
        }
    }

    // Trans array size must match wdata array size (1 entry per beat)
    constraint c_trans_size {
        trans.size() == wdata.size();
    }

    // Slave response arrays must match beat count
    constraint c_rdata_size {
        rdata.size() == wdata.size();
    }

    constraint c_ready_size {
        ready.size() == wdata.size();
    }

    constraint c_resp_size {
        resp.size() == wdata.size();
    }

    // Burst size must not exceed data bus width
    // 2^size <= DATA_WIDTH / 8  (Ch.3)
    constraint c_size_max {
        (1 << size) <= (AHB_DATA_WIDTH / 8);
    }

    // Start address must be aligned to transfer size (Ch.3)
    //   HADDR must be aligned to 2^HSIZE bytes
    constraint c_addr_align {
        (addr % (1 << size)) == 0;
    }

    // Incrementing burst must not cross 1KB boundary (Ch.3)
    //   end_addr = addr + (num_beats - 1) * 2^HSIZE
    //   addr[31:10] must equal end_addr[31:10]
    constraint c_1kb_boundary {
        (burst == AHB_BURST_INCR4) ->
            (addr[AHB_ADDR_WIDTH-1:10] ==
             ((addr + (4  - 1) * (1 << size))[AHB_ADDR_WIDTH-1:10]));
        (burst == AHB_BURST_INCR8) ->
            (addr[AHB_ADDR_WIDTH-1:10] ==
             ((addr + (8  - 1) * (1 << size))[AHB_ADDR_WIDTH-1:10]));
        (burst == AHB_BURST_INCR16) ->
            (addr[AHB_ADDR_WIDTH-1:10] ==
             ((addr + (16 - 1) * (1 << size))[AHB_ADDR_WIDTH-1:10]));
        // INCR (undefined length): cannot constrain at randomization,
        // checked at runtime by SVA
    }

    // Single master — HMASTLOCK not needed (no arbitration)
    constraint c_lock_fixed {
        lock == 1'b0;
    }

    // HPROT not supported — fixed to default
    constraint c_prot_fixed {
        prot == AHB_PROT_DEFAULT;
    }

    // Default slave responses
    constraint c_resp_default {
        foreach (resp[i]) soft resp[i] == AHB_RESP_OKAY;
    }

    // Default ready: no wait states
    constraint c_ready_default {
        foreach (ready[i]) soft ready[i] == 1'b1;
    }

    // Default: first beat NONSEQ, subsequent beats SEQ (Ch.3)
    constraint c_trans_default {
        foreach (trans[i]) {
            if (i == 0) {
                soft trans[i] == AHB_TRANS_NONSEQ;
            } else {
                soft trans[i] == AHB_TRANS_SEQ;
            }
        }
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
    endfunction : new

    //-------------------------------------------------------------------------
    // Helper: get number of beats for the current burst type
    //-------------------------------------------------------------------------
    function int get_num_beats();
        case (burst)
            AHB_BURST_SINGLE:                   return 1;
            AHB_BURST_WRAP4,  AHB_BURST_INCR4:  return 4;
            AHB_BURST_WRAP8,  AHB_BURST_INCR8:  return 8;
            AHB_BURST_WRAP16, AHB_BURST_INCR16: return 16;
            AHB_BURST_INCR:                     return wdata.size();
            default:                            return 1;
        endcase
    endfunction : get_num_beats

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
            printer.print_generic($sformatf("trans[%0d]", i), "ahb_trans_e", 2,
                                  trans[i].name());
        // Manually print resp[]
        printer.print_generic("resp.size()", "int", $bits(resp.size()),
                              $sformatf("%0d", resp.size()));
        foreach (resp[i])
            printer.print_generic($sformatf("resp[%0d]", i), "ahb_resp_e", 1,
                                  resp[i].name());
    endfunction : do_print

    //-------------------------------------------------------------------------
    // convert2string - human-readable transaction summary for debug
    //-------------------------------------------------------------------------
    function string convert2string();
        string s;
        int num_beats;
        num_beats = get_num_beats();
        s = $sformatf("\n---------- AHB-Lite Transaction ----------");
        s = {s, $sformatf("\n DIR    = %s",     write.name())};
        s = {s, $sformatf("\n ADDR   = 0x%08h", addr)};
        s = {s, $sformatf("\n BURST  = %s",     burst.name())};
        s = {s, $sformatf("\n SIZE   = %s (%0d bytes/beat)", size.name(), 1 << size)};
        s = {s, $sformatf("\n LOCK   = %0b",    lock)};
        s = {s, $sformatf("\n PROT   = %s",     prot.name())};
        s = {s, $sformatf("\n BEATS  = %0d",    num_beats)};
        for (int i = 0; i < num_beats; i++) begin
            s = {s, $sformatf("\n   [%0d] TRANS=%s", i,
                              (i < trans.size()) ? trans[i].name() : "N/A")};
            if (write == AHB_WRITE)
                s = {s, $sformatf("  WDATA=0x%08h",
                                  (i < wdata.size()) ? wdata[i] : '0)};
            else
                s = {s, $sformatf("  RDATA=0x%08h  RESP=%s",
                                  (i < rdata.size()) ? rdata[i] : '0,
                                  (i < resp.size())  ? resp[i].name() : "N/A")};
        end
        s = {s, "\n------------------------------------------\n"};
        return s;
    endfunction : convert2string

endclass : ahb_transaction