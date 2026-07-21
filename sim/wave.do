# ============================================================================
# wave.do - AMBA 3 AHB-Lite waveform setup for QuestaSim GUI
#   Custom radices show the enum names declared in src/cfg/ahb_types.sv on the
#   plain interface vectors: transfer type, burst type, size, direction and
#   response.
#
#   Colors:
#     - AHB signals use Questa's DEFAULT wave color (green traces, RED for
#       unknown/X regions before reset) - no -color overrides, otherwise the
#       X region loses its red highlight.
#     - User-defined radix values carry their own -color (green) so those rows
#       match the other signals instead of the white/gray default.
#     - clk / rst_n stay yellow.
# ============================================================================

radix define ahb_trans {
    2'b00 "IDLE"   -color #00ff00,
    2'b01 "BUSY"   -color #00ff00,
    2'b10 "NONSEQ" -color #00ff00,
    2'b11 "SEQ"    -color #00ff00,
    -default hex
}

radix define ahb_burst {
    3'b000 "SINGLE" -color #00ff00,
    3'b001 "INCR"   -color #00ff00,
    3'b010 "WRAP4"  -color #00ff00,
    3'b011 "INCR4"  -color #00ff00,
    3'b100 "WRAP8"  -color #00ff00,
    3'b101 "INCR8"  -color #00ff00,
    3'b110 "WRAP16" -color #00ff00,
    3'b111 "INCR16" -color #00ff00,
    -default hex
}

# HSIZE encodes the transfer width in bits (2^HSIZE bytes)
radix define ahb_size {
    3'b000 "8b"    -color #00ff00,
    3'b001 "16b"   -color #00ff00,
    3'b010 "32b"   -color #00ff00,
    3'b011 "64b"   -color #00ff00,
    3'b100 "128b"  -color #00ff00,
    3'b101 "256b"  -color #00ff00,
    3'b110 "512b"  -color #00ff00,
    3'b111 "1024b" -color #00ff00,
    -default hex
}

radix define ahb_dir {
    1'b0 "READ"  -color #00ff00,
    1'b1 "WRITE" -color #00ff00,
    -default hex
}

radix define ahb_resp {
    1'b0 "OKAY"  -color #00ff00,
    1'b1 "ERROR" -color #00ff00,
    -default hex
}

quietly set wave_pos 0

add wave -divider {System}
add wave -color Yellow sim:/tb_top/intf/clk
add wave -color Yellow sim:/tb_top/intf/rst_n

add wave -divider {Address / Control Phase}
add wave -radix ahb_trans sim:/tb_top/intf/HTRANS
add wave -hex              sim:/tb_top/intf/HADDR
add wave -radix ahb_dir   sim:/tb_top/intf/HWRITE
add wave -radix ahb_size  sim:/tb_top/intf/HSIZE
add wave -radix ahb_burst sim:/tb_top/intf/HBURST
add wave -hex             sim:/tb_top/intf/HPROT
add wave                  sim:/tb_top/intf/HMASTLOCK

add wave -divider {Data Phase}
add wave -hex sim:/tb_top/intf/HWDATA
add wave -hex sim:/tb_top/intf/HRDATA

add wave -divider {Slave Response}
add wave                 sim:/tb_top/intf/HREADY
add wave -radix ahb_resp sim:/tb_top/intf/HRESP

configure wave -namecolwidth 220
configure wave -valuecolwidth 100
configure wave -timelineunits ns
update
WaveRestoreZoom {0 ns} {500 ns}