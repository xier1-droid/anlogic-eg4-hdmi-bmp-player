`timescale 1ns/1ps
// Hazard layer (02_技术实现.md §4.2, v2 effects; bit contract in
// tools/scenes/README.md and make_scene_pack.hazard_layer_model). Two clocks
// from {rgb,T} to rgb_out; the caller delays its syncs by two (video_delay
// SYNC_EXTRA=2). Stage 1 classifies the pixel into one form
// out = operand(a) + k per channel: pass (a), 3/4 (a>>1 + a>>2), 1/2 (a>>1),
// 1/4 (a>>2) or a constant colour (0), and picks the colour term k; stage 2
// adds. de must accompany rgb_in; x/y count active pixels from frame_start.
// t_now/stage/alert_level/enable/thumbnail change only between frames.
module hazard_layer(
 input clk,rst,
 input [23:0] rgb_in,input [7:0] t_in,input de,frame_start,
 input [7:0] t_now,input [1:0] stage,alert_level,
 input enable,thumbnail,input [5:0] frame_cnt,
 output reg [23:0] rgb_out
);
 localparam [2:0] PASS=3'd0,A75=3'd1,A50=3'd2,A25=3'd3,ZERO=3'd4;
 localparam [23:0] CRACK=24'h180e06,CRACK_TIP=24'hffd000;
 localparam [23:0] MUD=24'h8c6a3c,RIPPLE=24'hc4a874,FOAM=24'hf0e8d6;
 localparam [23:0] ROUTE=24'h20c848,DASH=24'haaffbe,ROUTE_TIP=24'hffffff,ROUTE_TIP_OFF=24'h40ff40;
 localparam [23:0] RAIN=24'hc8d2dc,SPOT=24'h00ff00;
 // Colour terms of the three blends: k=1 c>>2, k=2 c>>1, k=3 c>>1 + c>>2.
 function [23:0] c25(input [23:0] c);
  integer i;for(i=0;i<3;i=i+1)c25[i*8+:8]=c[i*8+:8]>>2;
 endfunction
 function [23:0] c50(input [23:0] c);
  integer i;for(i=0;i<3;i=i+1)c50[i*8+:8]=c[i*8+:8]>>1;
 endfunction
 function [23:0] c75(input [23:0] c);
  integer i;for(i=0;i<3;i=i+1)c75[i*8+:8]=(c[i*8+:8]>>1)+(c[i*8+:8]>>2);
 endfunction

 // Active pixel position of rgb_in.
 reg [9:0] x;reg [8:0] y;reg de_q;
 always @(posedge clk or posedge rst)begin
  if(rst)begin x<=0;y<=0;de_q<=0;end
  else begin
   de_q<=de;x<=de ? x+1'b1 : 10'd0;
   if(frame_start)y<=0;else if(de_q && !de)y<=y+1'b1;
  end
 end

 wire [7:0] age=t_now-t_in;
 wire covered=t_in<8'd240 && t_in<=t_now;
 wire front=covered && age<8'd6;
 wire spot=t_in==8'd250;
 wire fast=alert_level==2'd3 ? frame_cnt[2] : alert_level==2'd2 ? frame_cnt[3] : frame_cnt[4];
 wire slow=frame_cnt[5];
 wire [3:0] wave=t_in[3:0]-frame_cnt[4:1];
 wire ripple=wave<4'd2;
 wire dash=wave[2:0]<3'd3;
 // Rain streaks: slanted columns col = x + y/4, a sparse hash of col, and
 // 12-of-32 dashes falling 8 lines per frame.
 wire [9:0] col=x+y[8:2];
 wire [10:0] prod={col,7'd0}+{col,4'd0}+{col,3'd0}+{col,2'd0}+col;   // col*157 mod 2048
 wire [7:0] h=prod[10:3]^col[7:0];
 wire [4:0] drop=y[4:0]-{frame_cnt[1:0],3'd0}+{col[2:0],2'd0};
 wire rain=stage==2'd0 && h<(8'd4+t_now[7:5]) && drop<5'd12;

 reg [2:0] form;reg [23:0] k;
 always @* begin
  form=PASS;k=24'd0;
  if(enable && !thumbnail && de)begin   // blanking stays black
   if(covered && stage!=2'd0)begin
    case(stage)
     2'd1:begin
      if(front && fast)begin form=ZERO;k=CRACK_TIP;end
      else begin form=A25;k=c75(CRACK);end
     end
     2'd2:begin
      if(front)begin
       if(fast)begin form=A50;k=c50(FOAM);end else begin form=A75;k=c25(FOAM);end
      end else if(age<8'd24)begin form=A75;k=ripple ? c25(RIPPLE) : c25(MUD);end
      else if(age<8'd64)begin form=A50;k=ripple ? c50(RIPPLE) : c50(MUD);end
      else begin form=A25;k=ripple ? c75(RIPPLE) : c75(MUD);end
     end
     default:begin
      if(front)begin form=ZERO;k=fast ? ROUTE_TIP : ROUTE_TIP_OFF;end
      else if(dash)begin form=ZERO;k=DASH;end
      else begin form=A25;k=c75(ROUTE);end
     end
    endcase
   end else if(spot && slow)begin form=ZERO;k=SPOT;end
   else if(rain)begin form=A50;k=c50(RAIN);end
  end
 end

 reg [23:0] rgb_q,k_q;reg [2:0] form_q;
 function [7:0] operand(input [7:0] a,input [2:0] f);
  case(f) PASS:operand=a; A75:operand=(a>>1)+(a>>2); A50:operand=a>>1; A25:operand=a>>2; default:operand=8'd0; endcase
 endfunction
 integer ch;
 always @(posedge clk or posedge rst)begin
  if(rst)begin rgb_q<=0;k_q<=0;form_q<=PASS;rgb_out<=0;end
  else begin
   rgb_q<=rgb_in;k_q<=k;form_q<=form;
   // Every sum stays below 256: the operand and colour weights add to 1.
   for(ch=0;ch<3;ch=ch+1)rgb_out[ch*8+:8]<=operand(rgb_q[ch*8+:8],form_q)+k_q[ch*8+:8];
  end
 end
endmodule
