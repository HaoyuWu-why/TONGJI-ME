// DDS waveform generator for the DMZ_EG4S20 board.
// DA_Data[7:0] drives the on-board R-2R DAC shared with LED0..LED7.

module dds_wavegen_top #(
    parameter integer SONG_CLK_FREQ_HZ = 50000000,
    parameter integer SONG_STEP_TICKS = 9146341  // one 16th note at 82 BPM
) (
    input        CLK,
    input  [3:0] Key_Row,
    input        UART_RX,
    input        Song_Enable,
    output [3:0] Key_Col,
    output [7:0] DA_Data,
    output       PWM_Out,
    output       Buzzer,
    output [7:0] Digitron_Out,
    output [3:0] DigitronCS_Out
);
    localparam [1:0] WAVE_SINE = 2'd0;
    localparam [1:0] WAVE_SQUARE = 2'd1;
    localparam [1:0] WAVE_TRIANGLE = 2'd2;
    localparam [1:0] WAVE_SAW = 2'd3;
    localparam [7:0] AMPLITUDE_STEP = 8'd16;

    wire       key_valid;
    wire [3:0] key_code;
    wire       uart_params_valid;
    wire [1:0] uart_wave_sel;
    wire [6:0] uart_freq_index;
    wire [7:0] uart_amplitude;
    wire       song_active;
    wire [6:0] song_freq_index;
    wire [7:0] song_amplitude;

    reg  [1:0] wave_sel;
    reg  [6:0] freq_index;  // 1..100, unit: 100 Hz
    reg  [7:0] amplitude;   // 0..255

    initial begin
        wave_sel = WAVE_SINE;
        freq_index = 7'd10;  // 1 kHz at power-up
        amplitude = 8'd255;
    end

    matrix_keypad u_keypad (
        .clk(CLK),
        .key_row(Key_Row),
        .key_col(Key_Col),
        .key_valid(key_valid),
        .key_code(key_code)
    );

    always @(posedge CLK) begin
        // Song mode is a temporary overlay. Freeze the user's settings while it
        // is active so switching it off restores the exact pre-song state.
        if (key_valid && !song_active) begin
            case (key_code)
                4'd0: begin  // schematic KEY0: switch waveform
                    if (wave_sel == WAVE_SAW)
                        wave_sel <= WAVE_SINE;
                    else
                        wave_sel <= wave_sel + 2'd1;
                end

                4'd1: begin  // schematic KEY1: frequency +100 Hz
                    if (freq_index < 7'd100)
                        freq_index <= freq_index + 7'd1;
                end

                4'd2: begin  // schematic KEY2: frequency -100 Hz
                    if (freq_index > 7'd1)
                        freq_index <= freq_index - 7'd1;
                end

                4'd3: begin  // schematic KEY3: reset to sine, 1 kHz
                    wave_sel <= WAVE_SINE;
                    freq_index <= 7'd10;
                    amplitude <= 8'd255;
                end

                4'd4: begin  // schematic KEY4: amplitude +16
                    if (amplitude < (8'd255 - AMPLITUDE_STEP))
                        amplitude <= amplitude + AMPLITUDE_STEP;
                    else
                        amplitude <= 8'd255;
                end

                4'd5: begin  // schematic KEY5: amplitude -16
                    if (amplitude > AMPLITUDE_STEP)
                        amplitude <= amplitude - AMPLITUDE_STEP;
                    else
                        amplitude <= 8'd0;
                end

                default: begin
                    wave_sel <= wave_sel;
                    freq_index <= freq_index;
                end
            endcase
        end

        // A valid UART packet has priority over a simultaneous keypad event.
        if (uart_params_valid && !song_active) begin
            wave_sel <= uart_wave_sel;
            freq_index <= uart_freq_index;
            amplitude <= uart_amplitude;
        end
    end

    uart_wave_params #(
        .CLK_FREQ_HZ(50000000),
        .BAUD_RATE(115200)
    ) u_uart_params (
        .clk(CLK),
        .uart_rx(UART_RX),
        .params_valid(uart_params_valid),
        .wave_sel(uart_wave_sel),
        .freq_index(uart_freq_index),
        .amplitude(uart_amplitude)
    );

    orchid_song_player #(
        .CLK_FREQ_HZ(SONG_CLK_FREQ_HZ),
        .STEP_TICKS(SONG_STEP_TICKS)
    ) u_song (
        .clk(CLK),
        .enable_async(Song_Enable),
        .song_active(song_active),
        .buzzer(Buzzer),
        .dds_freq_index(song_freq_index),
        .dds_amplitude(song_amplitude)
    );

    wire [6:0] output_freq_index = song_active ? song_freq_index : freq_index;
    wire [7:0] output_amplitude = song_active ? song_amplitude : amplitude;

    dds_core u_dds_core (
        .clk(CLK),
        .wave_sel(wave_sel),
        .freq_index(output_freq_index),
        .amplitude(output_amplitude),
        .dac_data(DA_Data),
        .pwm_out(PWM_Out)
    );

    sevenseg_status u_display (
        .clk(CLK),
        .wave_sel(wave_sel),
        .freq_index(output_freq_index),
        .amplitude(output_amplitude),
        .seg(Digitron_Out),
        .digit_cs(DigitronCS_Out)
    );
endmodule

// Plays the vocal melody of "Lan Hua Cao" ("Wo cong shan zhong lai...") on
// the board's passive buzzer. The score is in C major, 2/4. STEP_TICKS is one
// sixteenth-note unit (about 182.93 ms at the published quarter-note tempo 82).
// SW0=UP starts/repeats; SW0=DOWN silences and rewinds the melody.
module orchid_song_player #(
    parameter integer CLK_FREQ_HZ = 50000000,
    parameter integer STEP_TICKS = 10000000
) (
    input        clk,
    input        enable_async,
    output reg   song_active,
    output reg   buzzer,
    output reg [6:0] dds_freq_index,
    output reg [7:0] dds_amplitude
);
    localparam [3:0] REST  = 4'd0;
    localparam [3:0] N_E4  = 4'd1; // low 3
    localparam [3:0] N_G4  = 4'd2; // low 5
    localparam [3:0] N_A4  = 4'd3; // low 6
    localparam [3:0] N_B4  = 4'd4; // low 7
    localparam [3:0] N_C5  = 4'd5; // high 1
    localparam [3:0] N_D5  = 4'd6; // high 2
    localparam [3:0] N_E5  = 4'd7; // high 3
    localparam [3:0] N_FS5 = 4'd8; // high sharp 4
    localparam [3:0] N_G5  = 4'd9; // high 5
    localparam [3:0] N_A5  = 4'd10; // high 6
    localparam [5:0] LAST_EVENT = 6'd45;

    reg enable_meta;
    reg enable_sync;
    reg [26:0] event_counter;
    reg [5:0] event_index;
    reg [25:0] tone_counter;
    reg tone_level;
    reg [3:0] note_code;
    reg [3:0] note_units;
    reg [25:0] half_period;
    reg [26:0] event_ticks;

    wire note_gate = song_active && (note_code != REST) &&
                     (event_counter < (event_ticks - (STEP_TICKS / 8)));

    initial begin
        enable_meta = 1'b0;
        enable_sync = 1'b0;
        song_active = 1'b0;
        buzzer = 1'b0;
        event_counter = 27'd0;
        event_index = 6'd0;
        tone_counter = 26'd0;
        tone_level = 1'b0;
    end

    always @(posedge clk) begin
        enable_meta <= enable_async;
        enable_sync <= enable_meta;
        song_active <= enable_sync;

        if (!enable_sync) begin
            event_counter <= 27'd0;
            event_index <= 6'd0;
            tone_counter <= 26'd0;
            tone_level <= 1'b0;
        end else begin
            if (event_counter >= event_ticks - 1) begin
                event_counter <= 27'd0;
                if (event_index == LAST_EVENT)
                    event_index <= 6'd0;
                else
                    event_index <= event_index + 6'd1;
            end else begin
                event_counter <= event_counter + 27'd1;
            end

            if (!note_gate) begin
                tone_counter <= 26'd0;
                tone_level <= 1'b0;
            end else if (tone_counter >= half_period - 1) begin
                tone_counter <= 26'd0;
                tone_level <= ~tone_level;
            end else begin
                tone_counter <= tone_counter + 26'd1;
            end
        end

        buzzer <= note_gate ? tone_level : 1'b0;
    end

    always @(*) begin
        note_code = melody_note(event_index);
        note_units = melody_units(event_index);
        half_period = note_half_period(note_code);
        event_ticks = note_duration_ticks(note_units);
        case (note_code)
            N_E4:  begin dds_freq_index = 7'd3; dds_amplitude = 8'd96;  end
            N_G4:  begin dds_freq_index = 7'd4; dds_amplitude = 8'd112; end
            N_A4:  begin dds_freq_index = 7'd4; dds_amplitude = 8'd128; end
            N_B4:  begin dds_freq_index = 7'd5; dds_amplitude = 8'd144; end
            N_C5:  begin dds_freq_index = 7'd5; dds_amplitude = 8'd160; end
            N_D5:  begin dds_freq_index = 7'd6; dds_amplitude = 8'd176; end
            N_E5:  begin dds_freq_index = 7'd7; dds_amplitude = 8'd192; end
            N_FS5: begin dds_freq_index = 7'd7; dds_amplitude = 8'd208; end
            N_G5:  begin dds_freq_index = 7'd8; dds_amplitude = 8'd224; end
            N_A5:  begin dds_freq_index = 7'd9; dds_amplitude = 8'd240; end
            default: begin dds_freq_index = 7'd1; dds_amplitude = 8'd0; end
        endcase
    end

    function [25:0] note_half_period;
        input [3:0] note;
        begin
            case (note)
                N_E4: note_half_period = CLK_FREQ_HZ / (2 * 330);
                N_G4: note_half_period = CLK_FREQ_HZ / (2 * 392);
                N_A4: note_half_period = CLK_FREQ_HZ / (2 * 440);
                N_B4: note_half_period = CLK_FREQ_HZ / (2 * 494);
                N_C5: note_half_period = CLK_FREQ_HZ / (2 * 523);
                N_D5: note_half_period = CLK_FREQ_HZ / (2 * 587);
                N_E5: note_half_period = CLK_FREQ_HZ / (2 * 659);
                N_FS5: note_half_period = CLK_FREQ_HZ / (2 * 740);
                N_G5: note_half_period = CLK_FREQ_HZ / (2 * 784);
                N_A5: note_half_period = CLK_FREQ_HZ / (2 * 880);
                default: note_half_period = 26'd1;
            endcase
        end
    endfunction

    function [26:0] note_duration_ticks;
        input [3:0] units;
        begin
            case (units)
                4'd1: note_duration_ticks = STEP_TICKS;
                4'd2: note_duration_ticks = STEP_TICKS * 2;
                4'd3: note_duration_ticks = STEP_TICKS * 3;
                4'd4: note_duration_ticks = STEP_TICKS * 4;
                4'd6: note_duration_ticks = STEP_TICKS * 6;
                default: note_duration_ticks = STEP_TICKS * 8;
            endcase
        end
    endfunction

    function [3:0] melody_note;
        input [5:0] idx;
        begin
            case (idx)
                // Measures 5-8: "Wo cong shan zhong lai, dai zhe lan hua cao"
                6'd0: melody_note=N_A4; 6'd1,6'd2,6'd3,6'd4: melody_note=N_E5;
                6'd5: melody_note=N_D5; 6'd6: melody_note=N_C5;
                6'd7: melody_note=N_D5; 6'd8: melody_note=N_C5;
                6'd9: melody_note=N_B4; 6'd10: melody_note=N_A4;
                // Measures 9-12: "Zhong zai xiao yuan zhong, xi wang hua kai zao"
                6'd11,6'd12,6'd13,6'd14,6'd15: melody_note=N_A5;
                6'd16: melody_note=N_G5; 6'd17: melody_note=N_E5;
                6'd18,6'd19: melody_note=N_G5; 6'd20: melody_note=N_FS5;
                6'd21: melody_note=N_E5;
                // Measures 13-16: "Yi ri kan san hui, kan de hua shi guo"
                6'd22: melody_note=N_E5; 6'd23,6'd24: melody_note=N_A5;
                6'd25: melody_note=N_G5; 6'd26: melody_note=N_E5;
                6'd27: melody_note=N_D5; 6'd28: melody_note=N_C5;
                6'd29: melody_note=N_D5; 6'd30: melody_note=N_C5;
                6'd31: melody_note=N_B4; 6'd32: melody_note=N_A4;
                6'd33: melody_note=N_E5;
                // Measures 17-20: "Lan hua que yi ran, bao ye wu yi ge"
                6'd34: melody_note=N_E4; 6'd35,6'd36: melody_note=N_C5;
                6'd37: melody_note=N_B4; 6'd38: melody_note=N_A4;
                6'd39: melody_note=N_E5; 6'd40: melody_note=N_D5;
                6'd41: melody_note=N_C5; 6'd42: melody_note=N_B4;
                6'd43: melody_note=N_G4; 6'd44: melody_note=N_A4;
                default: melody_note=REST;
            endcase
        end
    endfunction

    function [3:0] melody_units;
        input [5:0] idx;
        begin
            case (idx)
                // Eighth notes.
                6'd0,6'd1,6'd2,6'd3,6'd5,6'd8,6'd9,
                6'd11,6'd12,6'd13,6'd14,6'd16,6'd17,6'd18,6'd19,6'd20,
                6'd22,6'd23,6'd24,6'd25,6'd27,6'd30,6'd31,
                6'd34,6'd35,6'd36,6'd37,6'd39,6'd42,6'd43:
                    melody_units = 4'd2;
                // Sixteenth notes following dotted eighth notes.
                6'd7,6'd29,6'd41: melody_units = 4'd1;
                // Dotted eighth notes.
                6'd6,6'd28,6'd40: melody_units = 4'd3;
                // Quarter notes.
                6'd32,6'd33: melody_units = 4'd4;
                // Dotted quarter notes.
                6'd4,6'd15,6'd26,6'd38: melody_units = 4'd6;
                // Half notes and the pause before looping.
                default: melody_units = 4'd8;
            endcase
        end
    endfunction
endmodule

module dds_core (
    input        clk,
    input  [1:0] wave_sel,
    input  [6:0] freq_index,
    input  [7:0] amplitude,
    output reg [7:0] dac_data,
    output           pwm_out
);
    localparam [31:0] PHASE_STEP_100HZ = 32'd8590;

    wire [38:0] freq_ext = {32'd0, freq_index};
    wire [38:0] step_ext = {7'd0, PHASE_STEP_100HZ};
    wire [38:0] fword_wide = freq_ext * step_ext;
    wire [31:0] fword = fword_wide[31:0];
    wire [31:0] phase_out;
    wire [7:0]  sine_data_signed;
    wire [7:0]  sine_data;
    wire [7:0]  phase = phase_out[31:24];

    reg [7:0] por_cnt;
    wire ip_rst_n = &por_cnt;

    // TD DDS IP outputs sine as signed two's-complement. The on-board R-2R DAC is
    // unipolar, so flip the sign bit to convert signed data to offset-binary.
    assign sine_data = sine_data_signed ^ 8'h80;

    // Keep square-wave levels away from the op-amp rails. Full-scale 0/255 makes
    // the on-board DAC output stage recover from saturation and looks rounded on
    // the oscilloscope, while 32/224 still gives a clear square wave.
    wire [7:0] square_data = phase_out[31] ? 8'd32 : 8'd224;
    wire [7:0] triangle_data = phase[7] ? (8'd255 - {phase[6:0], 1'b0}) :
                                         {phase[6:0], 1'b0};
    wire [7:0] saw_data = phase;
    reg  [7:0] wave_data;
    reg  [7:0] pwm_counter;
    wire [7:0] distance_from_mid = (wave_data >= 8'd128) ?
                                         (wave_data - 8'd128) :
                                         (8'd128 - wave_data);
    wire [15:0] scaled_product = distance_from_mid * amplitude;
    wire [7:0] scaled_distance = scaled_product[15:8];
    wire [7:0] amplitude_data = (amplitude == 8'd255) ? wave_data :
                                ((wave_data >= 8'd128) ?
                                 (8'd128 + scaled_distance) :
                                 (8'd128 - scaled_distance));

    // 50 MHz / 256 = 195.3125 kHz PWM carrier. A low-pass filter recovers
    // the amplitude-controlled waveform represented by dac_data.
    assign pwm_out = (pwm_counter < dac_data);

    initial begin
        por_cnt = 8'd0;
        dac_data = 8'd128;
        pwm_counter = 8'd0;
    end

    always @(posedge clk) begin
        if (!ip_rst_n)
            por_cnt <= por_cnt + 8'd1;

        pwm_counter <= pwm_counter + 8'd1;
        dac_data <= amplitude_data;
    end

    always @(*) begin
        case (wave_sel)
            2'd0: wave_data = sine_data;
            2'd1: wave_data = square_data;
            2'd2: wave_data = triangle_data;
            2'd3: wave_data = saw_data;
            default: wave_data = sine_data;
        endcase
    end

    dds_sine_ip u_dds_sine_ip (
        .ce(1'b1),
        .clk(clk),
        .fword(fword),
        .rst_n(ip_rst_n),
        .phase_out(phase_out),
        .wave_sin(sine_data_signed)
    );
endmodule

// UART packet format (115200-8N1 at the top level):
//   0xA5, wave(0..3), frequency_index(1..100), amplitude(0..255), checksum
// checksum is the XOR of the first four bytes. Invalid packets are ignored.
module uart_wave_params #(
    parameter integer CLK_FREQ_HZ = 50000000,
    parameter integer BAUD_RATE = 115200
) (
    input        clk,
    input        uart_rx,
    output reg   params_valid,
    output reg [1:0] wave_sel,
    output reg [6:0] freq_index,
    output reg [7:0] amplitude
);
    localparam integer CLKS_PER_BIT = CLK_FREQ_HZ / BAUD_RATE;
    localparam integer HALF_BIT_CLKS = CLKS_PER_BIT / 2;

    localparam [1:0] RX_IDLE  = 2'd0;
    localparam [1:0] RX_START = 2'd1;
    localparam [1:0] RX_DATA  = 2'd2;
    localparam [1:0] RX_STOP  = 2'd3;

    reg rx_meta;
    reg rx_sync;
    reg [1:0] rx_state;
    reg [15:0] rx_count;
    reg [2:0] rx_bit_index;
    reg [7:0] rx_shift;
    reg [7:0] rx_byte;
    reg       rx_byte_valid;

    reg [2:0] packet_index;
    reg [7:0] packet_wave;
    reg [7:0] packet_freq;
    reg [7:0] packet_amplitude;

    initial begin
        rx_meta = 1'b1;
        rx_sync = 1'b1;
        rx_state = RX_IDLE;
        rx_count = 16'd0;
        rx_bit_index = 3'd0;
        rx_shift = 8'd0;
        rx_byte = 8'd0;
        rx_byte_valid = 1'b0;
        packet_index = 3'd0;
        packet_wave = 8'd0;
        packet_freq = 8'd10;
        packet_amplitude = 8'd255;
        params_valid = 1'b0;
        wave_sel = 2'd0;
        freq_index = 7'd10;
        amplitude = 8'd255;
    end

    always @(posedge clk) begin
        rx_meta <= uart_rx;
        rx_sync <= rx_meta;
        rx_byte_valid <= 1'b0;

        case (rx_state)
            RX_IDLE: begin
                rx_count <= 16'd0;
                if (!rx_sync)
                    rx_state <= RX_START;
            end

            RX_START: begin
                if (rx_count == HALF_BIT_CLKS - 1) begin
                    rx_count <= 16'd0;
                    if (!rx_sync) begin
                        rx_bit_index <= 3'd0;
                        rx_state <= RX_DATA;
                    end else begin
                        rx_state <= RX_IDLE;
                    end
                end else begin
                    rx_count <= rx_count + 16'd1;
                end
            end

            RX_DATA: begin
                if (rx_count == CLKS_PER_BIT - 1) begin
                    rx_count <= 16'd0;
                    rx_shift[rx_bit_index] <= rx_sync;
                    if (rx_bit_index == 3'd7) begin
                        rx_bit_index <= 3'd0;
                        rx_state <= RX_STOP;
                    end else begin
                        rx_bit_index <= rx_bit_index + 3'd1;
                    end
                end else begin
                    rx_count <= rx_count + 16'd1;
                end
            end

            RX_STOP: begin
                if (rx_count == CLKS_PER_BIT - 1) begin
                    rx_count <= 16'd0;
                    rx_state <= RX_IDLE;
                    if (rx_sync) begin
                        rx_byte <= rx_shift;
                        rx_byte_valid <= 1'b1;
                    end
                end else begin
                    rx_count <= rx_count + 16'd1;
                end
            end

            default: rx_state <= RX_IDLE;
        endcase
    end

    always @(posedge clk) begin
        params_valid <= 1'b0;

        if (rx_byte_valid) begin
            case (packet_index)
                3'd0: begin
                    if (rx_byte == 8'hA5)
                        packet_index <= 3'd1;
                end

                3'd1: begin
                    packet_wave <= rx_byte;
                    packet_index <= 3'd2;
                end

                3'd2: begin
                    packet_freq <= rx_byte;
                    packet_index <= 3'd3;
                end

                3'd3: begin
                    packet_amplitude <= rx_byte;
                    packet_index <= 3'd4;
                end

                default: begin
                    packet_index <= 3'd0;
                    if ((rx_byte == (8'hA5 ^ packet_wave ^ packet_freq ^ packet_amplitude)) &&
                        (packet_wave <= 8'd3) &&
                        (packet_freq >= 8'd1) &&
                        (packet_freq <= 8'd100)) begin
                        wave_sel <= packet_wave[1:0];
                        freq_index <= packet_freq[6:0];
                        amplitude <= packet_amplitude;
                        params_valid <= 1'b1;
                    end
                end
            endcase
        end
    end
endmodule

module matrix_keypad #(
    parameter integer SCAN_DIV = 12500,          // 250 us per column at 50 MHz
    parameter integer DEBOUNCE_FRAMES = 20       // 20 full 4-column scans, about 20 ms
) (
    input        clk,
    input  [3:0] key_row,
    output reg [3:0] key_col,
    output reg       key_valid,
    output reg [3:0] key_code
);
    localparam [4:0] NO_KEY = 5'd31;

    reg [13:0] scan_cnt;
    reg [1:0]  col_idx;
    reg [3:0]  row_meta;
    reg [3:0]  row_sync;
    reg [4:0]  sample_code;
    reg [4:0]  frame_code;
    reg [4:0]  next_frame_code;
    reg [4:0]  last_sample;
    reg [4:0]  stable_code;
    reg [7:0]  same_count;

    initial begin
        key_valid = 1'b0;
        key_code = 4'd0;
        scan_cnt = 14'd0;
        col_idx = 2'd0;
        row_meta = 4'b1111;
        row_sync = 4'b1111;
        sample_code = NO_KEY;
        frame_code = NO_KEY;
        next_frame_code = NO_KEY;
        last_sample = NO_KEY;
        stable_code = NO_KEY;
        same_count = 8'd0;
    end

    always @(*) begin
        case (col_idx)
            2'd0: key_col = 4'b1110;
            2'd1: key_col = 4'b1101;
            2'd2: key_col = 4'b1011;
            2'd3: key_col = 4'b0111;
            default: key_col = 4'b1111;
        endcase
    end

    always @(posedge clk) begin
        row_meta <= key_row;
        row_sync <= row_meta;
        key_valid <= 1'b0;

        if (scan_cnt == SCAN_DIV - 1) begin
            scan_cnt <= 14'd0;
            sample_code = scan_code(col_idx, row_sync);

            next_frame_code = frame_code;
            if ((sample_code != NO_KEY) && (frame_code == NO_KEY))
                next_frame_code = sample_code;

            if (col_idx == 2'd3) begin
                col_idx <= 2'd0;
                frame_code <= NO_KEY;

                if (next_frame_code == last_sample) begin
                    if (same_count < DEBOUNCE_FRAMES)
                        same_count <= same_count + 8'd1;
                end else begin
                    last_sample <= next_frame_code;
                    same_count <= 8'd0;
                end

                if ((same_count == DEBOUNCE_FRAMES - 1) &&
                    (next_frame_code != stable_code)) begin
                    stable_code <= next_frame_code;

                    if (next_frame_code != NO_KEY) begin
                        key_code <= next_frame_code[3:0];
                        key_valid <= 1'b1;
                    end
                end
            end else begin
                col_idx <= col_idx + 2'd1;
                frame_code <= next_frame_code;
            end
        end else begin
            scan_cnt <= scan_cnt + 14'd1;
        end
    end

    function [4:0] scan_code;
        input [1:0] col;
        input [3:0] rows;
        begin
            // Schematic key number: KEYn = Key_Row[n/4] + Key_Col[n%4].
            // Thus the bottom-row group KEY0..KEY3 is Row0 with Col0..Col3.
            if (!rows[0])
                scan_code = {1'b0, 2'd0, col};
            else if (!rows[1])
                scan_code = {1'b0, 2'd1, col};
            else if (!rows[2])
                scan_code = {1'b0, 2'd2, col};
            else if (!rows[3])
                scan_code = {1'b0, 2'd3, col};
            else
                scan_code = NO_KEY;
        end
    endfunction
endmodule

module sevenseg_status (
    input        clk,
    input  [1:0] wave_sel,
    input  [6:0] freq_index,
    input  [7:0] amplitude,
    output reg [7:0] seg,
    output reg [3:0] digit_cs
);
    localparam integer DIGIT_DIV = 50000;      // 1 ms per digit at 50 MHz
    localparam integer PAGE_DIV = 50000000;    // alternate pages every 1 s

    localparam [4:0] CH_BLANK = 5'd10;
    localparam [4:0] CH_S     = 5'd11;
    localparam [4:0] CH_I     = 5'd12;
    localparam [4:0] CH_N     = 5'd13;
    localparam [4:0] CH_E     = 5'd14;
    localparam [4:0] CH_Q     = 5'd15;
    localparam [4:0] CH_U     = 5'd16;
    localparam [4:0] CH_T     = 5'd17;
    localparam [4:0] CH_R     = 5'd18;
    localparam [4:0] CH_A     = 5'd19;

    reg [15:0] refresh_cnt;
    reg [1:0]  digit_idx;
    reg [25:0] page_cnt;
    reg        page_wave;
    reg        page_amplitude;
    reg [6:0]  seg_body;
    reg        dot_on;

    wire       freq_10khz;
    wire [3:0] freq_khz_ones;
    wire [3:0] freq_khz_tenths;
    wire [3:0] amplitude_hundreds;
    wire [3:0] amplitude_tens;
    wire [3:0] amplitude_ones;

    assign freq_10khz = (freq_index == 7'd100);
    assign freq_khz_ones = freq_10khz ? 4'd0 : (freq_index / 7'd10);
    assign freq_khz_tenths = freq_10khz ? 4'd0 : (freq_index % 7'd10);
    assign amplitude_hundreds = amplitude / 8'd100;
    assign amplitude_tens = (amplitude / 8'd10) % 8'd10;
    assign amplitude_ones = amplitude % 8'd10;

    initial begin
        refresh_cnt = 16'd0;
        digit_idx = 2'd0;
        page_cnt = 26'd0;
        page_wave = 1'b0;
        page_amplitude = 1'b0;
    end

    always @(posedge clk) begin
        if (refresh_cnt == DIGIT_DIV - 1) begin
            refresh_cnt <= 16'd0;
            digit_idx <= digit_idx + 2'd1;
        end else begin
            refresh_cnt <= refresh_cnt + 16'd1;
        end

        if (page_cnt == PAGE_DIV - 1) begin
            page_cnt <= 26'd0;
            // Rotate through frequency, waveform and amplitude pages.
            if (!page_wave && !page_amplitude) begin
                page_wave <= 1'b1;
                page_amplitude <= 1'b0;
            end else if (page_wave) begin
                page_wave <= 1'b0;
                page_amplitude <= 1'b1;
            end else begin
                page_wave <= 1'b0;
                page_amplitude <= 1'b0;
            end
        end else begin
            page_cnt <= page_cnt + 26'd1;
        end
    end

    always @(*) begin
        case (digit_idx)
            2'd0: digit_cs = 4'b1110;
            2'd1: digit_cs = 4'b1101;
            2'd2: digit_cs = 4'b1011;
            default: digit_cs = 4'b0111;
        endcase

        seg_body = seg7_char(CH_BLANK);
        dot_on = 1'b0;

        if (page_amplitude) begin
            // Decimal amplitude page: A000 .. A255.
            case (digit_idx)
                2'd0: seg_body = seg7_digit(amplitude_ones);
                2'd1: seg_body = seg7_digit(amplitude_tens);
                2'd2: seg_body = seg7_digit(amplitude_hundreds);
                default: seg_body = seg7_char(CH_A);
            endcase
        end else if (!page_wave) begin
            case (digit_idx)
                2'd0: seg_body = seg7_char(CH_BLANK);
                2'd1: seg_body = seg7_digit(freq_khz_tenths);
                2'd2: begin
                    seg_body = seg7_digit(freq_10khz ? 4'd0 : freq_khz_ones);
                    dot_on = 1'b1;
                end
                default: seg_body = freq_10khz ? seg7_digit(4'd1) : seg7_char(CH_BLANK);
            endcase
        end else begin
            case (wave_sel)
                2'd0: begin  // SInE
                    case (digit_idx)
                        2'd0: seg_body = seg7_char(CH_E);
                        2'd1: seg_body = seg7_char(CH_N);
                        2'd2: seg_body = seg7_char(CH_I);
                        default: seg_body = seg7_char(CH_S);
                    endcase
                end

                2'd1: begin  // SqU
                    case (digit_idx)
                        2'd0: seg_body = seg7_char(CH_BLANK);
                        2'd1: seg_body = seg7_char(CH_U);
                        2'd2: seg_body = seg7_char(CH_Q);
                        default: seg_body = seg7_char(CH_S);
                    endcase
                end

                2'd2: begin  // trI
                    case (digit_idx)
                        2'd0: seg_body = seg7_char(CH_BLANK);
                        2'd1: seg_body = seg7_char(CH_I);
                        2'd2: seg_body = seg7_char(CH_R);
                        default: seg_body = seg7_char(CH_T);
                    endcase
                end

                default: begin  // SAU, seven-segment approximation of SAW
                    case (digit_idx)
                        2'd0: seg_body = seg7_char(CH_BLANK);
                        2'd1: seg_body = seg7_char(CH_U);
                        2'd2: seg_body = seg7_char(CH_A);
                        default: seg_body = seg7_char(CH_S);
                    endcase
                end
            endcase
        end

        seg = {dot_on, seg_body};
    end

    function [6:0] seg7_digit;
        input [3:0] value;
        begin
            case (value)
                4'd0: seg7_digit = 7'b0111111;
                4'd1: seg7_digit = 7'b0000110;
                4'd2: seg7_digit = 7'b1011011;
                4'd3: seg7_digit = 7'b1001111;
                4'd4: seg7_digit = 7'b1100110;
                4'd5: seg7_digit = 7'b1101101;
                4'd6: seg7_digit = 7'b1111101;
                4'd7: seg7_digit = 7'b0000111;
                4'd8: seg7_digit = 7'b1111111;
                4'd9: seg7_digit = 7'b1101111;
                default: seg7_digit = 7'b0000000;
            endcase
        end
    endfunction

    function [6:0] seg7_char;
        input [4:0] value;
        begin
            case (value)
                CH_BLANK: seg7_char = 7'b0000000;
                CH_S:     seg7_char = 7'b1101101;
                CH_I:     seg7_char = 7'b0000110;
                CH_N:     seg7_char = 7'b1010100;
                CH_E:     seg7_char = 7'b1111001;
                CH_Q:     seg7_char = 7'b1100111;
                CH_U:     seg7_char = 7'b0111110;
                CH_T:     seg7_char = 7'b1111000;
                CH_R:     seg7_char = 7'b1010000;
                CH_A:     seg7_char = 7'b1110111;
                default:  seg7_char = 7'b0000000;
            endcase
        end
    endfunction
endmodule
