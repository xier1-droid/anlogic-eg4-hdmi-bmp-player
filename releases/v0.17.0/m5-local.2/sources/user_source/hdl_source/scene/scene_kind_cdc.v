`timescale 1ns/1ps
// Latest-state mailbox for the scene kind table (SD domain -> pixel domain),
// as osd_status_cdc: the held bus stays fixed until the pixel domain
// acknowledges it; changes while busy are coalesced into the next transfer.
// The table changes only when a load succeeds, well before that image can be
// committed for display.
module scene_kind_cdc (
 input src_clk,src_rst,input [23:0] src_kinds,
 input dst_clk,dst_rst,output reg [23:0] dst_kinds
);
 reg [23:0] held;
 reg request,acknowledge;
 (* ASYNC_REG = "TRUE" *) reg [1:0] req_sync,ack_sync;
 always @(posedge src_clk or posedge src_rst)begin
  if(src_rst)begin held<=0;request<=0;ack_sync<=0;end
  else begin
   ack_sync<={ack_sync[0],acknowledge};
   if(request==ack_sync[1] && src_kinds!=held)begin held<=src_kinds;request<=~request;end
  end
 end
 always @(posedge dst_clk or posedge dst_rst)begin
  if(dst_rst)begin req_sync<=0;acknowledge<=0;dst_kinds<=0;end
  else begin
   req_sync<={req_sync[0],request};
   if(req_sync[1]!=acknowledge)begin dst_kinds<=held;acknowledge<=req_sync[1];end
  end
 end
endmodule
