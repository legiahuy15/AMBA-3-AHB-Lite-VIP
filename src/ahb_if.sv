//==============================================================================
// File        : ahb_if.sv
// Project     : AMBA 3 AHB-Lite VIP
// Author      : Huy Le
// Description : AHB-Lite interface with address & data chanel.
//               Includes clocking blocks for master driver, slave driver,
//               and monitor to avoid race conditions.
//               Signal widths use parameters from ahb_types.sv.
//==============================================================================

`timescale 1ns/1ps

`ifndef AHB_IF_INCLUDED_
`define AHB_IF_INCLUDED_i

interface ahb_if #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32
)(
    input logic clk,
    input logic rst_n
);

    //-------------------------------------------------------------------------
    // Master signals
    //-------------------------------------------------------------------------
    logic [ADDR_WIDTH-1:0] HADDR;
    logic [2:0]            HBURST;
    logic                  HMASTLOCK;
    logic [3:0]            HPROT;
    logic [2:0]            HSIZE;
    logic [1:0]            HTRANS;
    logic [DATA_WIDTH-1:0] HWDATA;
    logic                  HWRITE;

    //-------------------------------------------------------------------------
    // Slave signals
    //-------------------------------------------------------------------------
    logic [DATA_WIDTH-1:0] HRDATA;
    logic                  HREADY;
    logic                  HRESP;

    //-------------------------------------------------------------------------
    // Clocking Block: Master Driver
    //  - Drives: HADDR, HBURST, HMASTLOCK, HPROT, HSIZE, HTRANS, HWDATA, HWRITE
    //  - Samples: HRDATA, HREADY, HWRITE
    //-------------------------------------------------------------------------
    clocking master_cb @(posedge clk);
        default input #1step output #1;
        output HADDR, HBURST, HMASTLOCK, HPROT, HSIZE, HTRANS, HWDATA, HWRITE;
        input  HRDATA, HREADY, HRESP;
    endclocking

    //-------------------------------------------------------------------------
    // Clocking Block: Slave Driver
    //  - Drives: HRDATA, HREADY, HWRITE
    //  - Samples: HADDR, HBURST, HMASTLOCK, HPROT, HSIZE, HTRANS, HWDATA, HWRITE
    //-------------------------------------------------------------------------
    clocking slave_cb @(posedge clk);
        default input #1step output #1;
        input  HADDR, HBURST, HMASTLOCK, HPROT, HSIZE, HTRANS, HWDATA, HWRITE;
        output HRDATA, HREADY, HRESP;
    endclocking


    //-------------------------------------------------------------------------
    // Clocking Block: Monitor
    //  - Samples all signals (passive observation only)
    //-------------------------------------------------------------------------
    clocking monitor_cb @(posedge clk);
        default input #1step;
        input HADDR, HBURST, HMASTLOCK, HPROT, HSIZE, HTRANS, HWDATA, HWRITE;
        input HRDATA, HREADY, HRESP;
    endclocking

    //-------------------------------------------------------------------------
    // Modports
    //-------------------------------------------------------------------------
    modport maser_mp   (clocking master_cb,  input clk, input rst_n); 
    modport slave_mp   (clocking slave_cb,   input clk, input rst_n);
    modport monitor_mp (clocking monitor_cb, input clk, input rst_n);

    endinterface : ahb_if

`endif // AHB_IF_INCLUDED_
