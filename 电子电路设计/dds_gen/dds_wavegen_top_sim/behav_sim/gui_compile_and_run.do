# Compile and run one testbench in a GUI-only work library so an already-open
# ModelSim session cannot lock the normal batch-simulation work directory.

set root_dir C:/Users/wyshin/Desktop/dds_gen
set sim_dir $root_dir/dds_wavegen_top_sim/behav_sim
set td_sim_dir C:/Anlogic/TD_5.6.5_SP3_151.449/sim_release
# A previous GUI script deliberately leaves its simulation paused just before
# $finish so the Wave window stays available.  Close that loaded design before
# changing directories or elaborating the next testbench.
catch {quit -sim}
cd $sim_dir

if {![info exists testbench]} {
    set testbench tb_all_waveforms_one_cycle
}

set gui_lib gui_work_$testbench
if {![file exists $gui_lib]} {
    vlib $gui_lib
}
vmap work $gui_lib
transcript file modelsim_gui_${testbench}.log

eval vlog -work work [glob $td_sim_dir/common/al_map_*.v]
vlog -work work $td_sim_dir/common/al_phy_glbl.v
vlog -work work $td_sim_dir/eg/eg_logic_bram.v
vlog -work work $root_dir/dds_wavegen_top.v
vlog -work work $root_dir/al_ip/DDS_Direct_Digital_Synthesis_0/DDS_Direct_Digital_Synthesis_0_gate.v
vlog -work work $root_dir/tb_dds_wavegen_top.v
vlog -work work $root_dir/tb_uart_pwm.v
vlog -work work $root_dir/tb_sine_one_cycle.v
vlog -work work $root_dir/tb_square_one_cycle.v
vlog -work work $root_dir/tb_all_waveforms_one_cycle.v
vlog -work work $root_dir/tb_song_mode.v

echo "===== GUI RUNNING $testbench ====="
vsim -t ps -voptargs=+acc work.$testbench work.glbl
log -r /*
if {$testbench eq "tb_uart_pwm"} {
    do $sim_dir/uart_pwm_wave_setup.do
}

# The caller configures its Wave window first, then runs for a fixed duration
# just short of the testbench $finish.  This keeps the GUI script active so it
# can apply the final zoom range without opening a finish dialog.
