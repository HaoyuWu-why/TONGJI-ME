set root_dir C:/Users/wyshin/Desktop/dds_gen
set sim_dir $root_dir/dds_wavegen_top_sim/behav_sim
set td_sim_dir C:/Anlogic/TD_5.6.5_SP3_151.449/sim_release
cd $sim_dir
if {![info exists testbench]} {
    set testbench tb_dds_wavegen_top
}
transcript file modelsim_${testbench}.log

if {[file exists work]} {
    file delete -force work
}
vlib work
vmap work work

# Anlogic behavioral primitives used by the generated DDS gate model.
eval vlog -work work [glob $td_sim_dir/common/al_map_*.v]
vlog -work work $td_sim_dir/common/al_phy_glbl.v
vlog -work work $td_sim_dir/eg/eg_logic_bram.v

# Design, generated DDS IP model, and all self-checking testbenches.
vlog -work work $root_dir/dds_wavegen_top.v
vlog -work work $root_dir/al_ip/DDS_Direct_Digital_Synthesis_0/DDS_Direct_Digital_Synthesis_0_gate.v
vlog -work work $root_dir/tb_dds_wavegen_top.v
vlog -work work $root_dir/tb_uart_pwm.v
vlog -work work $root_dir/tb_sine_one_cycle.v
vlog -work work $root_dir/tb_square_one_cycle.v
vlog -work work $root_dir/tb_all_waveforms_one_cycle.v
vlog -work work $root_dir/tb_song_mode.v

echo "===== RUNNING $testbench ====="
vsim -t ps -voptargs=+acc work.$testbench work.glbl
log -r /*

# UART/PWM verification view.
if {$testbench eq "tb_uart_pwm"} {
    do $sim_dir/uart_pwm_wave_setup.do
}

run -all

if {$testbench eq "tb_uart_pwm"} {
    catch {wave zoom full}
}
