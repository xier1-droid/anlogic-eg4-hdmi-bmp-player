// Two pixel clocks from input to output, including all video sidebands.
module audio_ring_overlay_v017 #(
 parameter integer ENABLE=1,
 parameter integer CENTER_X=520, CENTER_Y=310
)(
 input wire clk,rst,hs,vs,de,enable,
 input wire [9:0] pixel_x,
 input wire [8:0] pixel_y,
 input wire [23:0] rgb_in,
 input wire [4:0] bar_height,
 output wire [6:0] bar_index,
 output reg hs_out,vs_out,de_out,
 output reg [9:0] x_out,
 output reg [23:0] rgb_out
);
 wire nx=pixel_x<CENTER_X, ny=pixel_y<CENTER_Y;
 wire [9:0] dx=nx ? CENTER_X-pixel_x : pixel_x-CENTER_X;
 wire [8:0] dy=ny ? CENTER_Y-pixel_y : pixel_y-CENTER_Y;
 wire in_region=(dx<96 && dy<96);
 wire [13:0] row={7'd0,dy[6:0]};
 wire [13:0] address=in_region ? (row<<6)+(row<<5)+dx[6:0] : 14'd0;
 wire [11:0] geometry;
 audio_ring_rom_v017 rom(.clk(clk),.address(address),.data(geometry));
 reg nx_q,ny_q,visible_q,hs_q,vs_q,de_q;
 reg [9:0] x_q;
 reg [23:0] rgb_q;
 wire [6:0] quadrant_bar={2'b0,geometry[9:5]};
 assign bar_index = nx_q ? (ny_q ? 7'd48+quadrant_bar : 7'd48-quadrant_bar) :
                    (ny_q && quadrant_bar!=0 ? 7'd96-quadrant_bar : quadrant_bar);
 // Six 16-bar hue sectors. A 64-channel floor keeps the colors bright.
 wire [7:0] color_step={2'b0,bar_index[3:0],2'b0}+{1'b0,bar_index[3:0],3'b0};
 wire [7:0] color_rise=8'd64+color_step;
 wire [7:0] color_fall=8'd255-color_step;
 reg [23:0] bar_color;
 always @* begin
  case(bar_index[6:4])
   0: bar_color={8'd255,color_rise,8'd64};
   1: bar_color={color_fall,8'd255,8'd64};
   2: bar_color={8'd64,8'd255,color_rise};
   3: bar_color={8'd64,color_fall,8'd255};
   4: bar_color={color_rise,8'd64,8'd255};
   default: bar_color={8'd255,8'd64,color_fall};
  endcase
 end
 always @(posedge clk or posedge rst) begin
  if(rst) begin
   nx_q<=0;ny_q<=0;visible_q<=0;hs_q<=1;vs_q<=1;de_q<=0;x_q<=0;rgb_q<=0;
   hs_out<=1;vs_out<=1;de_out<=0;x_out<=0;rgb_out<=0;
  end else begin
   nx_q<=nx;ny_q<=ny;visible_q<=ENABLE && enable && de && in_region;
   hs_q<=hs;vs_q<=vs;de_q<=de;x_q<=pixel_x;rgb_q<=rgb_in;
   hs_out<=hs_q;vs_out<=vs_q;de_out<=de_q;x_out<=x_q;
   if(visible_q && geometry[11:10]==1) rgb_out<=24'h000000;
   else if(visible_q && geometry[11:10]==2 && bar_height>=geometry[4:0]) rgb_out<=bar_color;
   else rgb_out<=rgb_q;
  end
 end
endmodule
