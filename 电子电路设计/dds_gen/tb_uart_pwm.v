`timescale 1ns/1ps

module tb_uart_pwm;
    localparam integer BIT_CLKS = 434;

    reg        CLK;
    reg  [3:0] Key_Row;
    reg        UART_RX;
    wire [3:0] Key_Col;
    wire [7:0] DA_Data;
    wire       PWM_Out;
    wire [7:0] Digitron_Out;
    wire [3:0] DigitronCS_Out;

    integer errors;
    integer i;
    integer pwm_high_count;
    integer capture_fd;
    integer capture_sample;
    integer capture_divider;
    reg     capture_enable;
    reg     pwm_detail_enable;

    dds_wavegen_top dut (
        .CLK(CLK),
        .Key_Row(Key_Row),
        .UART_RX(UART_RX),
        .Song_Enable(1'b0),
        .Key_Col(Key_Col),
        .DA_Data(DA_Data),
        .PWM_Out(PWM_Out),
        .Buzzer(),
        .Digitron_Out(Digitron_Out),
        .DigitronCS_Out(DigitronCS_Out)
    );

    initial begin
        CLK = 1'b0;
        forever #10 CLK = ~CLK;
    end

    always @(posedge CLK) begin
        if (capture_enable) begin
            if (pwm_detail_enable || (capture_divider == 0)) begin
                $fwrite(capture_fd, "%0d,%0t,%0d,%0d,%0d,%0d,%0d,%0d,%0d\n",
                        capture_sample, $time, UART_RX, PWM_Out, DA_Data,
                        dut.wave_sel, dut.freq_index, dut.amplitude,
                        dut.u_uart_params.params_valid);
                capture_sample = capture_sample + 1;
            end
            if (capture_divider == 19)
                capture_divider = 0;
            else
                capture_divider = capture_divider + 1;
        end
    end

    initial begin
        Key_Row = 4'b1111;
        UART_RX = 1'b1;
        errors = 0;
        capture_sample = 0;
        capture_divider = 0;
        capture_enable = 1'b0;
        pwm_detail_enable = 1'b0;
        capture_fd = $fopen("uart_pwm_waveform.csv", "w");
        $fwrite(capture_fd, "sample,time_ps,uart_rx,pwm_out,dac_data,wave_sel,freq_index,amplitude,param_valid\n");

        repeat (20) @(posedge CLK);
        capture_enable = 1'b1;
        uart_send_packet(8'd1, 8'd25, 8'd64, 1'b0);
        repeat (10) @(posedge CLK);
        #1;
        check(dut.wave_sel === 2'd1, "UART selects square wave");
        check(dut.freq_index === 7'd25, "UART sets 2.5 kHz frequency index");
        check(dut.amplitude === 8'd64, "UART sets amplitude to 64");
        check(dut.u_dds_core.fword === 32'd214750, "DDS fword follows UART frequency");

        force dut.u_dds_core.phase_out = 32'h0000_0000;
        repeat (3) @(posedge CLK);
        #1;
        check(DA_Data === 8'd152, "amplitude-scaled square high level is 152");
        count_pwm_high;
        check(pwm_high_count == 152, "PWM duty follows scaled high sample (152/256)");

        force dut.u_dds_core.phase_out = 32'h8000_0000;
        repeat (3) @(posedge CLK);
        #1;
        check(DA_Data === 8'd104, "amplitude-scaled square low level is 104");
        count_pwm_high;
        check(pwm_high_count == 104, "PWM duty follows scaled low sample (104/256)");
        release dut.u_dds_core.phase_out;

        uart_send_packet(8'd3, 8'd100, 8'd0, 1'b1);
        repeat (10) @(posedge CLK);
        #1;
        check(dut.wave_sel === 2'd1, "bad-checksum UART packet is ignored");
        check(dut.freq_index === 7'd25, "bad packet does not change frequency");
        check(dut.amplitude === 8'd64, "bad packet does not change amplitude");

        uart_send_packet(8'd3, 8'd100, 8'd0, 1'b0);
        repeat (10) @(posedge CLK);
        #1;
        check(dut.wave_sel === 2'd3, "UART selects sawtooth wave");
        check(dut.freq_index === 7'd100, "UART sets 10 kHz frequency index");
        check(dut.amplitude === 8'd0, "UART accepts zero AC amplitude");
        repeat (3) @(posedge CLK);
        #1;
        check(DA_Data === 8'd128, "zero amplitude produces DAC midpoint");
        count_pwm_high;
        check(pwm_high_count == 128, "zero AC amplitude produces 50-percent PWM midpoint");

        if (errors == 0)
            $display("UART PWM SIM PASS");
        else
            $display("UART PWM SIM FAIL: %0d error(s)", errors);

        capture_enable = 1'b0;
        $fclose(capture_fd);
        #100;
        $finish;
    end

    task uart_send_packet;
        input [7:0] wave_value;
        input [7:0] freq_value;
        input [7:0] amplitude_value;
        input       corrupt_checksum;
        reg [7:0] checksum;
        begin
            checksum = 8'hA5 ^ wave_value ^ freq_value ^ amplitude_value;
            if (corrupt_checksum)
                checksum = checksum ^ 8'h01;
            uart_send_byte(8'hA5);
            uart_send_byte(wave_value);
            uart_send_byte(freq_value);
            uart_send_byte(amplitude_value);
            uart_send_byte(checksum);
        end
    endtask

    task uart_send_byte;
        input [7:0] value;
        integer bit_index;
        begin
            @(negedge CLK);
            UART_RX = 1'b0;
            repeat (BIT_CLKS) @(posedge CLK);
            for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
                UART_RX = value[bit_index];
                repeat (BIT_CLKS) @(posedge CLK);
            end
            UART_RX = 1'b1;
            repeat (BIT_CLKS) @(posedge CLK);
        end
    endtask

    task count_pwm_high;
        begin
            pwm_high_count = 0;
            pwm_detail_enable = 1'b1;
            for (i = 0; i < 256; i = i + 1) begin
                @(posedge CLK);
                #1;
                if (PWM_Out)
                    pwm_high_count = pwm_high_count + 1;
            end
            pwm_detail_enable = 1'b0;
        end
    endtask

    task check;
        input condition;
        input [1023:0] message;
        begin
            if (condition)
                $display("[%0t] PASS: %0s", $time, message);
            else begin
                errors = errors + 1;
                $display("[%0t] FAIL: %0s", $time, message);
            end
        end
    endtask
endmodule
