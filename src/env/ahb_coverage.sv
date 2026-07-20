//==============================================================================
// File        : ahb_coverage.sv
// Project     : AMBA 3 AHB-Lite VIP
// Author      : Huy Le
// Description : AHB-Lite functional coverage collector. Subscribes to a monitor
//               analysis port and samples each ahb_transaction into a covergroup.
//               One instance per agent; the instance name tags the report.
//==============================================================================

class ahb_coverage extends uvm_subscriber #(ahb_transaction);

    `uvm_component_utils(ahb_coverage)

    //-------------------------------------------------------------------------
    // Sampled transaction handle (covergroup reads from this)
    //-------------------------------------------------------------------------
    ahb_transaction tr;

    //-------------------------------------------------------------------------
    // Per-transaction derived scalars (populated in write() before sampling)
    //-------------------------------------------------------------------------
    bit          has_error;    // any beat returned ERROR
    bit          has_busy;     // any BUSY cycle inserted mid-burst
    bit          has_wait;     // any beat driven with HREADY low (wait state)
    int unsigned beats;        // number of beats in the burst

    //-------------------------------------------------------------------------
    // Functional coverage
    //-------------------------------------------------------------------------
    covergroup ahb_cg;
        option.per_instance = 1;

        // Transfer direction - HWRITE
        cp_dir : coverpoint tr.write {
            bins read  = {AHB_READ};
            bins write = {AHB_WRITE};
        }

        // Burst type - HBURST (all eight encodings)
        cp_burst : coverpoint tr.burst {
            bins single = {AHB_BURST_SINGLE};
            bins incr   = {AHB_BURST_INCR};
            bins wrap4  = {AHB_BURST_WRAP4};
            bins incr4  = {AHB_BURST_INCR4};
            bins wrap8  = {AHB_BURST_WRAP8};
            bins incr8  = {AHB_BURST_INCR8};
            bins wrap16 = {AHB_BURST_WRAP16};
            bins incr16 = {AHB_BURST_INCR16};
        }

        // Transfer size - HSIZE (only sizes legal for the bus width)
        cp_size : coverpoint tr.size {
            bins byte_8   = {AHB_SIZE_8B};
            bins half_16  = {AHB_SIZE_16B};
            bins word_32  = {AHB_SIZE_32B};
            // Larger HSIZE encodings are illegal on a 32-bit data bus and
            // are excluded by the transaction's c_size_max constraint.
            ignore_bins wide = {AHB_SIZE_64B, AHB_SIZE_128B, AHB_SIZE_256B,
                                AHB_SIZE_512B, AHB_SIZE_1024B};
        }

        // Burst length (number of beats)
        cp_beats : coverpoint beats {
            bins single      = {1};
            bins len4        = {4};
            bins len8        = {8};
            bins len16       = {16};
            bins incr_other  = {[2:3], [5:7], [9:15], [17:256]};
        }

        // Slave response - did the burst see an ERROR?
        cp_resp : coverpoint has_error {
            bins okay  = {0};
            bins error = {1};
        }

        // BUSY insertion (master stalling mid-burst)
        cp_busy : coverpoint has_busy {
            bins none = {0};
            bins busy = {1};
        }

        // HREADY wait states (slave back-pressure)
        cp_wait : coverpoint has_wait {
            bins none = {0};
            bins wait_states = {1};
        }

        // Interesting crosses
        x_dir_burst  : cross cp_dir, cp_burst;
        x_dir_size   : cross cp_dir, cp_size;
        x_burst_resp : cross cp_burst, cp_resp;
    endgroup : ahb_cg

    //-------------------------------------------------------------------------
    // Constructor - covergroup must be built here
    //-------------------------------------------------------------------------
    function new(string name, uvm_component parent);
        super.new(name, parent);
        ahb_cg = new();
    endfunction : new

    //-------------------------------------------------------------------------
    // write - analysis callback; derive scalars then sample
    //-------------------------------------------------------------------------
    function void write(ahb_transaction t);
        tr = t;

        beats     = t.get_num_beats();
        has_error = 0;
        has_busy  = 0;
        has_wait  = 0;

        foreach (t.resp[i])
            if (t.resp[i] == AHB_RESP_ERROR) has_error = 1;
        foreach (t.busy_cycles[i])
            if (t.busy_cycles[i] > 0) has_busy = 1;
        if (t.trailing_busy_cycles > 0) has_busy = 1;
        foreach (t.ready[i])
            if (t.ready[i] == 1'b0) has_wait = 1;

        ahb_cg.sample();

        `uvm_info(get_type_name(),
                  $sformatf("Sampled [%s]: burst=%s size=%s beats=%0d error=%0b",
                            t.write.name(), t.burst.name(), t.size.name(),
                            beats, has_error), UVM_HIGH)
    endfunction : write

    //-------------------------------------------------------------------------
    // report_phase - print achieved coverage for this instance
    //-------------------------------------------------------------------------
    function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        `uvm_info(get_type_name(),
                  $sformatf("[%s] functional coverage = %.2f%%",
                            get_name(), ahb_cg.get_coverage()), UVM_LOW)
    endfunction : report_phase

endclass : ahb_coverage
