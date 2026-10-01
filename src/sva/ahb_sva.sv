//=============================================================================
// File        : ahb_sva.sv
// Project     : AMBA 3 AHB-Lite VIP
// Author      : Huy Le
// Description : AHB-Lite protocol assertions and covers (IHI0033A).
//               Instantiated in tb_top.
//=============================================================================

`timescale 1ns/1ps

module ahb_sva #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32
)(
    input logic                  clk,
    input logic                  rst_n,
    // Master signals
    input logic [ADDR_WIDTH-1:0] HADDR,
    input logic [2:0]            HBURST,
    input logic                  HMASTLOCK,
    input logic [3:0]            HPROT,
    input logic [2:0]            HSIZE,
    input logic [1:0]            HTRANS,
    input logic [DATA_WIDTH-1:0] HWDATA,
    input logic                  HWRITE,
    // Slave signals
    input logic [DATA_WIDTH-1:0] HRDATA,
    input logic                  HREADY,
    input logic                  HRESP
);

    //-------------------------------------------------------------------------
    // Imports & Macros
    //-------------------------------------------------------------------------
    import uvm_pkg::*;
    `include "uvm_macros.svh"

    // HTRANS encoding
    localparam [1:0] IDLE   = 2'b00;
    localparam [1:0] BUSY   = 2'b01;
    localparam [1:0] NONSEQ = 2'b10;
    localparam [1:0] SEQ    = 2'b11;

    // HBURST encoding
    localparam [2:0] SINGLE = 3'b000;
    localparam [2:0] INCR   = 3'b001;
    localparam [2:0] WRAP4  = 3'b010;
    localparam [2:0] INCR4  = 3'b011;
    localparam [2:0] WRAP8  = 3'b100;
    localparam [2:0] INCR8  = 3'b101;
    localparam [2:0] WRAP16 = 3'b110;
    localparam [2:0] INCR16 = 3'b111;

    // Bytes per beat = 2^HSIZE
    wire [31:0] bytes_per_beat = (32'd1 << HSIZE);

    // Active transfer = NONSEQ or SEQ
    wire is_active_transfer = (HTRANS == NONSEQ) || (HTRANS == SEQ);

    //-------------------------------------------------------------------------
    // SIGNAL INTEGRITY
    //-------------------------------------------------------------------------

    // HTRANS not X/Z
    property p_htrans_known;
        @(posedge clk) disable iff (!rst_n)
        !$isunknown(HTRANS);
    endproperty
    HTRANS_KNOWN: assert property (p_htrans_known)
        else `uvm_error("AHB_SVA", "HTRANS is X/Z out of reset")

    // Address/control not X/Z during an active transfer
    property p_active_control_known;
        @(posedge clk) disable iff (!rst_n)
        is_active_transfer |-> !$isunknown({HADDR, HWRITE, HSIZE, HBURST});
    endproperty
    ACTIVE_CONTROL_KNOWN: assert property (p_active_control_known)
        else `uvm_error("AHB_SVA", "HADDR/HWRITE/HSIZE/HBURST is X/Z during active transfer")

    // HREADY/HRESP not X/Z
    property p_resp_known;
        @(posedge clk) disable iff (!rst_n)
        !$isunknown({HREADY, HRESP});
    endproperty
    RESP_KNOWN: assert property (p_resp_known)
        else `uvm_error("AHB_SVA", "HREADY/HRESP is X/Z out of reset")

    //-------------------------------------------------------------------------
    // WAIT STATES (HREADY=0)
    //-------------------------------------------------------------------------

    // Address/control stable during wait (non-IDLE). Exceptions: INCR
    // BUSY -> NONSEQ/IDLE, ERROR -> IDLE
    property p_addr_ctrl_stable_during_wait;
        @(posedge clk) disable iff (!rst_n)
        (!HREADY && HTRANS != IDLE) |=>
            ($past(HTRANS) == BUSY && $past(HBURST) == INCR &&
             (HTRANS == IDLE || HTRANS == NONSEQ)) ||
            ($past(HRESP) == 1'b1 && HTRANS == IDLE) ||
            ($stable(HADDR) && $stable(HWRITE) && $stable(HSIZE) && $stable(HBURST));
    endproperty
    ADDR_CTRL_STABLE_DURING_WAIT: assert property (p_addr_ctrl_stable_during_wait)
        else `uvm_error("AHB_SVA", "HADDR/HWRITE/HSIZE/HBURST changed during wait state (HREADY=0)")

    // NONSEQ/SEQ stable during wait. Exception: ERROR -> IDLE
    property p_htrans_stable_during_wait;
        @(posedge clk) disable iff (!rst_n)
        (!HREADY && is_active_transfer) |=>
            ($stable(HTRANS) ||
             ($past(HRESP) == 1'b1 && HTRANS == IDLE));
    endproperty
    HTRANS_STABLE_DURING_WAIT: assert property (p_htrans_stable_during_wait)
        else `uvm_error("AHB_SVA", "HTRANS changed during wait state (NONSEQ/SEQ must remain stable)")

    // BUSY during wait -> BUSY/SEQ; INCR also NONSEQ/IDLE; ERROR -> IDLE
    property p_busy_wait_transition;
        @(posedge clk) disable iff (!rst_n)
        (!HREADY && HTRANS == BUSY) |=>
            (HTRANS == BUSY || HTRANS == SEQ ||
             ($past(HBURST) == INCR && (HTRANS == NONSEQ || HTRANS == IDLE)) ||
             ($past(HRESP) == 1'b1 && HTRANS == IDLE));
    endproperty
    BUSY_WAIT_TRANSITION: assert property (p_busy_wait_transition)
        else `uvm_error("AHB_SVA", "BUSY changed to illegal type during wait")

    // Last accepted transfer was an active write
    logic in_write_data_phase;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            in_write_data_phase <= 1'b0;
        else if (HREADY)
            in_write_data_phase <= (is_active_transfer && HWRITE);
    end

    // HWDATA stable during wait in a write data phase
    property p_wdata_stable_during_wait;
        @(posedge clk) disable iff (!rst_n)
        (!HREADY && in_write_data_phase) |=> ($stable(HWDATA));
    endproperty
    WDATA_STABLE_DURING_WAIT: assert property (p_wdata_stable_during_wait)
        else `uvm_error("AHB_SVA", "HWDATA changed during wait state in write data phase")

    // HWDATA not X/Z in a write data phase
    property p_wdata_known;
        @(posedge clk) disable iff (!rst_n)
        in_write_data_phase |-> !$isunknown(HWDATA);
    endproperty
    WDATA_KNOWN: assert property (p_wdata_known)
        else `uvm_error("AHB_SVA", "HWDATA is X/Z during write data phase")

    //-------------------------------------------------------------------------
    // ADDRESS & SIZE
    //-------------------------------------------------------------------------

    // HADDR aligned to 2^HSIZE
    property p_addr_aligned;
        @(posedge clk) disable iff (!rst_n)
        is_active_transfer |-> ((HADDR % bytes_per_beat) == 0);
    endproperty
    ADDR_ALIGNED: assert property (p_addr_aligned)
        else `uvm_error("AHB_SVA",
            $sformatf("HADDR=0x%08h not aligned to HSIZE=%0d (need %0d-byte alignment)", HADDR, HSIZE, bytes_per_beat))

    // 2^HSIZE <= bus width
    property p_size_max;
        @(posedge clk) disable iff (!rst_n)
        is_active_transfer |-> (bytes_per_beat <= (DATA_WIDTH / 8));
    endproperty
    SIZE_MAX: assert property (p_size_max)
        else `uvm_error("AHB_SVA",
            $sformatf("HSIZE=%0d exceeds bus width (%0d bytes)", HSIZE, DATA_WIDTH/8))

    // INCR bursts do not cross a 1KB boundary
    property p_incr_1kb_boundary;
        @(posedge clk) disable iff (!rst_n)
        (HREADY && HTRANS == SEQ &&
         (HBURST == INCR || HBURST == INCR4 || HBURST == INCR8 || HBURST == INCR16))
        |-> (HADDR[ADDR_WIDTH-1:10] == $past(HADDR[ADDR_WIDTH-1:10]));
    endproperty
    INCR_1KB_BOUNDARY: assert property (p_incr_1kb_boundary)
        else `uvm_error("AHB_SVA",
            $sformatf("INCR burst crossed 1KB boundary: 0x%08h -> 0x%08h", $past(HADDR), HADDR))

    //-------------------------------------------------------------------------
    // BURST RULES
    //-------------------------------------------------------------------------

    // HBURST/HSIZE/HWRITE constant within a burst
    property p_ctrl_stable_in_burst;
        @(posedge clk) disable iff (!rst_n)
        (HREADY && (HTRANS == SEQ || HTRANS == BUSY))
        |-> ($stable(HBURST) && $stable(HSIZE) && $stable(HWRITE));
    endproperty
    CTRL_STABLE_IN_BURST: assert property (p_ctrl_stable_in_burst)
        else `uvm_error("AHB_SVA", "HBURST, HSIZE, or HWRITE changed mid-burst")

    // HPROT constant within a burst
    property p_hprot_stable_in_burst;
        @(posedge clk) disable iff (!rst_n)
        (HREADY && (HTRANS == SEQ || HTRANS == BUSY)) |-> ($stable(HPROT));
    endproperty
    HPROT_STABLE_IN_BURST: assert property (p_hprot_stable_in_burst)
        else `uvm_error("AHB_SVA", "HPROT changed mid-burst")

    // HMASTLOCK stable within a burst and during wait states (same exceptions
    // as ADDR_CTRL_STABLE_DURING_WAIT)
    property p_mastlock_addr_timing;
        @(posedge clk) disable iff (!rst_n)
        ((HREADY && (HTRANS == SEQ || HTRANS == BUSY)) ||
         (!$past(HREADY) && $past(HTRANS) != IDLE &&
          !($past(HTRANS) == BUSY && $past(HBURST) == INCR &&
            (HTRANS == IDLE || HTRANS == NONSEQ)) &&
          !($past(HRESP) == 1'b1 && HTRANS == IDLE)))
        |-> ($stable(HMASTLOCK));
    endproperty
    MASTLOCK_ADDR_TIMING: assert property (p_mastlock_addr_timing)
        else `uvm_error("AHB_SVA",
            "HMASTLOCK changed mid-burst or during a wait state (must follow address-phase timing)")

    // No BUSY with SINGLE
    property p_no_busy_for_single;
        @(posedge clk) disable iff (!rst_n)
        (HTRANS == BUSY) |-> (HBURST != SINGLE);
    endproperty
    NO_BUSY_FOR_SINGLE: assert property (p_no_busy_for_single)
        else `uvm_error("AHB_SVA", "BUSY transfer used with SINGLE burst (not allowed)")

    // Fixed-length burst: accepted BUSY -> BUSY/SEQ (excludes ERROR cancel)
    property p_busy_fixed_len_no_terminate;
        @(posedge clk) disable iff (!rst_n)
        (HREADY && HTRANS == BUSY && HRESP == 1'b0 &&
         HBURST != INCR && HBURST != SINGLE) |=>
            (HTRANS == BUSY || HTRANS == SEQ);
    endproperty
    BUSY_FIXED_LEN_NO_TERMINATE: assert property (p_busy_fixed_len_no_terminate)
        else `uvm_error("AHB_SVA",
            "Fixed-length burst terminated out of BUSY (must end with SEQ)")

    // SINGLE -> IDLE/NONSEQ
    property p_single_followed_by_idle_nonseq;
        @(posedge clk) disable iff (!rst_n)
        (HREADY && HTRANS == NONSEQ && HBURST == SINGLE) |=>
            (HTRANS == IDLE || HTRANS == NONSEQ);
    endproperty
    SINGLE_FOLLOWED_BY_IDLE_NONSEQ: assert property (p_single_followed_by_idle_nonseq)
        else `uvm_error("AHB_SVA",
            "SINGLE burst must be followed by IDLE or NONSEQ transfer")

    // Accepted IDLE -> IDLE/NONSEQ
    property p_no_seq_busy_after_idle;
        @(posedge clk) disable iff (!rst_n)
        (HTRANS == IDLE && HREADY) |=> (HTRANS == IDLE || HTRANS == NONSEQ);
    endproperty
    NO_SEQ_BUSY_AFTER_IDLE: assert property (p_no_seq_busy_after_idle)
        else `uvm_error("AHB_SVA", "SEQ/BUSY transfer appeared after an accepted IDLE transfer")

    // First transfer after reset: IDLE/NONSEQ
    property p_first_transfer_after_reset;
        @(posedge clk)
        $rose(rst_n) |-> (HTRANS == IDLE || HTRANS == NONSEQ);
    endproperty
    FIRST_TRANSFER_AFTER_RESET: assert property (p_first_transfer_after_reset)
        else `uvm_error("AHB_SVA", "First transfer after reset must be IDLE or NONSEQ")

    // HTRANS IDLE during reset, except the first edge (clocked driver)
    property p_idle_during_reset;
        @(posedge clk)
        (!rst_n && !$fell(rst_n)) |-> (HTRANS == IDLE);
    endproperty
    IDLE_DURING_RESET: assert property (p_idle_during_reset)
        else `uvm_error("AHB_SVA", "HTRANS is not IDLE during reset")

    // HREADY (= HREADYOUT) high during reset, except the first edge
    property p_readyout_high_in_reset;
        @(posedge clk)
        (!rst_n && !$fell(rst_n)) |-> (HREADY == 1'b1);
    endproperty
    READYOUT_HIGH_IN_RESET: assert property (p_readyout_high_in_reset)
        else `uvm_error("AHB_SVA", "HREADY (HREADYOUT) is not HIGH during reset")

    // INCR: HADDR += 2^HSIZE per beat (not after BUSY)
    property p_incr_addr_increment;
        @(posedge clk) disable iff (!rst_n)
        ($past(HREADY) && HTRANS == SEQ && $past(HTRANS) != BUSY &&
         (HBURST == INCR || HBURST == INCR4 || HBURST == INCR8 || HBURST == INCR16))
        |-> (HADDR == ($past(HADDR) + $past(bytes_per_beat)));
    endproperty
    INCR_ADDR_INCREMENT: assert property (p_incr_addr_increment)
        else `uvm_error("AHB_SVA",
            $sformatf("INCR address not incrementing correctly: expected 0x%08h, got 0x%08h",
                      $past(HADDR) + $past(bytes_per_beat), HADDR))

    // SEQ after BUSY keeps HADDR
    property p_addr_stable_after_busy;
        @(posedge clk) disable iff (!rst_n)
        (HTRANS == SEQ && $past(HTRANS) == BUSY)
        |-> ($stable(HADDR));
    endproperty
    ADDR_STABLE_AFTER_BUSY: assert property (p_addr_stable_after_busy)
        else `uvm_error("AHB_SVA", "HADDR changed after BUSY (must hold next-beat address)")

    // WRAP: address bits above the wrap boundary (beats * 2^HSIZE) constant

    // WRAP4: boundary = 4 * 2^HSIZE
    property p_wrap4_upper_stable;
        @(posedge clk) disable iff (!rst_n)
        (HREADY && HTRANS == SEQ && HBURST == WRAP4)
        |-> ((HADDR & ~((4 * bytes_per_beat) - 1)) ==
             ($past(HADDR) & ~((4 * $past(bytes_per_beat)) - 1)));
    endproperty
    WRAP4_UPPER_STABLE: assert property (p_wrap4_upper_stable)
        else `uvm_error("AHB_SVA",
            $sformatf("WRAP4 upper address changed: 0x%08h -> 0x%08h", $past(HADDR), HADDR))

    // WRAP8: boundary = 8 * 2^HSIZE
    property p_wrap8_upper_stable;
        @(posedge clk) disable iff (!rst_n)
        (HREADY && HTRANS == SEQ && HBURST == WRAP8)
        |-> ((HADDR & ~((8 * bytes_per_beat) - 1)) ==
             ($past(HADDR) & ~((8 * $past(bytes_per_beat)) - 1)));
    endproperty
    WRAP8_UPPER_STABLE: assert property (p_wrap8_upper_stable)
        else `uvm_error("AHB_SVA",
            $sformatf("WRAP8 upper address changed: 0x%08h -> 0x%08h", $past(HADDR), HADDR))

    // WRAP16: boundary = 16 * 2^HSIZE
    property p_wrap16_upper_stable;
        @(posedge clk) disable iff (!rst_n)
        (HREADY && HTRANS == SEQ && HBURST == WRAP16)
        |-> ((HADDR & ~((16 * bytes_per_beat) - 1)) ==
             ($past(HADDR) & ~((16 * $past(bytes_per_beat)) - 1)));
    endproperty
    WRAP16_UPPER_STABLE: assert property (p_wrap16_upper_stable)
        else `uvm_error("AHB_SVA",
            $sformatf("WRAP16 upper address changed: 0x%08h -> 0x%08h", $past(HADDR), HADDR))

    //-------------------------------------------------------------------------
    // SLAVE RESPONSE
    //-------------------------------------------------------------------------

    // ERROR: (HRESP=1, HREADY=0) then (HRESP=1, HREADY=1)
    property p_error_two_cycle;
        @(posedge clk) disable iff (!rst_n)
        (HRESP == 1'b1 && !HREADY) |=> (HRESP == 1'b1 && HREADY);
    endproperty
    ERROR_TWO_CYCLE: assert property (p_error_two_cycle)
        else `uvm_error("AHB_SVA",
            "ERROR two-cycle violated: HRESP=1,HREADY=0 must be followed by HRESP=1,HREADY=1")

    // ERROR first cycle: HREADY=0
    property p_error_first_cycle_ready_low;
        @(posedge clk) disable iff (!rst_n)
        ($rose(HRESP)) |-> (!HREADY);
    endproperty
    ERROR_FIRST_CYCLE_READY_LOW: assert property (p_error_first_cycle_ready_low)
        else `uvm_error("AHB_SVA", "ERROR response first cycle must have HREADY=LOW")

    // ERROR with HREADY=1 must follow ERROR with HREADY=0
    property p_okay_before_error;
        @(posedge clk) disable iff (!rst_n)
        (HRESP == 1'b1 && HREADY) |-> ($past(HRESP) == 1'b1 && !$past(HREADY));
    endproperty
    OKAY_BEFORE_ERROR: assert property (p_okay_before_error)
        else `uvm_error("AHB_SVA",
            "ERROR completed without a preceding ERROR/HREADY=0 cycle (wait states before ERROR must drive HRESP=OKAY)")

    // IDLE -> zero-wait OKAY
    property p_idle_okay_resp;
        @(posedge clk) disable iff (!rst_n)
        (HTRANS == IDLE && HREADY) |=> (HRESP == 1'b0 && HREADY);
    endproperty
    IDLE_OKAY_RESP: assert property (p_idle_okay_resp)
        else `uvm_warning("AHB_SVA", "Slave did not respond OKAY to IDLE transfer")

    // BUSY -> zero-wait OKAY
    property p_busy_okay_resp;
        @(posedge clk) disable iff (!rst_n)
        (HTRANS == BUSY && HREADY) |=> (HRESP == 1'b0 && HREADY);
    endproperty
    BUSY_OKAY_RESP: assert property (p_busy_okay_resp)
        else `uvm_warning("AHB_SVA", "Slave did not respond OKAY to BUSY transfer")

    //-------------------------------------------------------------------------
    // COVERAGE - transfer-type changes during wait states
    //-------------------------------------------------------------------------

    // IDLE -> NONSEQ
    C_IDLE_TO_NONSEQ_IN_WAIT: cover property (@(posedge clk) disable iff (!rst_n)
        (!HREADY && HTRANS == IDLE) |=> (HTRANS == NONSEQ));

    // BUSY -> SEQ
    C_BUSY_TO_SEQ_IN_WAIT: cover property (@(posedge clk) disable iff (!rst_n)
        (!HREADY && HTRANS == BUSY) |=> (HTRANS == SEQ));

    // BUSY -> SEQ, fixed-length burst
    C_BUSY_TO_SEQ_IN_WAIT_FIXED: cover property (@(posedge clk) disable iff (!rst_n)
        (!HREADY && HTRANS == BUSY && HBURST != INCR && HBURST != SINGLE)
        |=> (HTRANS == SEQ));

    // BUSY -> IDLE / NONSEQ (INCR)
    C_BUSY_TO_IDLE_IN_WAIT: cover property (@(posedge clk) disable iff (!rst_n)
        (!HREADY && HTRANS == BUSY && HBURST == INCR) |=> (HTRANS == IDLE));

    C_BUSY_TO_NONSEQ_IN_WAIT: cover property (@(posedge clk) disable iff (!rst_n)
        (!HREADY && HTRANS == BUSY && HBURST == INCR) |=> (HTRANS == NONSEQ));

    // BUSY held
    C_BUSY_HELD_IN_WAIT: cover property (@(posedge clk) disable iff (!rst_n)
        (!HREADY && HTRANS == BUSY) |=> (HTRANS == BUSY));

    // HADDR change on ERROR cancel
    C_ADDR_CHANGE_AFTER_ERROR: cover property (@(posedge clk) disable iff (!rst_n)
        (!HREADY && HRESP == 1'b1 && HTRANS != IDLE)
        |=> (HTRANS == IDLE && !$stable(HADDR)));

endmodule : ahb_sva