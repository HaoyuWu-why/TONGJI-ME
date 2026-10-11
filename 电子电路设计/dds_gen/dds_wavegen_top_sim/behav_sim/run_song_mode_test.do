set root_dir C:/Users/wyshin/Desktop/dds_gen
set sim_dir $root_dir/dds_wavegen_top_sim/behav_sim
set td_sim_dir C:/Anlogic/TD_5.6.5_SP3_151.449/sim_release
cd $sim_dir

if {![file isdirectory song_work_v1]} {
    vlib song_work_v1
}
vmap work song_work_v1

eval vlog -work work [glob $td_sim_dir/common/al_map_*.v]
vlog -work work $td_sim_dir/common/al_phy_glbl.v
vlog -work work $td_sim_dir/eg/eg_logic_bram.v
vlog -work work $root_dir/dds_wavegen_top.v
vlog -work work $root_dir/al_ip/DDS_Direct_Digital_Synthesis_0/DDS_Direct_Digital_Synthesis_0_gate.v
vlog -work work $root_dir/tb_song_mode.v

vsim -t ps -voptargs=+acc work.tb_song_mode work.glbl
log -r /*
run -all
quit -f
