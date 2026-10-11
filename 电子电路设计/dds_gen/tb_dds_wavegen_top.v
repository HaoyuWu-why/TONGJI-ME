`timescale 1ns/1ps

module tb_dds_wavegen_top;
    reg        CLK;
    reg  [3:0] Key_Row;
    reg        UART_RX;
    wire [3:0] Key_Col;
    wire [7:0] DA_Data;
    wire       PWM_Out;
    wire [7:0] Digitron_Out;
    wire [3:0] DigitronCS_Out;

    reg        keypad_pressed;
    reg  [3:0] keypad_press_code;
    reg  [3:0] unit_key_row;
    wire [3:0] unit_key_col;
    wire       unit_key_valid;
    wire [3:0] unit_key_code;

    integer errors;
    integer pwm_high_count;
    integer pwm_sample_index;

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

    matrix_keypad #(
        .SCAN_DIV(4),
        .DEBOUNCE_FRAMES(3)
    ) u_keypad_unit (
        .clk(CLK),
        .key_row(unit_key_row),
        .key_col(unit_key_col),
        .key_valid(unit_key_valid),
        .key_code(unit_key_code)
    );

    always @(*) begin
        unit_key_row = 4'b1111;
        if (keypad_pressed && !unit_key_col[keypad_press_code[1:0]])
            unit_key_row[keypad_press_code[3:2]] = 1'b0;
    end

    initial begin
        CLK = 1'b0;
        forever #10 CLK = ~CLK;  // 50 MHz
    end

    initial begin
        Key_Row = 4'b1111;
        UART_RX = 1'b1;
        keypad_pressed = 1'b0;
        keypad_press_code = 4'd0;
        errors = 0;

        $display("[%0t] Start DDS waveform generator direct-IP simulation", $time);

        repeat (5) @(posedge CLK);
        #1;
        check(dut.wave_sel === 2'd0, "power-up waveform is sine");
        check(dut.freq_index === 7'd10, "power-up frequency index is 10, i.e. 1 kHz");
        check(dut.amplitude === 8'd255, "power-up amplitude is full scale 255");
        check(dut.u_dds_core.fword === 32'd85900, "DDS fword is 85900 at 1 kHz");

        repeat (300) @(posedge CLK);
        #1;
        check(dut.u_dds_core.ip_rst_n === 1'b1, "DDS IP reset is released");
        check_known(DA_Data, "DAC data after DDS IP reset release");

        force dut.u_dds_core.sine_data_signed = 8'h00;
        repeat (2) @(posedge CLK);
        #1;
        check(DA_Data === 8'h80, "signed DDS sine zero converts to DAC mid-scale");

        force dut.u_dds_core.sine_data_signed = 8'h7F;
        repeat (2) @(posedge CLK);
        #1;
        check(DA_Data === 8'hFF, "signed DDS sine positive peak converts near DAC full-scale");

        force dut.u_dds_core.sine_data_signed = 8'h80;
        repeat (2) @(posedge CLK);
        #1;
        check(DA_Data === 8'h00, "signed DDS sine negative peak converts near DAC zero");
        release dut.u_dds_core.sine_data_signed;

        pulse_key(4'd0);
        check(dut.wave_sel === 2'd1, "key 0 switches sine -> square");

        force dut.u_dds_core.phase_out = 32'h0000_0000;
        repeat (2) @(posedge CLK);
        #1;
        check(DA_Data === 8'd224, "square output is high in first half-cycle");

        force dut.u_dds_core.phase_out = 32'h8000_0000;
        repeat (2) @(posedge CLK);
        #1;
        check(DA_Data === 8'd32, "square output is low in second half-cycle");
        release dut.u_dds_core.phase_out;

        pulse_key(4'd0);
        check(dut.wave_sel === 2'd2, "key 0 switches square -> triangle");

        force dut.u_dds_core.phase_out = 32'h4000_0000;
        repeat (2) @(posedge CLK);
        #1;
        check(DA_Data === 8'd128, "triangle output follows phase ramp in first half-cycle");

        force dut.u_dds_core.phase_out = 32'hC000_0000;
        repeat (2) @(posedge CLK);
        #1;
        check(DA_Data === 8'd127, "triangle output folds in second half-cycle");
        release dut.u_dds_core.phase_out;

        pulse_key(4'd0);
        check(dut.wave_sel === 2'd3, "key 0 switches triangle -> sawtooth");

        force dut.u_dds_core.phase_out = 32'h5A00_0000;
        repeat (2) @(posedge CLK);
        #1;
        check(DA_Data === 8'h5A, "sawtooth output uses phase[31:24]");
        release dut.u_dds_core.phase_out;

        pulse_key(4'd0);
        check(dut.wave_sel === 2'd0, "key 0 wraps sawtooth -> sine");

        pulse_key(4'd1);
        check(dut.freq_index === 7'd11, "key 1 increments frequency by 100 Hz");
        check(dut.u_dds_core.fword === 32'd94490, "DDS fword updates at 1.1 kHz");

        repeat (120) pulse_key(4'd1);
        check(dut.freq_index === 7'd100, "frequency increment saturates at 10 kHz");

        repeat (140) pulse_key(4'd2);
        check(dut.freq_index === 7'd1, "frequency decrement saturates at 100 Hz");

        pulse_key(4'd3);
        check(dut.wave_sel === 2'd0, "key 3 resets waveform to sine");
        check(dut.freq_index === 7'd10, "key 3 resets frequency to 1 kHz");
        check(dut.amplitude === 8'd255, "key 3 resets amplitude to full scale");

        pulse_key(4'd0);
        force dut.u_dds_core.phase_out = 32'h0000_0000;
        pulse_key(4'd5);
        repeat (2) @(posedge CLK);
        #1;
        check(dut.amplitude === 8'd239, "key 5 decreases amplitude by 16");
        check(DA_Data === 8'd217, "key amplitude reduction moves square high level toward midpoint");
        count_pwm_high;
        check(pwm_high_count == 217, "PWM duty follows key-controlled amplitude");

        pulse_key(4'd4);
        check(dut.amplitude === 8'd255, "key 4 increases amplitude by 16 and saturates at 255");

        repeat (20) pulse_key(4'd5);
        check(dut.amplitude === 8'd0, "key 5 amplitude decrement saturates at zero");
        repeat (2) @(posedge CLK);
        #1;
        check(DA_Data === 8'd128, "zero key amplitude produces DAC midpoint");

        pulse_key(4'd4);
        check(dut.amplitude === 8'd16, "key 4 raises zero amplitude to 16");
        repeat (20) pulse_key(4'd4);
        check(dut.amplitude === 8'd255, "key 4 amplitude increment saturates at 255");
        release dut.u_dds_core.phase_out;
        pulse_key(4'd3);

        check_display_frequency_page;
        check_display_wave_page;
        check_display_amplitude_page;
        check_matrix_keypad_bottom_row;

        if (errors == 0) begin
            $display("[%0t] SIM PASS", $time);
        end else begin
            $display("[%0t] SIM FAIL: %0d error(s)", $time, errors);
        end

        #100;
        $finish;
    end

    task pulse_key;
        input [3:0] key_code;
        begin
            @(negedge CLK);
            force dut.key_code = key_code;
            force dut.key_valid = 1'b1;
            @(posedge CLK);
            #1;
            force dut.key_valid = 1'b0;
            release dut.key_valid;
            release dut.key_code;
            repeat (2) @(posedge CLK);
            #1;
        end
    endtask

    task check_matrix_keypad_bottom_row;
        begin
            matrix_press_and_expect(4'd0, "matrix scanner recognizes schematic KEY0");
            matrix_press_and_expect(4'd1, "matrix scanner recognizes schematic KEY1");
            matrix_press_and_expect(4'd2, "matrix scanner recognizes schematic KEY2");
            matrix_press_and_expect(4'd3, "matrix scanner recognizes schematic KEY3");
            matrix_press_and_expect(4'd4, "matrix scanner recognizes amplitude-up KEY4");
            matrix_press_and_expect(4'd5, "matrix scanner recognizes amplitude-down KEY5");
        end
    endtask

    task count_pwm_high;
        begin
            pwm_high_count = 0;
            for (pwm_sample_index = 0; pwm_sample_index < 256; pwm_sample_index = pwm_sample_index + 1) begin
                @(posedge CLK);
                #1;
                if (PWM_Out)
                    pwm_high_count = pwm_high_count + 1;
            end
        end
    endtask

    task matrix_press_and_expect;
        input [3:0] expected_code;
        input [1023:0] message;
        integer i;
        integer good_pulses;
        integer bad_pulses;
        begin
            good_pulses = 0;
            bad_pulses = 0;

            keypad_press_code = expected_code;
            keypad_pressed = 1'b1;

            for (i = 0; i < 140; i = i + 1) begin
                @(posedge CLK);
                #1;
                if (unit_key_valid) begin
                    if (unit_key_code === expected_code)
                        good_pulses = good_pulses + 1;
                    else
                        bad_pulses = bad_pulses + 1;
                end
            end

            check(good_pulses == 1, message);
            check(bad_pulses == 0, "matrix scanner does not emit a wrong key code while pressed");

            keypad_pressed = 1'b0;

            for (i = 0; i < 140; i = i + 1) begin
                @(posedge CLK);
                #1;
                if (unit_key_valid)
                    bad_pulses = bad_pulses + 1;
            end

            check(bad_pulses == 0, "matrix scanner does not repeat while held or released");
        end
    endtask

    task check_display_frequency_page;
        begin
            force dut.u_display.page_wave = 1'b0;

            force dut.u_display.digit_idx = 2'd2;
            #1;
            check(DigitronCS_Out === 4'b1011, "frequency page selects hundreds/ones-kHz digit");
            check(Digitron_Out === {1'b1, 7'b0000110}, "frequency page shows 1.0 kHz dot on digit 2");

            force dut.u_display.digit_idx = 2'd1;
            #1;
            check(DigitronCS_Out === 4'b1101, "frequency page selects tenths-kHz digit");
            check(Digitron_Out === {1'b0, 7'b0111111}, "frequency page shows tenths digit 0 at 1.0 kHz");

            release dut.u_display.digit_idx;
            release dut.u_display.page_wave;
        end
    endtask

    task check_display_wave_page;
        begin
            force dut.u_display.page_wave = 1'b1;

            force dut.u_display.digit_idx = 2'd3;
            #1;
            check(DigitronCS_Out === 4'b0111, "wave page selects leftmost digit");
            check(Digitron_Out === {1'b0, 7'b1101101}, "wave page sine label leftmost digit is S");

            force dut.u_display.digit_idx = 2'd2;
            #1;
            check(Digitron_Out === {1'b0, 7'b0000110}, "wave page sine label digit 2 is I");

            force dut.u_display.digit_idx = 2'd1;
            #1;
            check(Digitron_Out === {1'b0, 7'b1010100}, "wave page sine label digit 1 is n");

            force dut.u_display.digit_idx = 2'd0;
            #1;
            check(Digitron_Out === {1'b0, 7'b1111001}, "wave page sine label rightmost digit is E");

            release dut.u_display.digit_idx;
            release dut.u_display.page_wave;
        end
    endtask

    task check_display_amplitude_page;
        begin
            force dut.u_display.page_wave = 1'b0;
            force dut.u_display.page_amplitude = 1'b1;

            force dut.u_display.digit_idx = 2'd3;
            #1;
            check(DigitronCS_Out === 4'b0111, "amplitude page selects leftmost digit");
            check(Digitron_Out === {1'b0, 7'b1110111}, "amplitude page starts with A");

            force dut.u_display.digit_idx = 2'd2;
            #1;
            check(Digitron_Out === {1'b0, 7'b1011011}, "amplitude page shows hundreds digit 2");

            force dut.u_display.digit_idx = 2'd1;
            #1;
            check(Digitron_Out === {1'b0, 7'b1101101}, "amplitude page shows tens digit 5");

            force dut.u_display.digit_idx = 2'd0;
            #1;
            check(Digitron_Out === {1'b0, 7'b1101101}, "amplitude page shows ones digit 5");

            release dut.u_display.digit_idx;
            release dut.u_display.page_amplitude;
            release dut.u_display.page_wave;
        end
    endtask

    task check;
        input condition;
        input [1023:0] message;
        begin
            if (!condition) begin
                errors = errors + 1;
                $display("[%0t] FAIL: %0s", $time, message);
            end else begin
                $display("[%0t] PASS: %0s", $time, message);
            end
        end
    endtask

    task check_known;
        input [7:0] value;
        input [1023:0] message;
        begin
            check(^value !== 1'bx, message);
        end
    endtask
endmodule
