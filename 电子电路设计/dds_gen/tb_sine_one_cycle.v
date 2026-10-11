`timescale 1ns/1ps

module tb_sine_one_cycle;
    reg        CLK;
    reg  [3:0] Key_Row;
    wire [3:0] Key_Col;
    wire [7:0] DA_Data;
    wire       PWM_Out;
    wire [7:0] Digitron_Out;
    wire [3:0] DigitronCS_Out;

    integer i;
    integer min_v;
    integer max_v;
    integer sum_v;
    integer first_v;
    integer q1_v;
    integer q2_v;
    integer q3_v;
    integer last_v;
    integer sample_count;
    integer fd;
    integer prev_v;
    integer delta_v;
    integer max_delta;
    integer big_jump_count;
    integer sample_v;

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

        // Keep the test focused on sine output and use the maximum supported
        // frequency. At 10 kHz, one period is 100 us = 5000 clocks at 50 MHz.
        force dut.wave_sel = 2'd0;
        force dut.freq_index = 7'd100;

        repeat (400) @(posedge CLK);

        min_v = 999;
        max_v = -1;
        sum_v = 0;
        prev_v = -1;
        max_delta = 0;
        big_jump_count = 0;
        sample_count = 5000;
        fd = $fopen("sine_one_cycle_da_data.csv", "w");
        $fwrite(fd, "sample,time_ns,phase_msb,sine_signed_hex,dac_unsigned_dec\n");

        for (i = 0; i < sample_count; i = i + 1) begin
            @(posedge CLK);
            #1;

            sample_v = DA_Data;

            if (sample_v < min_v)
                min_v = sample_v;
            if (sample_v > max_v)
                max_v = sample_v;
            sum_v = sum_v + sample_v;

            if (prev_v >= 0) begin
                delta_v = sample_v - prev_v;
                if (delta_v < 0)
                    delta_v = -delta_v;
                if (delta_v > max_delta)
                    max_delta = delta_v;
                if (delta_v > 64)
                    big_jump_count = big_jump_count + 1;
            end
            prev_v = sample_v;

            if (i == 0)
                first_v = sample_v;
            if (i == sample_count / 4)
                q1_v = sample_v;
            if (i == sample_count / 2)
                q2_v = sample_v;
            if (i == (sample_count * 3) / 4)
                q3_v = sample_v;
            if (i == sample_count - 1)
                last_v = sample_v;

            $fwrite(fd, "%0d,%0t,%02h,%02h,%0d\n",
                    i, $time / 1000, dut.u_dds_core.phase_out[31:24],
                    dut.u_dds_core.sine_data_signed, DA_Data);
        end

        $fclose(fd);

        $display("SINE_10KHZ_ONE_PERIOD samples=%0d min=%0d max=%0d avg=%0d max_delta=%0d big_jumps=%0d first=%0d q1=%0d q2=%0d q3=%0d last=%0d",
                 sample_count, min_v, max_v, sum_v / sample_count,
                 max_delta, big_jump_count, first_v, q1_v, q2_v, q3_v, last_v);

        if ((min_v < 16) && (max_v > 239) &&
            (sum_v / sample_count > 112) && (sum_v / sample_count < 144) &&
            (max_delta < 32) && (big_jump_count == 0)) begin
            $display("SINE ONE-CYCLE CHECK PASS");
        end else begin
            $display("SINE ONE-CYCLE CHECK WARN: inspect sine_one_cycle_da_data.csv");
        end

        #100;
        $finish;
    end
endmodule
