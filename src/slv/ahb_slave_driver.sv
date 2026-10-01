//=============================================================================
// File        : ahb_slave_driver.sv
// Project     : AMBA 3 AHB-Lite VIP
// Author      : Huy Le
// Description : AHB-Lite slave driver (ahb_agent_config.auto_gen_resp):
//                 1 (auto)     - internal memory model, OKAY
//                 0 (sequence) - wait states / HRESP / HRDATA from
//                                ahb_slave_response items
//               Raises no objection.
//=============================================================================

class ahb_slave_driver extends uvm_driver #(ahb_slave_response);

    `uvm_component_utils(ahb_slave_driver)

    // Virtual interface handle
    virtual ahb_if vif;

    // Sequencer (set by the agent); receives the current address phase
    ahb_slave_sequencer sqr;

    // See ahb_agent_config
    bit          auto_gen_resp   = 1;
    int unsigned ready_delay_min = 0;
    int unsigned ready_delay_max = 0;

    // Auto-mode memory model (HADDR -> data)
    protected bit [AHB_DATA_WIDTH-1:0] mem [bit [AHB_ADDR_WIDTH-1:0]];

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction : new

    //-------------------------------------------------------------------------
    // Build phase - vif and agent config (optional)
    //-------------------------------------------------------------------------
    function void build_phase(uvm_phase phase);
        ahb_agent_config cfg;
        super.build_phase(phase);
        if (!uvm_config_db#(virtual ahb_if)::get(this, "", "vif", vif))
            `uvm_fatal(get_type_name(), "Virtual interface not found in config_db")
        if (uvm_config_db#(ahb_agent_config)::get(this, "", "cfg", cfg)) begin
            auto_gen_resp   = cfg.auto_gen_resp;
            ready_delay_min = cfg.ready_delay_min;
            ready_delay_max = cfg.ready_delay_max;
        end
    endfunction : build_phase

    //-------------------------------------------------------------------------
    // Run phase - restart on reset
    //-------------------------------------------------------------------------
    virtual task run_phase(uvm_phase phase);
        forever begin
            reset_signals();
            if (!vif.rst_n) @(posedge vif.rst_n);
            `uvm_info(get_type_name(),
                      $sformatf("Reset deasserted - slave driver active (%s mode)",
                                auto_gen_resp ? "auto" : "sequence"), UVM_MEDIUM)
            fork
                serve_bus();
                begin : rst_watch
                    @(negedge vif.rst_n);
                    `uvm_info(get_type_name(),
                              "Reset asserted - slave driver idle", UVM_MEDIUM)
                end
            join_any
            disable fork;
        end
    endtask : run_phase

    //-------------------------------------------------------------------------
    // serve_bus - one iteration per address phase. IDLE/BUSY: zero-wait OKAY;
    // NONSEQ/SEQ: data-phase response
    //-------------------------------------------------------------------------
    task serve_bus();
        @(vif.slave_cb);
        forever begin
            ahb_trans_e htrans;
            htrans = ahb_trans_e'(vif.slave_cb.HTRANS);

            if (htrans == AHB_TRANS_IDLE || htrans == AHB_TRANS_BUSY) begin
                vif.slave_cb.HREADY <= 1'b1;
                vif.slave_cb.HRESP  <= AHB_RESP_OKAY;
                @(vif.slave_cb);
            end else begin
                bit [AHB_ADDR_WIDTH-1:0] addr;
                ahb_dir_e                write;
                int unsigned             delay;
                ahb_resp_e               resp;
                bit [AHB_DATA_WIDTH-1:0] rdata;

                addr  = vif.slave_cb.HADDR;
                write = ahb_dir_e'(vif.slave_cb.HWRITE);

                get_response(addr, write, delay, resp, rdata);
                drive_beat(addr, write, delay, resp, rdata);
            end
        end
    endtask : serve_bus

    //-------------------------------------------------------------------------
    // get_response - response for one beat. Sequence mode: get_next_item()
    // and item_done() in the same time step (reset-safe)
    //-------------------------------------------------------------------------
    task get_response(input  bit [AHB_ADDR_WIDTH-1:0] addr,
                      input  ahb_dir_e                write,
                      output int unsigned             delay,
                      output ahb_resp_e               resp,
                      output bit [AHB_DATA_WIDTH-1:0] rdata);
        if (auto_gen_resp) begin
            delay = $urandom_range(ready_delay_max, ready_delay_min);
            resp  = AHB_RESP_OKAY;
            rdata = mem.exists(addr) ? mem[addr] : '0;
        end else begin
            ahb_slave_response rsp;
            // Address phase for the response sequence
            if (sqr != null) begin
                sqr.req_addr  = addr;
                sqr.req_write = write;
            end
            seq_item_port.get_next_item(rsp);
            delay = rsp.ready_delay;
            resp  = rsp.resp;
            rdata = rsp.rdata;
            seq_item_port.item_done();
        end
    endtask : get_response

    //-------------------------------------------------------------------------
    // drive_beat - data phase:
    //   1) 'delay' wait states (HREADY=0, HRESP=OKAY)
    //   2) OKAY  - HREADY=1 (+ HRDATA on read); store write data
    //      ERROR - (HREADY=0, ERROR) then (HREADY=1, ERROR)
    //-------------------------------------------------------------------------
    task drive_beat(input bit [AHB_ADDR_WIDTH-1:0] addr,
                    input ahb_dir_e                write,
                    input int unsigned             delay,
                    input ahb_resp_e               resp,
                    input bit [AHB_DATA_WIDTH-1:0] rdata);

        repeat (delay) begin
            vif.slave_cb.HREADY <= 1'b0;
            vif.slave_cb.HRESP  <= AHB_RESP_OKAY;
            @(vif.slave_cb);
        end

        if (resp == AHB_RESP_ERROR) begin
            vif.slave_cb.HREADY <= 1'b0;
            vif.slave_cb.HRESP  <= AHB_RESP_ERROR;
            @(vif.slave_cb);
            vif.slave_cb.HREADY <= 1'b1;
            vif.slave_cb.HRESP  <= AHB_RESP_ERROR;
            @(vif.slave_cb);
            // No memory update on ERROR
        end else begin
            vif.slave_cb.HREADY <= 1'b1;
            vif.slave_cb.HRESP  <= AHB_RESP_OKAY;
            if (write == AHB_READ)
                vif.slave_cb.HRDATA <= rdata;
            @(vif.slave_cb);
            if (write == AHB_WRITE)
                mem[addr] = vif.slave_cb.HWDATA;
        end

        `uvm_info(get_type_name(),
                  $sformatf("Beat %s addr=0x%08h resp=%s waits=%0d %s=0x%08h",
                            write.name(), addr, resp.name(), delay,
                            (write == AHB_WRITE) ? "wdata" : "rdata",
                            (write == AHB_WRITE) ? vif.slave_cb.HWDATA : rdata),
                  UVM_HIGH)
    endtask : drive_beat

    //-------------------------------------------------------------------------
    // reset_signals - HREADY=1, OKAY. Memory is kept
    //-------------------------------------------------------------------------
    task reset_signals();
        @(vif.slave_cb);
        vif.slave_cb.HREADY <= 1'b1;
        vif.slave_cb.HRESP  <= AHB_RESP_OKAY;
        vif.slave_cb.HRDATA <= '0;
    endtask : reset_signals

endclass : ahb_slave_driver