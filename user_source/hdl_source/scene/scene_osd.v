`timescale 1ns/1ps
// M5 scene OSD, the last layer before the HDMI bridge. Like the other OSD
// layers it adds no RGB latency; glyph lookups run two clocks ahead on lead_x
// (pixel_x two clocks earlier on the same line): TEXT byte, then FONT row.
// Scene mode (scene=1, already cleared in thumbnail view):
//   top right  alert block x352-367, title x376+16i, y32-47; progress bar
//              x376-615 y52-55, one pixel per t; dark panel x348-635 y28-59
//   bottom left legend x8+16i y416-431, dark band to its end
//   bottom     subtitle y444-459 in x8-631, moving left 2 pixels per frame
//   the status band (x4-283 y4-27) is shown undimmed (status text is off)
// Warning mode: red 8-pixel frame and red alert block, both blinking.
// Text lines come from TEXT.BIN v1 segments (title 1+stage, subtitle
// 5+stage, legend 10+stage; warning: 0, 9, 13) and need font_ok && text_ok.
// Codes: 00-7F FONT glyph, E0-E7 legend swatch, F0-FF digits/symbols in the
// 5x7 font, others blank. Descriptors are read in vertical blanking.
module scene_osd(
 input clk,rst,
 input vs,de,
 input [9:0] pixel_x,
 input [9:0] lead_x,
 input [23:0] rgb_in,          // after the OSD bands
 input [23:0] rgb_plain,       // the same pixel before the bands
 input scene,warn,             // frame-stable
 input [1:0] stage,
 input [7:0] t_now,
 input [9:0] frame_cnt,
 input font_ok,text_ok,
 output [10:0] font_addr,
 input [15:0] font_data,
 output [11:0] text_addr,
 input [7:0] text_data,
 output [23:0] rgb_out
);
 wire [8:0] y;wire frame_start;
 osd_pixel_position position(.clk(clk),.rst(rst),.vs(vs),.de(de),.line_y(y),.frame_start(frame_start),.first_active());
 localparam [23:0] RED=24'hff2020;
 wire blink_fast=frame_cnt[4],blink_slow=frame_cnt[5];

 // Descriptor {offset lo, offset hi, length, type} of segment n at 4+4n.
 // Step 1 requests byte 3 (N); steps 2-10 the title, subtitle and legend
 // descriptors; each byte is taken one step after its request.
 wire [3:0] seg_t=warn ? 4'd0 : {2'd0,stage}+4'd1;
 wire [3:0] seg_s=warn ? 4'd9 : {2'd0,stage}+4'd5;
 wire [3:0] seg_l=warn ? 4'd13 : {2'd0,stage}+4'd10;
 reg [3:0] fstep,seg_s_q;
 reg [7:0] count,len_t,len_s,len_l;
 reg [11:0] off_t,off_s,off_l,legend_end;
 reg [12:0] scroll;
 reg [5:0] fetch_addr;
 always @* begin
  case(fstep)
   4'd1: fetch_addr=6'd3;
   4'd2,4'd3,4'd4: fetch_addr={seg_t,2'b00}+{2'd0,fstep}+6'd2;
   4'd5,4'd6,4'd7: fetch_addr={seg_s,2'b00}+{2'd0,fstep}-6'd1;
   default: fetch_addr={seg_l,2'b00}+{2'd0,fstep}-6'd4;
  endcase
 end
 wire text_on=scene && font_ok && text_ok;
 wire show_t=text_on && {4'd0,seg_t}<count && len_t!=0;
 wire show_s=text_on && {4'd0,seg_s}<count && len_s!=0;
 wire show_l=text_on && {4'd0,seg_l}<count && len_l!=0;
 always @(posedge clk or posedge rst) begin
  if(rst) begin
   fstep<=0;seg_s_q<=0;count<=0;len_t<=0;len_s<=0;len_l<=0;
   off_t<=0;off_s<=0;off_l<=0;legend_end<=0;scroll<=0;
  end else begin
   if(frame_start) fstep<=4'd1;
   else if(fstep!=0) fstep<=fstep==4'd11 ? 4'd0 : fstep+1'b1;
   case(fstep)
    4'd2: count<=text_data;
    4'd3: off_t[7:0]<=text_data;
    4'd4: off_t[11:8]<=text_data[3:0];
    4'd5: len_t<=text_data;
    4'd6: off_s[7:0]<=text_data;
    4'd7: off_s[11:8]<=text_data[3:0];
    4'd8: len_s<=text_data;
    4'd9: off_l[7:0]<=text_data;
    4'd10: off_l[11:8]<=text_data[3:0];
    4'd11: begin
     len_l<=text_data;legend_end<=12'd12+{text_data,4'b0};
     // A new subtitle segment starts at the right edge of the window.
     seg_s_q<=seg_s;
     if(seg_s!=seg_s_q || !show_s || scroll>=13'd624+{1'b0,len_s,4'b0}) scroll<=0;
     else scroll<=scroll+13'd2;
    end
    default:;
   endcase
  end
 end

 // Stage A (lead_x): line, cell and TEXT address.
 wire on_t=y>=32 && y<48, on_l=y>=416 && y<432, on_s=y>=444 && y<460;
 wire [3:0] row=on_s ? y[3:0]+4'd4 : y[3:0];
 wire [13:0] rel=on_s ? {1'b0,scroll}+{4'd0,lead_x}-14'd632 :
                 on_t ? {4'd0,lead_x}-14'd376 : {4'd0,lead_x}-14'd8;
 wire [7:0] len=on_s ? len_s : on_t ? len_t : len_l;
 wire [11:0] off=on_s ? off_s : on_t ? off_t : off_l;
 wire line_show=on_s ? show_s : on_t ? show_t : on_l && show_l;
 wire a_hit=line_show && !rel[13] && rel[12:4]<{1'b0,len} && lead_x>=8 && lead_x<632;
 assign text_addr=fstep!=0 ? {6'd0,fetch_addr} : off+{4'd0,rel[11:4]};
 // Stage B: the character code selects the FONT row.
 assign font_addr={text_data[6:0],row};
 reg a_q,b_hit;
 reg [3:0] a_col,b_col;
 reg [7:0] b_code;
 always @(posedge clk or posedge rst) begin
  if(rst) begin a_q<=0;b_hit<=0;a_col<=0;b_col<=0;b_code<=0;end
  else begin a_q<=a_hit;a_col<=rel[3:0];b_hit<=a_q;b_col<=a_col;b_code<=text_data;end
 end
 // Stage C (pixel_x): glyph, 5x7 symbol or swatch.
 reg [7:0] ascii;
 always @* begin
  case(b_code[3:0])
   4'ha: ascii=":";4'hb: ascii=".";4'hc: ascii="-";4'hd: ascii="!";4'he: ascii="?";4'hf: ascii=" ";
   default: ascii=8'd48+{4'd0,b_code[3:0]};
  endcase
 end
 wire [4:0] g5;
 osd_font_5x7 font(.character(ascii),.row(row[3:1]),.pixels(g5));
 wire glyph=b_hit && (!b_code[7] ? font_data[4'd15-b_col] :
            b_code[7:4]==4'hf && b_col[3:1]<5 && row[3:1]<7 && g5[3'd4-b_col[3:1]]);
 wire swatch=b_hit && b_code[7:3]==5'b11100 && b_col>=2 && b_col<14 && row>=2 && row<14 &&
             (b_code[2:0]!=3'd2 || blink_slow);
 reg [23:0] swatch_rgb,alert_rgb;
 always @* begin
  case(b_code[2:0])
   3'd0: swatch_rgb=24'hd82020;   // danger
   3'd1: swatch_rgb=24'h20c848;   // route
   3'd2: swatch_rgb=24'h00ff00;   // refuge, blinking
   3'd3: swatch_rgb=24'h8c6a3c;   // mud
   3'd4: swatch_rgb=24'hffd000;   // hidden-danger zone
   3'd5: swatch_rgb=24'he83020;   // fault
   3'd6: swatch_rgb=24'h8e8a84;   // rock
   default: swatch_rgb=24'hc8d2dc; // rain
  endcase
  case(warn ? 2'd3 : stage)
   2'd0: alert_rgb=24'h2080ff;
   2'd1: alert_rgb=24'hffd000;
   2'd2: alert_rgb=24'hff8000;
   default: alert_rgb=RED;
  endcase
 end
 wire panel=scene && de && pixel_x>=348 && pixel_x<636 && y>=28 && y<60;
 wire block=scene && de && pixel_x>=352 && pixel_x<368 && y>=32 && y<48 && (!warn || blink_fast);
 wire bar=scene && de && pixel_x>=376 && pixel_x<616 && y>=52 && y<56;
 wire [9:0] bar_x=pixel_x-10'd376;
 wire legend_band=show_l && de && pixel_x>=4 && {2'd0,pixel_x}<legend_end && y>=412 && y<436;
 wire sub_band=show_s && de && pixel_x>=8 && pixel_x<632 && y>=440 && y<464;
 wire status_area=scene && pixel_x>=4 && pixel_x<284 && y>=4 && y<28;
 wire frame=scene && warn && blink_fast && de && (pixel_x<8 || pixel_x>=632 || y<8 || y>=472);
 wire [23:0] base=status_area ? rgb_plain : rgb_in;
 assign rgb_out=frame ? RED :
                glyph ? 24'hffffff :
                swatch ? swatch_rgb :
                block ? alert_rgb :
                bar ? (bar_x[7:0]<=t_now ? alert_rgb : 24'h404040) :
                (panel || legend_band || sub_band) ? {1'b0,base[23:17],1'b0,base[15:9],1'b0,base[7:1]} :
                base;
endmodule
