//=============================================================================
// File        : ahb_sva.sv
// Project     : AMBA 3 AHB-Lite VIP
// Author      : Huy Le
// Description : SystemVerilog Assertions for AHB-Lite protocol compliance.
//               Checks both master and slave behavior per IHI0033A spec.
//               Bind this module to the ahb_if interface instance.
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

    // Transfer type encoding
    localparam [1:0] IDLE   = 2'b00;
    localparam [1:0] BUSY   = 2'b01;
    localparam [1:0] NONSEQ = 2'b10;
    localparam [1:0] SEQ    = 2'b11;

    // Burst type encoding
    localparam [2:0] SINGLE = 3'b000;
    localparam [2:0] INCR   = 3'b001;
    localparam [2:0] WRAP4  = 3'b010;
    localparam [2:0] INCR4  = 3'b011;
    localparam [2:0] WRAP8  = 3'b100;
    localparam [2:0] INCR8  = 3'b101;
    localparam [2:0] WRAP16 = 3'b110;
    localparam [2:0] INCR16 = 3'b111;

    // Helper: bytes per beat
    wire [31:0] bytes_per_beat = (32'd1 << HSIZE);

    // Helper: is an active transfer? (NONSEQ or SEQ)
    wire is_active_transfer = (HTRANS == NONSEQ) || (HTRANS == SEQ);

    // ========================================================================
    // WAIT STATES BEHAVIOR
    // ========================================================================

    //-------------------------------------------------------------------------
    // HADDR, HWRITE, HSIZE, HBURST stable during wait states
    //   Applies for NONSEQ, SEQ, and BUSY - anything except IDLE.
    //   Exceptions:
    //   - IDLE is excluded (master may change IDLE -> NONSEQ during wait)
    //   - INCR burst: master may end burst from BUSY by transitioning
    //     to NONSEQ or IDLE even during !HREADY. In this case,
    //     address/control may change (new transfer or IDLE).
    //-------------------------------------------------------------------------
    property p_addr_ctrl_stable_during_wait;
        @(posedge clk) disable iff (!rst_n)
        (!HREADY && HTRANS != IDLE) |=>
            // Exception: ending INCR burst from BUSY state
            ($past(HTRANS) == BUSY && $past(HBURST) == INCR &&
             (HTRANS == IDLE || HTRANS == NONSEQ)) ||
            // Normal: signals must remain stable
            ($stable(HADDR) && $stable(HWRITE) && $stable(HSIZE) && $stable(HBURST));
    endproperty

    ADDR_CTRL_STABLE_DURING_WAIT: assert property (p_addr_ctrl_stable_during_wait)
        else `uvm_error("AHB_SVA", "HADDR/HWRITE/HSIZE/HBURST changed during wait state (HREADY=0)")

    //-------------------------------------------------------------------------
    // HTRANS must remain stable during wait for NONSEQ and SEQ
    //   Active transfers cannot change type while being held.
    //-------------------------------------------------------------------------
    property p_htrans_stable_during_wait;
        @(posedge clk) disable iff (!rst_n)
        (!HREADY && is_active_transfer) |=> ($stable(HTRANS));
    endproperty

    HTRANS_STABLE_DURING_WAIT: assert property (p_htrans_stable_during_wait)
        else `uvm_error("AHB_SVA", "HTRANS changed during wait state (NONSEQ/SEQ must remain stable)")

    //-------------------------------------------------------------------------
    // BUSY transition rules during wait
    //   - Fixed-length bursts: BUSY -> BUSY or SEQ
    //   - INCR (undefined length): BUSY -> BUSY, SEQ, NONSEQ, or IDLE
    //     (master may end INCR burst at any time)
    //-------------------------------------------------------------------------
    property p_busy_wait_transition;
        @(posedge clk) disable iff (!rst_n)
        (!HREADY && HTRANS == BUSY) |=>
            (HTRANS == BUSY || HTRANS == SEQ ||
             ($past(HBURST) == INCR && (HTRANS == NONSEQ || HTRANS == IDLE)));
    endproperty

    BUSY_WAIT_TRANSITION: assert property (p_busy_wait_transition)
        else `uvm_error("AHB_SVA", "BUSY changed to illegal type during wait")

    //-------------------------------------------------------------------------
    // HWDATA must remain stable during wait state in write data phase
    //   Data phase follows address phase by 1 cycle. If HREADY=0 during
    //   the data phase, HWDATA must not change.
    //-------------------------------------------------------------------------
    // Track: we are in a write data phase when previous accepted transfer
    //        was an active write
    logic in_write_data_phase;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            in_write_data_phase <= 1'b0;
        else if (HREADY)
            in_write_data_phase <= (is_active_transfer && HWRITE);
    end

    property p_wdata_stable_during_wait;
        @(posedge clk) disable iff (!rst_n)
        (!HREADY && in_write_data_phase) |=> ($stable(HWDATA));
    endproperty

    WDATA_STABLE_DURING_WAIT: assert property (p_wdata_stable_during_wait)
        else `uvm_error("AHB_SVA", "HWDATA changed during wait state in write data phase")

    // ========================================================================
    // ADDRESS & SIZE CONSTRAINTS
    // ========================================================================

    //-------------------------------------------------------------------------
    // Address alignment - HADDR must be aligned to 2^HSIZE
    //-------------------------------------------------------------------------
    property p_addr_aligned;
        @(posedge clk) disable iff (!rst_n)
        is_active_transfer |-> ((HADDR % bytes_per_beat) == 0);
    endproperty

    ADDR_ALIGNED: assert property (p_addr_aligned)
        else `uvm_error("AHB_SVA",
            $sformatf("HADDR=0x%08h not aligned to HSIZE=%0d (need %0d-byte alignment)", HADDR, HSIZE, bytes_per_beat))

    //-------------------------------------------------------------------------
    // HSIZE must not exceed data bus width
    //-------------------------------------------------------------------------
    property p_size_max;
        @(posedge clk) disable iff (!rst_n)
        is_active_transfer |-> (bytes_per_beat <= (DATA_WIDTH / 8));
    endproperty

    SIZE_MAX: assert property (p_size_max)
        else `uvm_error("AHB_SVA",
            $sformatf("HSIZE=%0d exceeds bus width (%0d bytes)", HSIZE, DATA_WIDTH/8))

    //-------------------------------------------------------------------------
    // Incrementing bursts must not cross 1KB boundary
    //   Only applies to INCR types. WRAP bursts wrap within their boundary
    //   so they never cross 1KB.
    //-------------------------------------------------------------------------
    property p_incr_1kb_boundary;
        @(posedge clk) disable iff (!rst_n)
        (HREADY && HTRANS == SEQ &&
         (HBURST == INCR || HBURST == INCR4 || HBURST == INCR8 || HBURST == INCR16))
        |-> (HADDR[ADDR_WIDTH-1:10] == $past(HADDR[ADDR_WIDTH-1:10]));
    endproperty

    INCR_1KB_BOUNDARY: assert property (p_incr_1kb_boundary)
        else `uvm_error("AHB_SVA",
            $sformatf("INCR burst crossed 1KB boundary: 0x%08h -> 0x%08h", $past(HADDR), HADDR))

    // ========================================================================
    // BURST BEHAVIOR & RULES
    // ========================================================================

    //-------------------------------------------------------------------------
    // HBURST, HSIZE, HWRITE must remain constant throughout a burst
    //   Triggered when SEQ or BUSY appears (continuation of a burst)
    //-------------------------------------------------------------------------
    property p_ctrl_stable_in_burst;
        @(posedge clk) disable iff (!rst_n)
        (HREADY && (HTRANS == SEQ || HTRANS == BUSY))
        |-> ($stable(HBURST) && $stable(HSIZE) && $stable(HWRITE));
    endproperty

    CTRL_STABLE_IN_BURST: assert property (p_ctrl_stable_in_burst)
        else `uvm_error("AHB_SVA", "HBURST, HSIZE, or HWRITE changed mid-burst")

    //-------------------------------------------------------------------------
    // BUSY transfer is NOT allowed with SINGLE burst
    //-------------------------------------------------------------------------
    property p_no_busy_for_single;
        @(posedge clk) disable iff (!rst_n)
        (HTRANS == BUSY) |-> (HBURST != SINGLE);
    endproperty

    NO_BUSY_FOR_SINGLE: assert property (p_no_busy_for_single)
        else `uvm_error("AHB_SVA", "BUSY transfer used with SINGLE burst (not allowed)")

    //-------------------------------------------------------------------------
    // SEQ transfer must NOT follow an accepted IDLE transfer
    //   After IDLE is accepted (HREADY=1), next transfer must be IDLE or NONSEQ
    //-------------------------------------------------------------------------
    property p_no_seq_after_idle;
        @(posedge clk) disable iff (!rst_n)
        (HTRANS == IDLE && HREADY) |=> (HTRANS != SEQ);
    endproperty

    NO_SEQ_AFTER_IDLE: assert property (p_no_seq_after_idle)
        else `uvm_error("AHB_SVA", "SEQ transfer appeared after an accepted IDLE transfer")

    //-------------------------------------------------------------------------
    // HTRANS must be IDLE during reset
    //-------------------------------------------------------------------------
    property p_idle_during_reset;
        @(posedge clk)
        (!rst_n) |-> (HTRANS == IDLE);
    endproperty

    IDLE_DURING_RESET: assert property (p_idle_during_reset)
        else `uvm_error("AHB_SVA", "HTRANS is not IDLE during reset")

    //-------------------------------------------------------------------------
    // INCR address must increment by 2^HSIZE between sequential beats
    //   Skip check when previous beat was BUSY (address doesn't change)
    //-------------------------------------------------------------------------
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

    //-------------------------------------------------------------------------
    // During a BUSY cycle, master must drive the address of the NEXT beat.
    //   So when SEQ follows BUSY, the address must not change.
    //-------------------------------------------------------------------------
    property p_addr_stable_after_busy;
        @(posedge clk) disable iff (!rst_n)
        (HTRANS == SEQ && $past(HTRANS) == BUSY)
        |-> ($stable(HADDR));
    endproperty

    ADDR_STABLE_AFTER_BUSY: assert property (p_addr_stable_after_busy)
        else `uvm_error("AHB_SVA", "HADDR changed after BUSY (must hold next-beat address)")

    //-------------------------------------------------------------------------
    // WRAP address: upper bits (above wrap boundary) must remain constant
    //   Check for each WRAP type individually for tool compatibility
    //-------------------------------------------------------------------------

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

    // ========================================================================
    // SLAVE RESPONSE SIGNALING
    // ========================================================================

    //-------------------------------------------------------------------------
    // ERROR response - two-cycle protocol
    //   Cycle 1: HRESP=ERROR, HREADY=LOW
    //   Cycle 2: HRESP=ERROR, HREADY=HIGH
    //-------------------------------------------------------------------------
    property p_error_two_cycle;
        @(posedge clk) disable iff (!rst_n)
        (HRESP == 1'b1 && !HREADY) |=> (HRESP == 1'b1 && HREADY);
    endproperty

    ERROR_TWO_CYCLE: assert property (p_error_two_cycle)
        else `uvm_error("AHB_SVA",
            "ERROR two-cycle violated: HRESP=1,HREADY=0 must be followed by HRESP=1,HREADY=1")

    //-------------------------------------------------------------------------
    // ERROR first cycle must have HREADY=LOW
    //   When HRESP transitions 0->1, it must be the first error cycle
    //-------------------------------------------------------------------------
    property p_error_first_cycle_ready_low;
        @(posedge clk) disable iff (!rst_n)
        ($rose(HRESP)) |-> (!HREADY);
    endproperty

    ERROR_FIRST_CYCLE_READY_LOW: assert property (p_error_first_cycle_ready_low)
        else `uvm_error("AHB_SVA", "ERROR response first cycle must have HREADY=LOW")

    //-------------------------------------------------------------------------
    // Slave must respond OKAY (zero-wait) to IDLE transfers
    //-------------------------------------------------------------------------
    property p_idle_okay_resp;
        @(posedge clk) disable iff (!rst_n)
        (HTRANS == IDLE && HREADY) |=> (HRESP == 1'b0 && HREADY);
    endproperty

    IDLE_OKAY_RESP: assert property (p_idle_okay_resp)
        else `uvm_warning("AHB_SVA", "Slave did not respond OKAY to IDLE transfer")

    //-------------------------------------------------------------------------
    // Slave must respond OKAY (zero-wait) to BUSY transfers
    //-------------------------------------------------------------------------
    property p_busy_okay_resp;
        @(posedge clk) disable iff (!rst_n)
        (HTRANS == BUSY && HREADY) |=> (HRESP == 1'b0 && HREADY);
    endproperty

    BUSY_OKAY_RESP: assert property (p_busy_okay_resp)
        else `uvm_warning("AHB_SVA", "Slave did not respond OKAY to BUSY transfer")

endmodule : ahb_sva