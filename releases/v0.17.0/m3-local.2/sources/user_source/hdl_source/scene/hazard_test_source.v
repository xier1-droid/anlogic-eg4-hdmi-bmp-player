`timescale 1ns/1ps
// M3 temporary hazard_layer driver; M4 replaces t_now/stage/alert_level with
// scenario_fsm. Each display commit (media_update, also for the same image)
// restarts the layer: the next frame_start takes the new stage and sets
// t_now=0. Otherwise t_now advances every 2 frames and loops 0..239.
// PIC1-4 = stage 0-3. All outputs change at frame_start.
module hazard_test_source(
 input clk,rst,frame_start,media_update,input [1:0] image_index,
 output reg [5:0] frame_cnt,output reg [7:0] t_now,output reg [1:0] stage,
 output [1:0] alert_level
);
 reg restart,half;
 assign alert_level=stage;
 always @(posedge clk or posedge rst)begin
  if(rst)begin frame_cnt<=0;t_now<=0;stage<=0;restart<=0;half<=0;end
  else begin
   if(media_update)restart<=1'b1;
   if(frame_start)begin
    frame_cnt<=frame_cnt+1'b1;
    if(restart || media_update)begin
     restart<=1'b0;stage<=image_index;t_now<=0;half<=0;
    end else begin
     half<=~half;
     if(half)t_now<=t_now==8'd239 ? 8'd0 : t_now+1'b1;
    end
   end
  end
 end
endmodule
