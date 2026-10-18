// Fixed text, RGB888 combinational overlay; no video latency or text CDC.
// BRAM_FONT=1 (M5): Chinese glyphs come from the FONT.BIN BRAM while
// font_valid, else from the case font. The BRAM has one clock of read
// latency, so the character is formed for the next pixel, which addresses
// the BRAM, and registered for the current one.
module scroll_text_overlay #(
    parameter integer ENABLE = 1,
    parameter integer TEXT_LEN = 25,
    parameter [TEXT_LEN*8-1:0] TEXT = "ANLOGIC FPGA IMAGE PLAYER",
    parameter integer WINDOW_LEFT = 8,
    parameter integer WINDOW_RIGHT = 632,
    parameter integer TEXT_Y = 444,
    parameter integer PIXELS_PER_FRAME = 1,
    parameter integer CN_ENABLE = 0,
    parameter integer RUNTIME_ENABLE = 0,
    parameter integer BRAM_FONT = 0
)(
    input clk, rst, vs, de,
    input [9:0] pixel_x,
    input image_valid,
    input [23:0] rgb_in,
    output wire [23:0] rgb_out,
    output wire active,
    input [119:0] runtime_text,
    input [3:0] runtime_length,
    input runtime_enable, runtime_text_changed,
    output [10:0] font_addr,          // glyph 0x80+i is FONT.BIN glyph i
    input [15:0] font_data,
    input font_valid
);
    localparam integer MIXED_LEN = 12;
    localparam integer MAX_WIDTH = (RUNTIME_ENABLE ? 15 : (CN_ENABLE ? MIXED_LEN : TEXT_LEN)) * 16;
    wire [10:0] text_width = RUNTIME_ENABLE ? {3'b0,runtime_length,4'b0} : MAX_WIDTH;
    wire subtitle_enabled = RUNTIME_ENABLE ? runtime_enable : 1'b1;
    // Window [8,632): text starts at x=632 and ends at x=8-TEXT_WIDTH.
    // Retain one fully outside position at each end of the cycle.
    localparam integer LAST_STEP = WINDOW_RIGHT - WINDOW_LEFT + MAX_WIDTH;
    wire [10:0] last_step = WINDOW_RIGHT - WINDOW_LEFT + text_width;
    localparam integer STEP_BITS = $clog2(LAST_STEP + 1);
    reg [STEP_BITS-1:0] scroll;
    wire [8:0] line_y;
    reg started;
    wire frame_start;
    osd_pixel_position position(.clk(clk), .rst(rst), .vs(vs), .de(de),
        .line_y(line_y), .frame_start(frame_start), .first_active());
    // TEXT is a synthesis-time constant. No asynchronous text bus is sampled.
    // A future runtime source must hold a complete mailbox until acknowledged;
    // commit its text/length/enable together here at frame_start.
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            scroll <= 0;
            started <= 0;
        end else begin
            if(RUNTIME_ENABLE && runtime_text_changed) scroll<=0;
            else if (frame_start && ENABLE && image_valid && subtitle_enabled) begin
                if (!started) begin
                    started <= 1;
                    scroll <= 0;
                end else
                    if (scroll == last_step) scroll <= 0;
                    else if (scroll + PIXELS_PER_FRAME >= last_step) scroll <= last_step;
                    else scroll <= scroll + PIXELS_PER_FRAME;
            end
        end
    end

    // Use a signed local coordinate: negative means not yet inside the text.
    wire signed [31:0] text_x = $signed({1'b0,scroll}) +
                                                $signed({1'b0,pixel_x}) - WINDOW_RIGHT;
    wire [8:0] dy = line_y - TEXT_Y;
    reg [7:0] character_now, next_char, character_q;
    wire signed [31:0] next_x = text_x + 1;
    function [7:0] mixed_char;
        input integer index;
        begin
            // Chinese slogan followed by the existing ASCII suffix.
            case (index)
                0: mixed_char=8'h89; 1: mixed_char=8'h83; 2: mixed_char=8'h8a;
                3: mixed_char=8'h8b; 4: mixed_char=8'h8b; 5: mixed_char=8'h8c;
                6: mixed_char=" "; 7: mixed_char="F"; 8: mixed_char="P";
                9: mixed_char="G"; 10: mixed_char="A"; 11: mixed_char=" ";
                default: mixed_char=" ";
            endcase
        end
    endfunction
    always @* begin
        character_now = " ";
        if (text_x >= 0 && text_x < text_width)
            character_now = RUNTIME_ENABLE ? runtime_text[(text_x >> 4)*8 +: 8] :
                        CN_ENABLE ? mixed_char(text_x >> 4) :
                        TEXT[(TEXT_LEN-1-(text_x >> 4))*8 +: 8];
        next_char = " ";
        if (next_x >= 0 && next_x < text_width)
            next_char = RUNTIME_ENABLE ? runtime_text[(next_x >> 4)*8 +: 8] :
                        CN_ENABLE ? mixed_char(next_x >> 4) :
                        TEXT[(TEXT_LEN-1-(next_x >> 4))*8 +: 8];
    end
    always @(posedge clk or posedge rst)
        if (rst) character_q <= " ";
        else character_q <= next_char;
    wire [7:0] character = BRAM_FONT ? character_q : character_now;
    assign font_addr = {next_char[6:0], dy[3:0]};
    wire [4:0] glyph;
    wire [15:0] cn_glyph, case_glyph;
    assign cn_glyph = (BRAM_FONT && font_valid) ? font_data : case_glyph;
    wire ascii_supported = (character >= "A" && character <= "Z") ||
        (character >= "0" && character <= "9") || character==" " || character==":" ||
        character=="." || character=="," || character=="!" || character=="?" ||
        character=="-" || character=="_" || character=="/";
    wire [7:0] ascii_char = RUNTIME_ENABLE && !ascii_supported ? "?" : character;
    osd_font_5x7 font(.character(ascii_char), .row(dy[3:1]), .pixels(glyph));
    osd_font_cn_16x16 cn_font(.character(character), .row(dy[3:0]), .pixels(case_glyph));

    wire in_region = ENABLE && subtitle_enabled && started && de && pixel_x >= WINDOW_LEFT && pixel_x < WINDOW_RIGHT &&
                     line_y >= TEXT_Y && line_y < TEXT_Y + 16 && text_x >= 0 && text_x < text_width;
    wire is_cn = character[7:4] == 4'h8;
    wire hit = in_region && (is_cn ? cn_glyph[15-text_x[3:0]] :
               (text_x[3:1] < 5 && dy[3:1] < 7 && glyph[3'd4-text_x[3:1]]));
    assign active = hit;
    assign rgb_out = hit ? 24'hffffff : rgb_in;
endmodule
