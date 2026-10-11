# Real ModelSim GUI view for the four DDS output waveforms.
# Start ModelSim in this directory and run:
#   do gui_all_waveforms.do

set testbench tb_all_waveforms_one_cycle
do gui_compile_and_run.do

catch {view wave}
catch {delete wave *}

add wave -divider {DDS control}
add wave -radix binary   sim:/tb_all_waveforms_one_cycle/CLK
add wave -radix unsigned sim:/tb_all_waveforms_one_cycle/dut/wave_sel
add wave -radix unsigned sim:/tb_all_waveforms_one_cycle/dut/freq_index

add wave -divider {DAC output from real HDL simulation}
# DA_Data is offset-binary for the unipolar DAC.  Force unsigned interpretation;
# otherwise ModelSim's analog renderer treats bit 7 as a sign bit and draws false
# discontinuities when the value crosses 127/128.
add wave -radix unsigned -format Analog-Step -height 180 -max 255 -min 0 sim:/tb_all_waveforms_one_cycle/DA_Data

proc show_all_waves {} {
    wave zoom range 7500ns 410000ns
}
proc show_sine {} {
    wave zoom range 7800ns 108500ns
}
proc show_square {} {
    wave zoom range 108100ns 209000ns
}
proc show_triangle {} {
    wave zoom range 208500ns 309500ns
}
proc show_saw {} {
    wave zoom range 309000ns 410000ns
}

configure wave -namecolwidth 300
configure wave -valuecolwidth 100
run 409690ns
show_all_waves
echo "GUI ready. Use: show_all_waves | show_sine | show_square | show_triangle | show_saw"
