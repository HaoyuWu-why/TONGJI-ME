# Recompile the song-mode testbench, run the real HDL simulation, and export
# the ModelSim Wave window for insertion into the design report.
set testbench tb_song_mode
do gui_compile_and_run.do

catch {view wave}
catch {delete wave *}

add wave -divider {Song control}
add wave -radix binary   sim:/tb_song_mode/Song_Enable
add wave -radix unsigned sim:/tb_song_mode/dut/u_song/event_index
add wave -radix unsigned sim:/tb_song_mode/dut/u_song/note_code
add wave -radix unsigned sim:/tb_song_mode/dut/u_song/note_units

add wave -divider {Temporary DDS parameters}
add wave -radix unsigned sim:/tb_song_mode/dut/song_freq_index
add wave -radix unsigned sim:/tb_song_mode/dut/song_amplitude
add wave -radix unsigned sim:/tb_song_mode/DA_Data

add wave -divider {Preserved user parameters}
add wave -radix unsigned sim:/tb_song_mode/dut/wave_sel
add wave -radix unsigned sim:/tb_song_mode/dut/freq_index
add wave -radix unsigned sim:/tb_song_mode/dut/amplitude

configure wave -namecolwidth 330
configure wave -valuecolwidth 100
run 32610ns
wave zoom range 0ns 32610ns
write wave C:/Users/wyshin/Desktop/dds_gen/photo/modelsim_song_start_20260910.ps -portrait -start 250ns -end 900ns -width 11.0 -height 7.5 -margin 0.25
write wave C:/Users/wyshin/Desktop/dds_gen/photo/modelsim_song_restore_20260910.ps -portrait -start 32250ns -end 32610ns -width 11.0 -height 7.5 -margin 0.25
quit -f
