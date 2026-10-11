# Real ModelSim GUI view for waveform switching, 100 Hz frequency steps,
# 100 Hz / 10 kHz limits, DAC data, and seven-segment outputs.

set testbench tb_dds_wavegen_top
do gui_compile_and_run.do

catch {view wave}
catch {delete wave *}

add wave -divider {Key driven parameters}
add wave -radix binary   sim:/tb_dds_wavegen_top/CLK
add wave -radix binary   sim:/tb_dds_wavegen_top/dut/key_valid
add wave -radix unsigned sim:/tb_dds_wavegen_top/dut/key_code
add wave -radix unsigned sim:/tb_dds_wavegen_top/dut/wave_sel
add wave -radix unsigned sim:/tb_dds_wavegen_top/dut/freq_index
add wave -radix unsigned sim:/tb_dds_wavegen_top/dut/amplitude
add wave -radix unsigned sim:/tb_dds_wavegen_top/dut/u_dds_core/fword

add wave -divider {DAC and display}
add wave -radix unsigned sim:/tb_dds_wavegen_top/DA_Data
add wave -radix binary   sim:/tb_dds_wavegen_top/PWM_Out
add wave -radix binary   sim:/tb_dds_wavegen_top/DigitronCS_Out
add wave -radix binary   sim:/tb_dds_wavegen_top/Digitron_Out

configure wave -namecolwidth 330
configure wave -valuecolwidth 110
run 65000ns
wave zoom full
echo "GUI ready. KEY4/KEY5 amplitude changes are visible in amplitude, DA_Data and PWM_Out."
