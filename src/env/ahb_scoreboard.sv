//==============================================================================
// File        : ahb_scoreboard.sv
// Project     : AMBA 3 AHB-Lite VIP
// Author      : Huy Le
// Description : AHB-Lite scoreboard:
//   1. Master vs slave monitor streams, compared in order.
//   2. Byte reference memory from the master stream: WRITE stores, READ
//      checks. OKAY beats only; unwritten locations skipped.
//==============================================================================

// write_master() / write_slave()
`uvm_analysis_imp_decl(_master)
`uvm_analysis_imp_decl(_slave)

class ahb_scoreboard extends uvm_scoreboard;

    `uvm_component_utils(ahb_scoreboard)

    //-------------------------------------------------------------------------
    // Analysis exports
    //-------------------------------------------------------------------------
    uvm_analysis_imp_master #(ahb_transaction, ahb_scoreboard) master_export;
    uvm_analysis_imp_slave  #(ahb_transaction, ahb_scoreboard) slave_export;

    //-------------------------------------------------------------------------
    // Master/slave FIFOs for in-order compare
    //-------------------------------------------------------------------------
    ahb_transaction master_q[$];
    ahb_transaction slave_q[$];

    //-------------------------------------------------------------------------
    // Byte reference memory
    //-------------------------------------------------------------------------
    localparam int unsigned BUS_BYTES = AHB_DATA_WIDTH / 8;
    bit [7:0] ref_mem [bit [AHB_ADDR_WIDTH-1:0]];

    //-------------------------------------------------------------------------
    // Statistics
    //-------------------------------------------------------------------------
    // Master/slave compare
    int unsigned num_compared;
    int unsigned num_matched;
    int unsigned num_mismatched;
    // Reference memory
    int unsigned num_wr_bytes;      // bytes written
    int unsigned num_rd_checked;    // read bytes checked
    int unsigned num_rd_uninit;     // read bytes not written before (skipped)
    int unsigned num_rd_mismatch;   // read byte mismatches

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction : new

    //-------------------------------------------------------------------------
    // Build phase
    //-------------------------------------------------------------------------
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        master_export = new("master_export", this);
        slave_export  = new("slave_export", this);
    endfunction : build_phase

    //-------------------------------------------------------------------------
    // Analysis callbacks - master: both checks; slave: compare only
    //-------------------------------------------------------------------------
    function void write_master(ahb_transaction t);
        update_ref_model(t);
        master_q.push_back(t);
        try_compare();
    endfunction : write_master

    function void write_slave(ahb_transaction t);
        slave_q.push_back(t);
        try_compare();
    endfunction : write_slave

    //=========================================================================
    // Check 1 - master vs slave
    //=========================================================================

    //-------------------------------------------------------------------------
    // try_compare - compare FIFO fronts while both are non-empty
    //-------------------------------------------------------------------------
    function void try_compare();
        ahb_transaction m_tr;
        ahb_transaction s_tr;

        while (master_q.size() > 0 && slave_q.size() > 0) begin
            m_tr = master_q.pop_front();
            s_tr = slave_q.pop_front();
            num_compared++;

            if (m_tr.compare(s_tr)) begin
                num_matched++;
                `uvm_info(get_type_name(),
                          $sformatf("MATCH #%0d: [%s] HADDR=0x%08h %s %0d beats",
                                    num_compared, m_tr.write.name(), m_tr.addr,
                                    m_tr.burst.name(), m_tr.get_num_beats()), UVM_HIGH)
            end else begin
                num_mismatched++;
                `uvm_error(get_type_name(),
                           $sformatf("MISMATCH #%0d:\n--- MASTER ---%s\n--- SLAVE ---%s",
                                     num_compared, m_tr.convert2string(),
                                     s_tr.convert2string()))
            end
        end
    endfunction : try_compare

    //=========================================================================
    // Check 2 - reference memory
    //=========================================================================

    //-------------------------------------------------------------------------
    // beat_address - address of beat i (INCR / WRAP)
    //-------------------------------------------------------------------------
    function bit [AHB_ADDR_WIDTH-1:0] beat_address(ahb_transaction t, int i);
        int unsigned bytes = 1 << t.size;
        int unsigned len   = t.get_num_beats();
        bit [AHB_ADDR_WIDTH-1:0] base;
        case (t.burst)
            AHB_BURST_WRAP4, AHB_BURST_WRAP8, AHB_BURST_WRAP16: begin
                int unsigned wrap_bytes = len * bytes;
                base = t.addr - (t.addr % wrap_bytes);
                return base + ((t.addr + i * bytes) % wrap_bytes);
            end
            default: begin                              // SINGLE, INCR*
                return t.addr + i * bytes;
            end
        endcase
    endfunction : beat_address

    //-------------------------------------------------------------------------
    // update_ref_model - apply one transaction to the reference memory
    //-------------------------------------------------------------------------
    function void update_ref_model(ahb_transaction t);
        int unsigned bytes;
        bit [AHB_ADDR_WIDTH-1:0] a;
        int unsigned lane;
        bit [7:0] exp_b, got_b;

        bytes = 1 << t.size;

        foreach (t.trans[i]) begin
            // Skip ERROR beats
            if (i < t.resp.size() && t.resp[i] == AHB_RESP_ERROR) continue;

            a    = beat_address(t, i);
            lane = a % BUS_BYTES;

            for (int k = 0; k < bytes; k++) begin
                if (t.write == AHB_WRITE) begin
                    ref_mem[a + k] = t.wdata[i][(lane + k)*8 +: 8];
                    num_wr_bytes++;
                end else begin
                    if (!ref_mem.exists(a + k)) begin
                        num_rd_uninit++;
                        continue;
                    end
                    exp_b = ref_mem[a + k];
                    got_b = t.rdata[i][(lane + k)*8 +: 8];
                    num_rd_checked++;
                    if (got_b !== exp_b) begin
                        num_rd_mismatch++;
                        `uvm_error(get_type_name(),
                                   $sformatf("REF-MEM read mismatch @0x%08h: exp=0x%02h got=0x%02h (beat %0d, burst %s)",
                                             a + k, exp_b, got_b, i, t.burst.name()))
                    end
                end
            end
        end
    endfunction : update_ref_model

    //=========================================================================
    // End-of-test reporting
    //=========================================================================

    //-------------------------------------------------------------------------
    // Check phase - no unmatched transactions
    //-------------------------------------------------------------------------
    function void check_phase(uvm_phase phase);
        super.check_phase(phase);
        if (master_q.size() != 0)
            `uvm_error(get_type_name(),
                       $sformatf("%0d master transaction(s) left unmatched at end of test",
                                 master_q.size()))
        if (slave_q.size() != 0)
            `uvm_error(get_type_name(),
                       $sformatf("%0d slave transaction(s) left unmatched at end of test",
                                 slave_q.size()))
    endfunction : check_phase

    //-------------------------------------------------------------------------
    // Report phase
    //-------------------------------------------------------------------------
    function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        `uvm_info(get_type_name(),
                  $sformatf("Passthrough : compared=%0d matched=%0d mismatched=%0d",
                            num_compared, num_matched, num_mismatched),
                  (num_mismatched == 0) ? UVM_LOW : UVM_NONE)
        `uvm_info(get_type_name(),
                  $sformatf("Ref-memory  : wr_bytes=%0d rd_checked=%0d rd_uninit=%0d rd_mismatch=%0d",
                            num_wr_bytes, num_rd_checked, num_rd_uninit, num_rd_mismatch),
                  (num_rd_mismatch == 0) ? UVM_LOW : UVM_NONE)
    endfunction : report_phase

endclass : ahb_scoreboard