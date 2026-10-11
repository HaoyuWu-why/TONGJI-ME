set script_dir [file dirname [file normalize [info script]]]
set root_dir   $script_dir
set build_dir  [file join $root_dir build_td_fix]

file mkdir $build_dir
cd $build_dir

import_device eagle_s20.db -package EG4S20BG256
set_param flow qor_monitor on
set_param rtl reg_threshold 0

set hdl_file    [file join $root_dir dds_wavegen_top.v]
set dds_ip_file [file join $root_dir al_ip DDS_Direct_Digital_Synthesis_0 DDS_Direct_Digital_Synthesis_0_gate.v]
set adc_file    [file join $root_dir dds_wavegen.adc]
set sdc_file    [file join $root_dir dds_wavegen.sdc]

eval "read_hdl -file {$dds_ip_file $hdl_file} -top dds_wavegen_top"
eval "read_adc {$adc_file}"
eval "read_sdc {$sdc_file}"

optimize_rtl
report_area -file dds_wavegen_rtl.area

optimize_gate
legalize_phy_inst
export_db dds_wavegen_gate.db
report_qor -step gate -file dds_wavegen_gate.qor
report_area -file dds_wavegen_gate.area

place
report_qor -step place -file dds_wavegen_place.qor
start_timer
report_timing_summary -file dds_wavegen_place_timing.rpt

route
export_db dds_wavegen_route.db
report_qor -step route -file dds_wavegen_route.qor
report_area -io_info -file dds_wavegen_route.area
start_timer
report_timing -mode FINAL -net_info -rpt_autogen true -file dds_wavegen_route_timing.rpt

bitgen -bit dds_wavegen.bit -bin dds_wavegen.bin
puts "BITSTREAM: [file join $build_dir dds_wavegen.bit]"
puts "BINSTREAM: [file join $build_dir dds_wavegen.bin]"
exit
