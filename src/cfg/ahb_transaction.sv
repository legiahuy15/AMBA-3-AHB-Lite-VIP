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
    rand ahb_trans_e              trans;
    rand bit [AHB_DATA_WIDTH-1:0] data[];   // 1 entry/beat
    rand bit                      write;    // 0:read - 1:write

    // Slave channel

