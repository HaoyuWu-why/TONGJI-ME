`timescale 1ns/1ps

module tb_song_mode;
    reg        CLK;
    reg  [3:0] Key_Row;
    reg        UART_RX;
    reg        Song_Enable;
    wire [3:0] Key_Col;
    wire [7:0] DA_Data;
    wire       PWM_Out;
    wire       Buzzer;
    wire [7:0] Digitron_Out;
    wire [3:0] DigitronCS_Out;

    integer errors;
    integer buzzer_edges;
    integer cycles;
    reg previous_buzzer;

    dds_wavegen_top #(
        .SONG_CLK_FREQ_HZ(50000),
        .SONG_STEP_TICKS(800)
    ) dut (
        .CLK(CLK),
        .Key_Row(Key_Row),
        .UART_RX(UART_RX),
        .Song_Enable(Song_Enable),
        .Key_Col(Key_Col),
        .DA_Data(DA_Data),
        .PWM_Out(PWM_Out),
        .Buzzer(Buzzer),
        .Digitron_Out(Digitron_Out),
        .DigitronCS_Out(DigitronCS_Out)
    );

    initial begin
        CLK = 1'b0;
        forever #10 CLK = ~CLK;
    end

    initial begin
        Key_Row = 4'b1111;
        UART_RX = 1'b1;
        Song_Enable = 1'b0;
        errors = 0;
        buzzer_edges = 0;
        previous_buzzer = 1'b0;

        repeat (10) @(posedge CLK);
        pulse_key(4'd0); // square
        pulse_key(4'd1); // 1.1 kHz
        pulse_key(4'd5); // amplitude 239
        check(dut.wave_sel === 2'd1, "pre-song waveform selected");
        check(dut.freq_index === 7'd11, "pre-song frequency selected");
        check(dut.amplitude === 8'd239, "pre-song amplitude selected");

        Song_Enable = 1'b1;
        repeat (6) @(posedge CLK);
        #1;
        check(dut.song_active === 1'b1, "SW0 UP starts song mode");
        check(dut.output_freq_index === 7'd4, "vocal melody starts on low 6/A4");
        check(dut.output_amplitude === 8'd128, "opening A4 selects amplitude 128");
        check(dut.wave_sel === 2'd1, "song preserves selected waveform type");
        check(dut.u_song.melody_note(6'd11) === 4'd10,
              "second phrase reaches high 6/A5");
        check(dut.u_song.melody_note(6'd20) === 4'd8,
              "score sharp-4 is encoded as F-sharp 5");
        check(dut.u_song.melody_note(6'd34) === 4'd1,
              "fourth phrase includes the low 3/E4 octave");
        check(dut.u_song.melody_units(6'd6) === 4'd3,
              "dotted-eighth duration is preserved");
        check(dut.u_song.melody_units(6'd7) === 4'd1,
              "sixteenth-note duration is preserved");

        previous_buzzer = Buzzer;
        repeat (700) begin
            @(posedge CLK);
            if (Buzzer !== previous_buzzer) begin
                buzzer_edges = buzzer_edges + 1;
                previous_buzzer = Buzzer;
            end
        end
        check(buzzer_edges > 0, "passive buzzer output toggles at note frequency");

        // Key presses are intentionally ignored while the song overlay is active.
        pulse_key(4'd0);
        check(dut.wave_sel === 2'd1, "song mode freezes keypad settings for exact restoration");

        cycles = 0;
        while ((dut.u_song.event_index < 6'd1) && (cycles < 3000)) begin
            @(posedge CLK);
            cycles = cycles + 1;
        end
        #1;
        check(dut.u_song.event_index === 6'd1, "melody advances from low 6 to high 3");
        check(dut.output_freq_index === 7'd7, "high 3/E5 maps to 700 Hz DDS output");
        check(dut.output_amplitude === 8'd192, "higher E5 note raises the temporary DAC amplitude");

        Song_Enable = 1'b0;
        repeat (6) @(posedge CLK);
        #1;
        check(dut.song_active === 1'b0, "SW0 DOWN stops song mode");
        check(Buzzer === 1'b0, "buzzer is silent after SW0 DOWN");
        check(dut.wave_sel === 2'd1, "waveform restored after song");
        check(dut.output_freq_index === 7'd11, "frequency restored after song");
        check(dut.output_amplitude === 8'd239, "amplitude restored after song");

        Song_Enable = 1'b1;
        repeat (6) @(posedge CLK);
        #1;
        check(dut.u_song.event_index === 6'd0, "a new SW0 UP restarts the melody from the beginning");

        if (errors == 0)
            $display("[%0t] SONG MODE SIM PASS", $time);
        else
            $display("[%0t] SONG MODE SIM FAIL: %0d error(s)", $time, errors);
        $finish;
    end

    task pulse_key;
        input [3:0] key_code;
        begin
            force dut.key_code = key_code;
            force dut.key_valid = 1'b1;
            @(posedge CLK);
            #1;
            force dut.key_valid = 1'b0;
            @(posedge CLK);
            #1;
            release dut.key_valid;
            release dut.key_code;
        end
    endtask

    task check;
        input condition;
        input [8*96-1:0] message;
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
