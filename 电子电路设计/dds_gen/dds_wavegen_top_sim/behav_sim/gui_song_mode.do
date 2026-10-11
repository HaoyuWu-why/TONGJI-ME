# Real ModelSim GUI view for SW0 Orchid Grass song mode.
# Start ModelSim in this directory and run:
#   do gui_song_mode.do

set testbench tb_song_mode
do gui_compile_and_run.do

catch {view wave}
catch {delete wave *}

add wave -divider {Song control}
add wave -radix binary   sim:/tb_song_mode/CLK
add wave -radix binary   sim:/tb_song_mode/Song_Enable
add wave -radix binary   sim:/tb_song_mode/Buzzer
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

configure wave -namecolwidth 360
configure wave -valuecolwidth 110
run 32610ns
wave zoom full
echo "GUI ready. event_index/note_code show the corrected Orchid Grass melody; Buzzer shows pitch periods."
