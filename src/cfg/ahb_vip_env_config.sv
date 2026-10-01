//=============================================================================
// File        : ahb_vip_env_config.sv
// Project     : AMBA 3 AHB-Lite VIP
// Author      : Huy Le
// Description : Environment configuration: agent configs, virtual interfaces,
//               scoreboard/coverage enables.
//=============================================================================

class ahb_vip_env_config extends uvm_object;

    `uvm_object_utils(ahb_vip_env_config)

    //-------------------------------------------------------------------------
    // Agent configs (created in the constructor)
    //-------------------------------------------------------------------------
    ahb_agent_config master_agent_cfg;
    ahb_agent_config slave_agent_cfg;

    //-------------------------------------------------------------------------
    // Virtual interfaces
    //   master_vif : master side (required)
    //   slave_vif  : slave side (optional). Null: master_vif for both agents
    //-------------------------------------------------------------------------
    virtual ahb_if master_vif;
    virtual ahb_if slave_vif;

    //-------------------------------------------------------------------------
    // Environment feature enables
    //-------------------------------------------------------------------------
    bit has_scoreboard = 1;
    bit has_coverage   = 1;

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(string name = "ahb_vip_env_config");
        super.new(name);
        master_agent_cfg = ahb_agent_config::type_id::create("master_agent_cfg");
        slave_agent_cfg  = ahb_agent_config::type_id::create("slave_agent_cfg");
    endfunction : new

endclass : ahb_vip_env_config