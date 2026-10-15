`timescale 1ns/1ps
// M3 temporary hazard_layer driver; M4 replaces t_now/stage/alert_level with
// scenario_fsm. Stage follows the displayed image (PIC1-4 = stage 0-3), t_now
// advances every 2 frames and loops 0..239. All outputs change at frame_start.
module hazard_test_source(
 input clk,rst,frame_start,input [1:0] image_index,
 output reg [5:0] frame_cnt,output reg [7:0] t_now,output reg [1:0] stage,
 output [1:0] alert_level
);
 assign alert_level=stage;
 always @(posedge clk or posedge rst)begin
  if(rst)begin frame_cnt<=0;t_now<=0;stage<=0;end
  else if(frame_start)begin
   frame_cnt<=frame_cnt+1'b1;stage<=image_index;
   if(frame_cnt[0])t_now<=t_now==8'd239 ? 8'd0 : t_now+1'b1;
  end
 end
endmodule
