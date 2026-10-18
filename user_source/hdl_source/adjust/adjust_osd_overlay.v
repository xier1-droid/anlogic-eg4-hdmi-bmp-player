module adjust_osd_overlay #(parameter ENABLE=1)(
 input clk,rst,vs,de,input [9:0] pixel_x,input [23:0] rgb_in,
 input [1:0] mode,selected,input [7:0] brightness,contrast,input [3:0] volume_level,
 output [23:0] rgb_out,output active,
 // Scene speed item "S:1X/2X/4X" after V, shown with speed_visible.
 input [1:0] speed,input speed_visible
);
 wire [8:0] y;wire frame_start;
 osd_pixel_position position(.clk(clk),.rst(rst),.vs(vs),.de(de),.line_y(y),.frame_start(frame_start),.first_active());
 wire [9:0] dx=pixel_x-10'd8;wire [8:0] dy=y-9'd32;
 wire visible=ENABLE && (mode==1 || mode==2);
 wire region=visible && de && pixel_x>=8 && (pixel_x<296 || (speed_visible && pixel_x<376)) && y>=32 && y<48;
 wire band=visible && de && pixel_x>=4 && (pixel_x<300 || (speed_visible && pixel_x<380)) && y>=28 && y<52;
 // Shared eight-step binary-to-BCD converter runs in vertical blanking.
 // Values are frame-stable; all three fields finish long before text line 32.
 reg [11:0] b_bcd,c_bcd,v_bcd;
 reg [19:0] shift;
 reg [1:0] phase;
 reg [2:0] bit_count;
 reg [19:0] corrected;
 always @*begin
  corrected=shift;
  if(shift[11:8]>=5)corrected[11:8]=shift[11:8]+4'd3;
  if(shift[15:12]>=5)corrected[15:12]=shift[15:12]+4'd3;
  if(shift[19:16]>=5)corrected[19:16]=shift[19:16]+4'd3;
 end
 wire [19:0] shifted=corrected<<1;
 wire [7:0] volume={4'd0,volume_level}*8'd10;
 always @(posedge clk or posedge rst)begin
  if(rst)begin b_bcd<=12'h128;c_bcd<=12'h128;v_bcd<=12'h100;shift<=0;phase<=3;bit_count<=0;end
  else if(frame_start)begin shift<={12'd0,brightness};phase<=0;bit_count<=0;end
  else if(phase!=3)begin
   if(bit_count==7)begin
    bit_count<=0;phase<=phase+1'b1;
    case(phase)
     0:begin b_bcd<=shifted[19:8];shift<={12'd0,contrast};end
     1:begin c_bcd<=shifted[19:8];shift<={12'd0,volume};end
     2:begin v_bcd<=shifted[19:8];shift<=0;end
    endcase
   end else begin shift<=shifted;bit_count<=bit_count+1'b1;end
  end
 end
 wire [23:0] b_digits={4'h3,b_bcd[11:8],4'h3,b_bcd[7:4],4'h3,b_bcd[3:0]};
 wire [23:0] c_digits={4'h3,c_bcd[11:8],4'h3,c_bcd[7:4],4'h3,c_bcd[3:0]};
 wire [23:0] v_digits={4'h3,v_bcd[11:8],4'h3,v_bcd[7:4],4'h3,v_bcd[3:0]};
 reg [7:0] character;reg [1:0] item;
 always @*begin
  character=" ";item=3;
  case(dx[8:4])
   0:begin character="B";item=0;end
   1:begin character=":";item=0;end
   2:begin character=b_digits[23:16];item=0;end
   3:begin character=b_digits[15:8];item=0;end
   4:begin character=b_digits[7:0];item=0;end
   6:begin character="C";item=1;end
   7:begin character=":";item=1;end
   8:begin character=c_digits[23:16];item=1;end
   9:begin character=c_digits[15:8];item=1;end
   10:begin character=c_digits[7:0];item=1;end
   12:begin character="V";item=2;end
   13:begin character=":";item=2;end
   14:begin character=v_digits[23:16];item=2;end
   15:begin character=v_digits[15:8];item=2;end
   16:begin character=v_digits[7:0];item=2;end
   17:begin character="%";item=2;end
   19:begin character="S";item=3;end
   20:begin character=":";item=3;end
   21:begin character=speed[1]?"4":speed[0]?"2":"1";item=3;end
   22:begin character="X";item=3;end

  endcase
 end
 wire [4:0] glyph;
 osd_font_5x7 font(.character(character),.row(dy[3:1]),.pixels(glyph));
 assign active=region && dx[3:1]<5 && dy[3:1]<7 && glyph[3'd4-dx[3:1]];
 assign rgb_out=active?(item==selected?24'hffff00:24'hffffff):
  band?{1'b0,rgb_in[23:17],1'b0,rgb_in[15:9],1'b0,rgb_in[7:1]}:rgb_in;
endmodule
