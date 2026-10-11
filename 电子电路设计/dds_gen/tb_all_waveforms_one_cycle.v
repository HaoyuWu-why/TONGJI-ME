`timescale 1ns/1ps

module tb_all_waveforms_one_cycle;
    reg        CLK;
    reg  [3:0] Key_Row;
    wire [3:0] Key_Col;
    wire [7:0] DA_Data;
    wire       PWM_Out;
    wire [7:0] Digitron_Out;
    wire [3:0] DigitronCS_Out;

    integer fd;
    integer i;
    integer sample_count;
    integer error_count;
    integer min_seen;
    integer max_seen;
    integer previous_sample;
    integer large_jump_count;
    integer invalid_level_count;

    dds_wavegen_top dut (
        .CLK(CLK),
        .Key_Row(Key_Row),
        .UART_RX(1'b1),
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
        forever #10 CLK = ~CLK;  // 50 MHz
    end

    initial begin
        Key_Row = 4'b1111;
        sample_count = 5000;     // 100 us = 1 period at 10 kHz
        error_count = 0;

        force dut.freq_index = 7'd100;

        repeat (400) @(posedge CLK);

        fd = $fopen("all_waveforms_one_cycle_da_data.csv", "w");
        $fwrite(fd, "wave,sample,time_ns,phase_msb,sine_signed_hex,dac_unsigned_dec\n");

        capture_wave(2'd0, "sine");
        capture_wave(2'd1, "square");
        capture_wave(2'd2, "triangle");
        capture_wave(2'd3, "saw");

        $fclose(fd);
        if (error_count == 0)
            $display("ALL WAVEFORMS ONE-CYCLE CHECK PASS");
        else
            $display("ALL WAVEFORMS ONE-CYCLE CHECK FAIL: %0d errors", error_count);

        #100;
        $finish;
    end

    task capture_wave;
        input [1:0] mode;
        input [1023:0] wave_name;
        begin
            min_seen = 255;
            max_seen = 0;
            previous_sample = -1;
            large_jump_count = 0;
            invalid_level_count = 0;

            force dut.wave_sel = mode;
            repeat (20) @(posedge CLK);

            for (i = 0; i < sample_count; i = i + 1) begin
                @(posedge CLK);
                #1;
                $fwrite(fd, "%0s,%0d,%0t,%02h,%02h,%0d\n",
                        wave_name, i, $time / 1000,
                        dut.u_dds_core.phase_out[31:24],
                        dut.u_dds_core.sine_data_signed,
                        DA_Data);

                if (DA_Data < min_seen)
                    min_seen = DA_Data;
                if (DA_Data > max_seen)
                    max_seen = DA_Data;
                if ((previous_sample >= 0) &&
                    (((DA_Data > previous_sample) && (DA_Data - previous_sample > 128)) ||
                     ((previous_sample > DA_Data) && (previous_sample - DA_Data > 128))))
                    large_jump_count = large_jump_count + 1;
                if ((mode == 2'd1) && (DA_Data != 8'd32) && (DA_Data != 8'd224))
                    invalid_level_count = invalid_level_count + 1;
                previous_sample = DA_Data;
            end

            $display("CAPTURED %0s one period at 10 kHz", wave_name);

            case (mode)
                2'd0: begin
                    if ((min_seen <= 2) && (max_seen >= 254) && (large_jump_count == 0))
                        $display("PASS: sine range and continuity (%0d..%0d)", min_seen, max_seen);
                    else begin
                        $display("FAIL: sine range/continuity (%0d..%0d, jumps=%0d)", min_seen, max_seen, large_jump_count);
                        error_count = error_count + 1;
                    end
                end
                2'd1: begin
                    if ((min_seen == 32) && (max_seen == 224) &&
                        (invalid_level_count == 0) && (large_jump_count >= 1))
                        $display("PASS: square uses only levels 32/224 and toggles");
                    else begin
                        $display("FAIL: square levels/toggles (%0d..%0d, invalid=%0d, jumps=%0d)",
                                 min_seen, max_seen, invalid_level_count, large_jump_count);
                        error_count = error_count + 1;
                    end
                end
                2'd2: begin
                    if ((min_seen <= 1) && (max_seen >= 254) && (large_jump_count == 0))
                        $display("PASS: triangle range and continuity (%0d..%0d)", min_seen, max_seen);
                    else begin
                        $display("FAIL: triangle range/continuity (%0d..%0d, jumps=%0d)", min_seen, max_seen, large_jump_count);
                        error_count = error_count + 1;
                    end
                end
                2'd3: begin
                    if ((min_seen <= 1) && (max_seen >= 254) && (large_jump_count >= 1))
                        $display("PASS: sawtooth range and wrap (%0d..%0d)", min_seen, max_seen);
                    else begin
                        $display("FAIL: sawtooth range/wrap (%0d..%0d, jumps=%0d)", min_seen, max_seen, large_jump_count);
                        error_count = error_count + 1;
                    end
                end
            endcase
        end
    endtask
endmodule
