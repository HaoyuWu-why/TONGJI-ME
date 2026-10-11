`timescale 1ns/1ps

module tb_square_one_cycle;
    reg        CLK;
    reg  [3:0] Key_Row;
    wire [3:0] Key_Col;
    wire [7:0] DA_Data;
    wire       PWM_Out;
    wire [7:0] Digitron_Out;
    wire [3:0] DigitronCS_Out;

    integer i;
    integer sample_count;
    integer min_v;
    integer max_v;
    integer sample_v;
    integer prev_v;
    integer transitions;
    integer illegal_count;
    integer high_count;
    integer low_count;
    integer fd;

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

        // 10 kHz square wave: one period is 100 us = 5000 clocks at 50 MHz.
        force dut.wave_sel = 2'd1;
        force dut.freq_index = 7'd100;

        repeat (400) @(posedge CLK);

        sample_count = 5000;
        min_v = 999;
        max_v = -1;
        prev_v = -1;
        transitions = 0;
        illegal_count = 0;
        high_count = 0;
        low_count = 0;

        fd = $fopen("square_one_cycle_da_data.csv", "w");
        $fwrite(fd, "sample,time_ns,phase_msb,dac_unsigned_dec\n");

        for (i = 0; i < sample_count; i = i + 1) begin
            @(posedge CLK);
            #1;

            sample_v = DA_Data;
            if (sample_v < min_v)
                min_v = sample_v;
            if (sample_v > max_v)
                max_v = sample_v;

            if (sample_v == 32)
                low_count = low_count + 1;
            else if (sample_v == 224)
                high_count = high_count + 1;
            else
                illegal_count = illegal_count + 1;

            if ((prev_v >= 0) && (sample_v != prev_v))
                transitions = transitions + 1;
            prev_v = sample_v;

            $fwrite(fd, "%0d,%0t,%02h,%0d\n",
                    i, $time / 1000, dut.u_dds_core.phase_out[31:24], sample_v);
        end

        $fclose(fd);

        $display("SQUARE_10KHZ_ONE_PERIOD samples=%0d min=%0d max=%0d low_count=%0d high_count=%0d transitions=%0d illegal_count=%0d",
                 sample_count, min_v, max_v, low_count, high_count, transitions, illegal_count);

        if ((min_v == 32) && (max_v == 224) &&
            (illegal_count == 0) && (transitions >= 1) && (transitions <= 3)) begin
            $display("SQUARE ONE-CYCLE CHECK PASS");
        end else begin
            $display("SQUARE ONE-CYCLE CHECK WARN: inspect square_one_cycle_da_data.csv");
        end

        #100;
        $finish;
    end
endmodule
