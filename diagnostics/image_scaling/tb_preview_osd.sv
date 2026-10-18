`timescale 1ns/1ps
module preview_osd_chain(input clk,rst,vs,de,input [9:0] x,input [23:0] rgb,input [1:0] id,input valid,preview,
 output [23:0] out);
 wire [23:0] a,b,c;wire sa,sb,sc;
 status_osd_overlay status(.clk(clk),.rst(rst),.vs(vs),.de(de),.pixel_x(x),.rgb_in(rgb),.image_index(id),
 .image_valid(valid),.auto_enabled(1'b1),.error_code(8'd0),.rgb_out(a),.active(sa));
 scroll_text_overlay #(.CN_ENABLE(1),.RUNTIME_ENABLE(1)) scroll(.clk(clk),.rst(rst),.vs(vs),.de(de),.pixel_x(x),.image_valid(valid),
 .rgb_in(a),.rgb_out(b),.active(sb),.runtime_text(120'h414243),.runtime_length(4'd3),.runtime_enable(!preview),.runtime_text_changed(1'b0),.font_addr(),.font_data(16'd0),.font_valid(1'b0));
 timestamp_osd timer(.clk(clk),.rst(rst),.vs(vs),.de(de),.pixel_x(x),.rgb_in(b),.rgb_out(c),.active(sc));
 osd_alpha_band #(.RUNTIME_ENABLE(1)) band(.clk(clk),.rst(rst),.vs(vs),.de(de),.pixel_x(x),.rgb_in(c),.glyph_active(sa||sb||sc),
 .subtitle_enable(!preview),.rgb_out(out),.active());
endmodule
module tb_preview_osd;
 reg clk=0,rst=1;always #5 clk=~clk;
 wire hs,vs,de;wire [9:0] x;wire [8:0] y;wire frame;
 video_timing_data timing(.video_clk(clk),.rst(rst),.read_req(),.read_req_ack(1'b1),.hs(hs),.vs(vs),.de(de),.video_x(x));
 osd_pixel_position pos(clk,rst,vs,de,y,frame, );
 reg preview=0;reg [1:0] focus=1;reg [3:0] complete=4'b0101;
 reg valid=0;reg [1:0] id=0;integer frames=0,checks=0,ring_pixels=0;
 wire [23:0] raw={x[7:0],y[7:0],8'h60};
 wire thumb,border;wire [1:0] quadrant;
 thumbnail_layout layout(.in_de(de),.pixel_x(x),.pixel_y(y),.focus_index(focus),.image_count(3'd4),
 .image_complete(complete),.thumb_de(thumb),.source_index(quadrant),.source_x(),.source_y(),.focus_border(border));
 wire [23:0] background=preview?(border?24'hffff00:thumb?raw:24'd0):raw;
 integer preview_checks=0,status_pixels=0,timer_pixels=0,restored_scroll=0;
 integer q,lx,ly;
 reg [23:0] base_expected;
 wire rh,rv,rd;wire [9:0] rx;wire [23:0] rr,result,reference;
 audio_ring_overlay ring(clk,rst,hs,vs,de,valid && !preview,x,y,background,5'd17, ,rh,rv,rd,rx,rr);
 preview_osd_chain actual(clk,rst,rv,rd,rx,rr,id,valid,preview,result);
 preview_osd_chain original(clk,rst,vs,de,x,background,id,valid,preview,reference);
 reg [23:0] expected0,expected1;reg [8:0] y0,y1;
 reg valid0,valid1,preview0,preview1;
 always @(posedge clk)begin
  preview0<=preview;preview1<=preview0;expected0<=reference;expected1<=expected0;y0<=y;y1<=y0;valid0<=valid;valid1<=valid0;
 end
 always @(negedge clk)if(!rst)begin
  if(frame)begin
   frames++;
   if(frames==2)begin valid=1;id=1;end
   if(frames==3)preview=1;
   if(frames==4)begin focus=3;complete=15;end
   if(frames==5)begin preview=0;id=2;end
   if(frames==6)begin
    if(checks<1000000 || ring_pixels<1000 || preview_checks<500000 || status_pixels==0 || timer_pixels==0 || restored_scroll==0)$fatal(1,"insufficient coverage");
    $display("PASS preview OSD: %0d original pixel comparisons, %0d ring pixels, first-image and image-change",checks,ring_pixels);$finish;
   end
  end
  if(preview && de)begin
   q=(y>=240?2:0)+(x>=320?1:0);lx=x%320;ly=y%240;
   base_expected=q==focus && (lx<2 || lx>=318 || ly<2 || ly>=238)?24'hffff00:complete[q]?raw:24'd0;
   if(background!==base_expected)$fatal(1,"preview black/border/valid mapping");
  end
  if(rd && preview1)begin
   if(actual.sb)$fatal(1,"subtitle visible during preview");
   preview_checks++;
   if(actual.sa)status_pixels++;
   if(actual.sc)timer_pixels++;
  end
  if(frames>=5 && actual.sb)restored_scroll++;
  if(rd)begin
   if(preview1 || !valid1 || rx<424 || rx>615 || y1<214 || y1>405)begin
    if(result!==expected1)$fatal(1,"OSD mismatch x=%0d y=%0d got=%h expected=%h",rx,y1,result,expected1);
    checks++;
   end else if(result!=expected1)ring_pixels++;
  end
 end
 initial begin repeat(4)@(negedge clk);rst=0;end
 initial begin #30000000;$fatal(1,"OSD timeout");end
endmodule
