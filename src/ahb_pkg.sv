//=============================================================================
// File        : ahb_pkg.sv
// Project     : AMBA 3 AHB-Lite VIP
// Author      : Huy Le
// Description : Top-level SystemVerilog package for AHB-Lite VIP.
//               Imports UVM library and includes all core components:
//               transactions, sequencers, drivers, monitors, agents,
//               configs, coverage, scoreboard, and environment.
//
//               Note: ahb_if.sv (SystemVerilog interface) is NOT included
//               here - it must be compiled separately before this package.
//=============================================================================

`ifndef AHB_PKG_INCLUDED_
`define AHB_PKG_INCLUDED_

package ahb_pkg;

   //-------------------------------------------------------------------------
    // Imports & Macros
   //-------------------------------------------------------------------------
    `include "uvm_macros.svh"
    import uvm_pkg::*;

   //-------------------------------------------------------------------------
    // Core Types & Transaction Objects  (src/cfg/)
   //-------------------------------------------------------------------------
    `include "cfg/ahb_types.sv"
    `include "cfg/ahb_agent_config.sv"
    `include "cfg/ahb_transaction.sv"

   //-------------------------------------------------------------------------
    // Master-side Components  (src/mst/)
   //-------------------------------------------------------------------------
    `include "mst/ahb_master_sequencer.sv"
    `include "mst/ahb_master_driver.sv"
    `include "mst/ahb_master_monitor.sv"
    `include "mst/ahb_master_agent.sv"

   //-------------------------------------------------------------------------
    // Slave-side Components  (src/slv/)
   //-------------------------------------------------------------------------
    `include "slv/ahb_slave_sequencer.sv"
    `include "slv/ahb_slave_driver.sv"
    `include "slv/ahb_slave_monitor.sv"
    `include "slv/ahb_slave_agent.sv"

   //-------------------------------------------------------------------------
    // Sequence Library  (src/seq/)
   //-------------------------------------------------------------------------
    `include "seq/..."

   //-------------------------------------------------------------------------
    // Environment-level Components  (src/env/)
   //-------------------------------------------------------------------------
    `include "env/ahb_coverage.sv"
    `include "env/ahb_scoreboard.sv"
    `include "env/ahb_vip_env_config.sv"
    `include "env/ahb_vip_env.sv"

endpackage : ahb_pkg

`endif // AHB_PKG_INCLUDED_