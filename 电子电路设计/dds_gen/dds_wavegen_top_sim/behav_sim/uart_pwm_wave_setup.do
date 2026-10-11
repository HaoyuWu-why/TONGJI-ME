# ModelSim UART/PWM waveform setup for an already loaded tb_uart_pwm.
# Run from the GUI Transcript:
#   do {C:/Users/wyshin/Desktop/dds_gen/dds_wavegen_top_sim/behav_sim/uart_pwm_wave_setup.do}

catch {view wave}
catch {delete wave *}

add wave -divider {Clock and serial}
add wave -radix binary   sim:/tb_uart_pwm/CLK
add wave -radix binary   sim:/tb_uart_pwm/UART_RX
add wave -radix binary   sim:/tb_uart_pwm/dut/u_uart_params/params_valid

add wave -divider {Decoded parameters (unsigned)}
add wave -radix unsigned sim:/tb_uart_pwm/dut/wave_sel
add wave -radix unsigned sim:/tb_uart_pwm/dut/freq_index
add wave -radix unsigned sim:/tb_uart_pwm/dut/amplitude
add wave -radix unsigned sim:/tb_uart_pwm/DA_Data

add wave -divider {PWM verification}
add wave -radix binary   sim:/tb_uart_pwm/PWM_Out
add wave -radix unsigned sim:/tb_uart_pwm/pwm_high_count

# Exact 256-clock windows from tb_uart_pwm (50 MHz x 256 = 5.12 us).
proc zoom_pwm_high {} {
    wave zoom range 434650000ps 439770000ps
}
proc zoom_pwm_low {} {
    wave zoom range 439830000ps 444950000ps
}
proc zoom_uart_full {} {
    wave zoom full
}

# Supported in the GUI; catch keeps command-line batch runs quiet.
catch {wave zoom full}

echo "Wave setup complete: parameter/DAC radix=Unsigned; UART/PWM radix=Binary."
echo "GUI zoom commands: zoom_uart_full | zoom_pwm_high | zoom_pwm_low"
