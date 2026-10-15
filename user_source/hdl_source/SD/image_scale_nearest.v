`timescale 1ns/1ps
// Bottom-up source and destination streams. One synchronous source line RAM.
// Setup uses bounded repeated subtraction, never a pixel-rate divider.
module image_scale_nearest (
 input clk,rst,start, input [15:0] image_width,image_height,
 input in_valid, output in_ready,
 input [23:0] in_rgb, input [15:0] in_x,in_y,
 output out_valid, input out_ready, output [23:0] out_rgb,
 output reg done,
 // Alpha (scene T) travels with RGB through the same line RAM entry.
 input [7:0] in_alpha, output [7:0] out_alpha
);
 localparam IDLE=0,ASPECT=1,ASPECT_DIV=2,X_DIV=3,Y_DIV=4,SETUP=5,
            ROW=6,CAPTURE=7,FETCH=8,EMIT=9,DRAIN=10;
 reg [3:0] state;
 reg [10:0] sw,sh,dw,dh,left,top,x,y;
 reg [10:0] source_last_x; // Frame-constant row endpoint, computed before capture.
 reg [10:0] right_edge,bottom_edge;
 reg [20:0] dividend;
 reg [10:0] divisor,quotient;
 reg width_fit;
 reg [10:0] xq,xr,yq,yr,sx,xrem,sy,yrem;
 reg [10:0] buffered_y;
 reg row_valid;
 reg [31:0] line [0:1919];
 reg [31:0] ram_pixel;
 // Preserve a combinational delay on the measured short BRAM data path.
 // INIT and EQN both describe identity; this does not add a clock of latency.
 wire [23:0] ram_input_rgb;
 assign ram_input_rgb[23:6]=in_rgb[23:6];
 assign ram_input_rgb[4:0]=in_rgb[4:0];
 (* keep = "true" *) AL_MAP_LUT1 #(.INIT(2'b10),.EQN("A"))
  u_line_data_hold (.o(ram_input_rgb[5]),.a(in_rgb[5]));
 reg pixel_black;
 wire row_inside = y>=top && y<bottom_edge;
 wire col_inside = x>=left && x<right_edge;
 wire [11:0] xsum={1'b0,xrem}+{1'b0,xr};
 wire [11:0] yborrow={1'b0,yrem}+{1'b0,dh}-{1'b0,yr};
 assign in_ready=state==CAPTURE || state==DRAIN;
 assign out_valid=state==EMIT;
 assign out_rgb=pixel_black ? 24'd0 : ram_pixel[31:8];
 assign out_alpha=pixel_black ? 8'hFF : ram_pixel[7:0];
 always @(posedge clk) begin
  if(in_valid && in_ready && state==CAPTURE) line[in_x[10:0]]<={ram_input_rgb,in_alpha};
  if(state==FETCH) ram_pixel<=line[sx];
 end
 always @(posedge clk or posedge rst) begin
  if(rst) begin
   state<=IDLE;source_last_x<=0;right_edge<=0;bottom_edge<=0;sw<=0;sh<=0;dw<=0;dh<=0;left<=0;top<=0;x<=0;y<=0;
   dividend<=0;divisor<=1;quotient<=0;width_fit<=0;
   xq<=0;xr<=0;yq<=0;yr<=0;sx<=0;xrem<=0;sy<=0;yrem<=0;
   buffered_y<=0;row_valid<=0;pixel_black<=1;done<=0;
  end else begin
   done<=0;
   if(start) begin
    sw<=image_width[10:0];sh<=image_height[10:0];source_last_x<=image_width[10:0]-11'd1;
    row_valid<=0;state<=ASPECT;
   end else case(state)
    ASPECT: begin
     width_fit<=sw*21'd480 >= sh*21'd640;
     if(sw*21'd480 >= sh*21'd640) begin dividend<=sh*21'd640;divisor<=sw;end
     else begin dividend<=sw*21'd480;divisor<=sh;end
     quotient<=0;state<=ASPECT_DIV;
    end
    ASPECT_DIV: if(dividend>=divisor) begin dividend<=dividend-divisor;quotient<=quotient+1'b1;end
     else begin
      dw<=width_fit?11'd640:(quotient==0?11'd1:quotient);
      dh<=width_fit?(quotient==0?11'd1:quotient):11'd480;
      dividend<=sw;divisor<=width_fit?11'd640:(quotient==0?11'd1:quotient);
      quotient<=0;state<=X_DIV;
     end
    X_DIV: if(dividend>=divisor) begin dividend<=dividend-divisor;quotient<=quotient+1'b1;end
     else begin xq<=quotient;xr<=dividend[10:0];dividend<=sh;divisor<=dh;quotient<=0;state<=Y_DIV;end
    Y_DIV: if(dividend>=divisor) begin dividend<=dividend-divisor;quotient<=quotient+1'b1;end
     else begin yq<=quotient;yr<=dividend[10:0];state<=SETUP;end
    SETUP: begin
     left<=(11'd640-dw)>>1;top<=(11'd480-dh)>>1;
     right_edge<=((11'd640-dw)>>1)+dw;
     bottom_edge<=((11'd480-dh)>>1)+dh;
     x<=0;y<=479;sx<=0;xrem<=0;
     sy<=sh-yq-(yr!=0);yrem<=yr==0?11'd0:dh-yr;
     state<=ROW;
    end
    ROW: begin
     x<=0;sx<=0;xrem<=0;
     if(!row_inside || (row_valid && buffered_y==sy)) state<=FETCH;
     else state<=CAPTURE;
    end
    CAPTURE: if(in_valid && in_ready && in_x=={5'd0,source_last_x}) begin
     buffered_y<=in_y[10:0];row_valid<=1;
     if(in_y==sy) state<=FETCH;
    end
    FETCH: begin pixel_black<=!row_inside || !col_inside;state<=EMIT;end
    EMIT: if(out_ready) begin
     if(x==639) begin
      if(y==0) begin done<=1;state<=DRAIN;end
      else begin
       y<=y-1'b1;
       if(row_inside && y!=top) begin
        if(yrem<yr) begin sy<=sy-yq-1'b1;yrem<=yborrow[10:0];end
        else begin sy<=sy-yq;yrem<=yrem-yr;end
       end
       state<=ROW;
      end
     end else begin
      x<=x+1'b1;
      if(col_inside) begin
       if(xsum>=dw) begin sx<=sx+xq+1'b1;xrem<=xsum-dw;end
       else begin sx<=sx+xq;xrem<=xsum[10:0];end
      end
      state<=FETCH;
     end
    end
    default: ;
   endcase
  end
 end
endmodule
