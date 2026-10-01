//=============================================================================
// File        : ahb_slave_agent.sv
// Project     : AMBA 3 AHB-Lite VIP
// Author      : Huy Le
// Description : AHB-Lite slave agent.
//               UVM_ACTIVE  - driver + sequencer + monitor
//               UVM_PASSIVE - monitor only
//               Sequencer unused when auto_gen_resp = 1.
//=============================================================================

class ahb_slave_agent extends uvm_agent;

    `uvm_component_utils(ahb_slave_agent)

    // Agent configuration (default if not in config_db)
    ahb_agent_config    cfg;

    // Virtual interface handle
    virtual ahb_if      vif;

    // Sub-components
    ahb_slave_driver    drv;
    ahb_slave_sequencer sqr;
    ahb_slave_monitor   mon;

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction : new

    //-------------------------------------------------------------------------
    // Build phase - resolve config, create sub-components per is_active
    //-------------------------------------------------------------------------
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        if (!uvm_config_db#(ahb_agent_config)::get(this, "", "cfg", cfg)) begin
            `uvm_info(get_type_name(),
                      "No ahb_agent_config in config_db - using defaults", UVM_MEDIUM)
            cfg = ahb_agent_config::type_id::create("cfg");
        end
        is_active = cfg.is_active;

        // Virtual interface
        if (!uvm_config_db#(virtual ahb_if)::get(this, "", "vif", vif))
            `uvm_fatal(get_type_name(), "Virtual interface not found in config_db")

        // Propagate cfg + vif to all children
        uvm_config_db#(ahb_agent_config)::set(this, "*", "cfg", cfg);
        uvm_config_db#(virtual ahb_if)::set(this, "*", "vif", vif);

        // Monitor (always created)
        mon = ahb_slave_monitor::type_id::create("mon", this);

        // Driver + Sequencer (ACTIVE mode only)
        if (is_active == UVM_ACTIVE) begin
            drv = ahb_slave_driver::type_id::create("drv", this);
            sqr = ahb_slave_sequencer::type_id::create("sqr", this);
            `uvm_info(get_type_name(),
                      $sformatf("ACTIVE mode - driver + sequencer created (%s responses)",
                                cfg.auto_gen_resp ? "auto" : "sequence"), UVM_MEDIUM)
        end else begin
            `uvm_info(get_type_name(), "PASSIVE mode - monitor only", UVM_MEDIUM)
        end
    endfunction : build_phase

    //-------------------------------------------------------------------------
    // Connect phase - sequencer -> driver TLM link
    //-------------------------------------------------------------------------
    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        if (is_active == UVM_ACTIVE) begin
            drv.seq_item_port.connect(sqr.seq_item_export);
            drv.sqr = sqr;
        end
    endfunction : connect_phase

endclass : ahb_slave_agent