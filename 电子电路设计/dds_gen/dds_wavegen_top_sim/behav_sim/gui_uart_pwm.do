# Real ModelSim GUI view for UART parameter download and PWM amplitude output.

set testbench tb_uart_pwm
do gui_compile_and_run.do

# The main script sources uart_pwm_wave_setup.do before running.
configure wave -namecolwidth 340
configure wave -valuecolwidth 105
run 1318630ns
zoom_uart_full
echo "GUI ready. Use: zoom_uart_full | zoom_pwm_high | zoom_pwm_low"
