//=============================================================================
// File        : ahb_seq_pkg.sv
// Project     : AMBA 3 AHB-Lite VIP
// Author      : Huy Le
// Description : Sequence library package for the AHB-Lite VIP. Imports
//               ahb_pkg (transaction, types, sequencers) and includes all
//               master-side and slave-side sequences.
//=============================================================================

`ifndef AHB_SEQ_PKG_INCLUDED_
`define AHB_SEQ_PKG_INCLUDED_

package ahb_seq_pkg;

    //-------------------------------------------------------------------------
    // Imports & Macros
    //-------------------------------------------------------------------------
    `include "uvm_macros.svh"
    import uvm_pkg::*;
    import ahb_pkg::*;

    //-------------------------------------------------------------------------
    // Master-sequence Library  (src/mst_seq/)
    //-------------------------------------------------------------------------
    `include "mst_seq/ahb_base_seq.sv"
    `include "mst_seq/ahb_sanity_seq.sv"
    `include "mst_seq/ahb_read_after_write_seq.sv"

    //-------------------------------------------------------------------------
    // Slave-sequence Library  (src/slv_seq/)
    //   Empty: the slave agent runs in auto-response mode (auto_gen_resp = 1).
    //   Add slave sequences here when driving ahb_slave_response items.
    //-------------------------------------------------------------------------

endpackage : ahb_seq_pkg

`endif // AHB_SEQ_PKG_INCLUDED_