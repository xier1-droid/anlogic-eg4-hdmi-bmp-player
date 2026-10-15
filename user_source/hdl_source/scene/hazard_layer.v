`timescale 1ns/1ps
// Hazard layer (02_技术实现.md §4.2, bit contract in tools/scenes/README.md).
// Two clocks from {rgb,T} to rgb_out; the caller delays its syncs by two
// (video_delay SYNC_EXTRA=2). Stage 1 classifies the pixel into one form
// out = operand + k per channel: pass (a+0), mix 1/2 (a>>1 + c>>1),
// mix 3/4 (a>>2 + c>>1 + c>>2) or a constant colour (0 + c). Stage 2 adds.
// t_now/stage/alert_level/enable/thumbnail change only between frames.
module hazard_layer(
 input clk,rst,
 input [23:0] rgb_in,input [7:0] t_in,
 input [7:0] t_now,input [1:0] stage,alert_level,
 input enable,thumbnail,input [5:0] frame_cnt,
 output reg [23:0] rgb_out
);
 localparam [1:0] PASS=2'd0,HALF=2'd1,QUARTER=2'd2,CONST=2'd3;
 // Stage index 0..3 is 阶段 1..4; stage 0 has no hazard colour.
 function [23:0] haz_color(input [1:0] s);
  case(s) 2'd1:haz_color=24'h603818; 2'd2:haz_color=24'h2060ff; default:haz_color=24'h20c040; endcase
 endfunction
 function [23:0] front_color(input [1:0] s);
  case(s) 2'd1:front_color=24'hffe000; 2'd2:front_color=24'hffffff; default:front_color=24'h40ff40; endcase
 endfunction
 function [23:0] k34(input [23:0] c);
  integer i;for(i=0;i<3;i=i+1)k34[i*8+:8]=(c[i*8+:8]>>1)+(c[i*8+:8]>>2);
 endfunction
 function [23:0] k12(input [23:0] c);
  integer i;for(i=0;i<3;i=i+1)k12[i*8+:8]=c[i*8+:8]>>1;
 endfunction

 wire covered=t_in<8'd240 && t_in<=t_now;
 wire front=covered && (t_now-t_in)<8'd6;
 wire spot=t_in==8'd250;
 wire haz=stage!=2'd0;
 wire blink_fast=alert_level==2'd3 ? frame_cnt[2] : alert_level==2'd2 ? frame_cnt[3] : frame_cnt[4];
 wire blink_slow=frame_cnt[5];
 reg [1:0] form;reg [23:0] k;
 always @* begin
  form=PASS;k=24'd0;
  if(enable && !thumbnail)begin
   if(haz && front)begin
    if(blink_fast)begin form=CONST;k=front_color(stage);end
    else begin form=QUARTER;k=k34(haz_color(stage));end
   end else if(haz && covered)begin
    if(stage==2'd2)begin form=HALF;k=k12(haz_color(stage));end
    else begin form=QUARTER;k=k34(haz_color(stage));end
   end else if(spot && blink_slow)begin form=CONST;k=24'h00ff00;end
  end
 end

 reg [23:0] rgb_q,k_q;reg [1:0] form_q;
 function [7:0] operand(input [7:0] a,input [1:0] f);
  case(f) PASS:operand=a; HALF:operand=a>>1; QUARTER:operand=a>>2; default:operand=8'd0; endcase
 endfunction
 integer ch;
 always @(posedge clk or posedge rst)begin
  if(rst)begin rgb_q<=0;k_q<=0;form_q<=PASS;rgb_out<=0;end
  else begin
   rgb_q<=rgb_in;k_q<=k;form_q<=form;
   // Each sum stays below 256: a>>1 + c>>1 <= 254, a>>2 + 3c/4 <= 254.
   for(ch=0;ch<3;ch=ch+1)rgb_out[ch*8+:8]<=operand(rgb_q[ch*8+:8],form_q)+k_q[ch*8+:8];
  end
 end
endmodule
