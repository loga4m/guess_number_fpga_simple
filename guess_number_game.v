module guess_number_game(
    input clk,              // 50MHz (Altera Cyclone 4)
    input reset_n,          // Active low reset
    input btn_start,        // Start game
    input btn_inc,          // Increment guess
    input btn_submit,       // Submit guess
    output reg [3:0] digit_sel,
    output reg [7:0] segments
);

    wire reset = ~reset_n; // We use opposite logic reset
    
    // ========== Button Debouncing ==========
    reg [19:0] start_cnt, inc_cnt, submit_cnt;
    reg start_sync1, start_sync2, start_db;
    reg inc_sync1, inc_sync2, inc_db;
    reg submit_sync1, submit_sync2, submit_db;
    reg start_prev, inc_prev, submit_prev;
    
    localparam DEBOUNCE = 20'd1_000_000; // 20ms (general debouncing time)
    
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            start_sync1 <= 0; start_sync2 <= 0; start_db <= 0;
            inc_sync1 <= 0; inc_sync2 <= 0; inc_db <= 0;
            submit_sync1 <= 0; submit_sync2 <= 0; submit_db <= 0;
            start_cnt <= 0; inc_cnt <= 0; submit_cnt <= 0;
        end else begin
            // Sync
            start_sync1 <= btn_start; start_sync2 <= start_sync1;
            inc_sync1 <= btn_inc; inc_sync2 <= inc_sync1;
            submit_sync1 <= btn_submit; submit_sync2 <= submit_sync1;
            
            // Debounce start
            if (start_sync2 == start_db) // enable debouncing if start is pressed 
                start_cnt <= 0;
            else if (start_cnt < DEBOUNCE)
                start_cnt <= start_cnt + 1;
            else begin
                start_db <= start_sync2;
                start_cnt <= 0;
            end
            
            // Debounce inc
            if (inc_sync2 == inc_db)
                inc_cnt <= 0;
            else if (inc_cnt < DEBOUNCE)
                inc_cnt <= inc_cnt + 1;
            else begin
                inc_db <= inc_sync2;
                inc_cnt <= 0;
            end
            
            // Debounce submit
            if (submit_sync2 == submit_db)
                submit_cnt <= 0;
            else if (submit_cnt < DEBOUNCE)
                submit_cnt <= submit_cnt + 1;
            else begin
                submit_db <= submit_sync2;
                submit_cnt <= 0;
            end
        end
    end
    
    // Edge detection
    wire start_edge, inc_edge, submit_edge;
    
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            start_prev <= 0;
            inc_prev <= 0;
            submit_prev <= 0;
        end else begin
            start_prev <= start_db;
            inc_prev <= inc_db;
            submit_prev <= submit_db;
        end
    end
    
    assign start_edge = start_db && !start_prev;
    assign inc_edge = inc_db && !inc_prev;
    assign submit_edge = submit_db && !submit_prev;
    
    // ========== LFSR for Random Number ==========
    reg [3:0] lfsr;
    /*
        LFSR -- linear-feedback shift register is a
        method to generate binary pseudo-random
        numbers using previous state and XOR.
    */
    always @(posedge clk or posedge reset) begin
        if (reset)
            lfsr <= 4'b1011;
        else
            lfsr <= {lfsr[2:0], lfsr[3] ^ lfsr[2]};
    end
    
    // ========== Game State Machine ==========
    localparam IDLE = 3'd0;
    localparam PLAYING = 3'd1;
    localparam SHOW_RESULT = 3'd2;
    localparam WIN_ANIM = 3'd3;
    localparam WIN_STATS = 3'd4;

    localparam ENTERING = 2'd0;
    localparam LOW = 2'd1;
    localparam HIGH = 2'd2;
    localparam WIN = 2'd3;
    
    reg [2:0] state;
    reg [3:0] target;
    reg [3:0] current_guess;
    reg [3:0] attempts;
    reg [1:0] result; // 0=entering, 1=low, 2=high, 3=win
    reg [28:0] delay_cnt;
    
    localparam DELAY = 28'd100_000_000; // 2 seconds
    localparam ANIM_DELAY = 28'd200_000_000; // 4 seconds
    localparam STATS_DELAY = 28'd150_000_000; // 3 seconds
    
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= IDLE;
            target <= 4'd1;
            current_guess <= 4'd1;
            attempts <= 4'd0;
            result <= ENTERING;
            delay_cnt <= 28'd0;
        end else begin
            case (state)
                IDLE: begin
                    result <= ENTERING;
                    current_guess <= 4'd1;
                    attempts <= 4'd0;
                    
                    if (start_edge) begin
                        state <= PLAYING;
                        target <= (lfsr % 10) + 1;
                    end
                end
                
                PLAYING: begin
                    result <= ENTERING; // Show we're entering input
                    
                    if (inc_edge) begin
                        if (current_guess < 4'd10)
                            current_guess <= current_guess + 1;
                        else
                            current_guess <= 4'd1;
                    end
                    
                    if (submit_edge) begin
                        attempts <= attempts + 1;
                        
                        if (current_guess < target)
                            result <= LOW; // Low
                        else if (current_guess > target)
                            result <= HIGH; // High
                        else
                            result <= WIN; // Win
                        
                        state <= SHOW_RESULT;
                        delay_cnt <= 28'd0;
                    end
                end
                
                SHOW_RESULT: begin
                    if (delay_cnt < DELAY)
                        delay_cnt <= delay_cnt + 1;
                    else begin
                        delay_cnt <= 28'd0;
                        
                        if (result == WIN)
                            state <= WIN_ANIM;
                        else begin
                            current_guess <= 4'd1;
                            state <= PLAYING;
                        end
                    end
                end
                
                WIN_ANIM: begin
                    if (delay_cnt < ANIM_DELAY)
                        delay_cnt <= delay_cnt + 1;
                    else begin
                        delay_cnt <= 28'd0;
                        state <= WIN_STATS;
                    end
                end
                
                WIN_STATS: begin
                    if (delay_cnt < STATS_DELAY)
                        delay_cnt <= delay_cnt + 1;
                    else begin
                        delay_cnt <= 28'd0;
                        state <= IDLE;
                    end
                end
                
                default: state <= IDLE;
            endcase
        end
    end
    
    // ========== 7-Segment Display ==========
    function [7:0] seg7;
        input [3:0] num;
        begin
            case (num)
                4'd0: seg7 = 8'b11000000;
                4'd1: seg7 = 8'b11111001;
                4'd2: seg7 = 8'b10100100;
                4'd3: seg7 = 8'b10110000;
                4'd4: seg7 = 8'b10011001;
                4'd5: seg7 = 8'b10010010;
                4'd6: seg7 = 8'b10000010;
                4'd7: seg7 = 8'b11111000;
                4'd8: seg7 = 8'b10000000;
                4'd9: seg7 = 8'b10010000;
                4'd10: seg7 = 8'b11111001; // Display as "1"
                default: seg7 = 8'b11111111;
            endcase
        end
    endfunction
    
    // Moving bar animation patterns (just middle horizontal bar)
    function [7:0] bar_pattern;
        input [2:0] frame;
        input [1:0] digit;
        begin
            case ({frame, digit})
                // Frame 0: -|__|__|__
                {3'd0, 2'd0}: bar_pattern = 8'b10111111;
                {3'd0, 2'd1}: bar_pattern = 8'b11111111;
                {3'd0, 2'd2}: bar_pattern = 8'b11111111;
                {3'd0, 2'd3}: bar_pattern = 8'b11111111;
                // Frame 1: __|-|__|__
                {3'd1, 2'd0}: bar_pattern = 8'b11111111;
                {3'd1, 2'd1}: bar_pattern = 8'b10111111;
                {3'd1, 2'd2}: bar_pattern = 8'b11111111;
                {3'd1, 2'd3}: bar_pattern = 8'b11111111;
                // Frame 2: __|__|-|__
                {3'd2, 2'd0}: bar_pattern = 8'b11111111;
                {3'd2, 2'd1}: bar_pattern = 8'b11111111;
                {3'd2, 2'd2}: bar_pattern = 8'b10111111;
                {3'd2, 2'd3}: bar_pattern = 8'b11111111;
                // Frame 3: __|__|__|-
                {3'd3, 2'd0}: bar_pattern = 8'b11111111;
                {3'd3, 2'd1}: bar_pattern = 8'b11111111;
                {3'd3, 2'd2}: bar_pattern = 8'b11111111;
                {3'd3, 2'd3}: bar_pattern = 8'b10111111;
                // Frame 4: __|__|-|__
                {3'd4, 2'd0}: bar_pattern = 8'b11111111;
                {3'd4, 2'd1}: bar_pattern = 8'b11111111;
                {3'd4, 2'd2}: bar_pattern = 8'b10111111;
                {3'd4, 2'd3}: bar_pattern = 8'b11111111;
                // Frame 5: __|-|__|__
                {3'd5, 2'd0}: bar_pattern = 8'b11111111;
                {3'd5, 2'd1}: bar_pattern = 8'b10111111;
                {3'd5, 2'd2}: bar_pattern = 8'b11111111;
                {3'd5, 2'd3}: bar_pattern = 8'b11111111;
                // Frame 6: -|__|__|__
                {3'd6, 2'd0}: bar_pattern = 8'b10111111;
                {3'd6, 2'd1}: bar_pattern = 8'b11111111;
                {3'd6, 2'd2}: bar_pattern = 8'b11111111;
                {3'd6, 2'd3}: bar_pattern = 8'b11111111;
                // Frame 7: __|-|__|__
                {3'd7, 2'd0}: bar_pattern = 8'b11111111;
                {3'd7, 2'd1}: bar_pattern = 8'b10111111;
                {3'd7, 2'd2}: bar_pattern = 8'b11111111;
                {3'd7, 2'd3}: bar_pattern = 8'b11111111;
                default: bar_pattern = 8'b11111111;
            endcase
        end
    endfunction
    
    reg [15:0] refresh_cnt;
    reg [1:0] digit_idx;
    reg [25:0] anim_cnt;
    reg [2:0] anim_frame;
	 
    localparam ANIM_SPEED = 26'd12_500_000; // 250ms per frame
	 
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            refresh_cnt <= 16'd0;
            digit_idx <= 2'd0;
            digit_sel <= 4'b1110;
            segments <= 8'b11111111;
            anim_cnt <= 26'd0;
            anim_frame <= 3'd0;
        end else begin
            // Animation frame counter (only during WIN_ANIM)
            if (state == WIN_ANIM) begin
                if (anim_cnt < ANIM_SPEED)
                    anim_cnt <= anim_cnt + 1;
                else begin
                    anim_cnt <= 26'd0;
                    anim_frame <= anim_frame + 1;
                end
            end else begin
                anim_cnt <= 26'd0;
                anim_frame <= 3'd0;
            end
            
            if (refresh_cnt < 16'd49999)
                refresh_cnt <= refresh_cnt + 1;
            else begin
                refresh_cnt <= 16'd0;
                digit_idx <= digit_idx + 1;
                
                // Select digit (active low)
                case (digit_idx)
                    2'd0: digit_sel <= 4'b1110;
                    2'd1: digit_sel <= 4'b1101;
                    2'd2: digit_sel <= 4'b1011;
                    2'd3: digit_sel <= 4'b0111;
                endcase
                
                // Display content
                case (digit_idx)
                    2'd0: begin // Rightmost
                        if (state == WIN_ANIM)
                            segments <= bar_pattern(anim_frame, 2'd0);
                        else if (state == WIN_STATS)
                            segments <= seg7(target);
                        else if (state == IDLE)
                            segments <= 8'b11111111;
                        else if (result == ENTERING) begin
                            if (current_guess == 4'd10)
                                segments <= 8'b11000000;
                            else
                                segments <= seg7(current_guess);
                        end
                        else if (result == LOW)
                            segments <= 8'b11000111; // L
                        else if (result == HIGH)
                            segments <= 8'b10001001; // H
                        else
                            segments <= seg7(target);
                    end
                    
                    2'd1: begin // Second
                        if (state == WIN_ANIM)
                            segments <= bar_pattern(anim_frame, 2'd1);
                        else if (state == WIN_STATS) begin
                            if (target >= 10)
                                segments <= seg7(target / 10);
                            else
                                segments <= 8'b11111111;
                        end
                        else if (result == LOW)
                            segments <= 8'b11000000; // o
                        else if (result == HIGH)
                            segments <= 8'b11111001; // i
                        else if (result == ENTERING && current_guess == 4'd10)
                            segments <= 8'b11111001;
                        else
                            segments <= 8'b11111111;
                    end
                    
                    2'd2: begin // Third
                        if (state == WIN_ANIM)
                            segments <= bar_pattern(anim_frame, 2'd2);
                        else if (state == WIN_STATS) begin
                            if (attempts >= 10)
                                segments <= seg7(attempts / 10);
                            else
                                segments <= 8'b11111111;
                        end
                        else if (attempts >= 10)
                            segments <= seg7(attempts / 10);
                        else
                            segments <= 8'b11111111;
                    end
                    
                    2'd3: begin // Leftmost
                        if (state == WIN_ANIM)
                            segments <= bar_pattern(anim_frame, 2'd3);
                        else if (state == WIN_STATS)
                            segments <= seg7(attempts % 10);
                        else
                            segments <= seg7(attempts % 10);
                    end
                endcase
            end
        end
    end

endmodule