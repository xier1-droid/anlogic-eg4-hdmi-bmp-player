`timescale 1ns/1ps
// M1: bmp_scale_stream carries the 32bpp alpha byte (scene T) beside RGB.
// 24bpp images and letterbox pixels must report alpha FF.
module tb_m1_alpha_stream;
 reg clk=0,rst=1,start=0,fv=0,fe=0,ready=0;
 always #5 clk=~clk;
 reg [31:0] size,offset;reg [7:0] byte_in;
 wire permit,pv,done;wire [23:0] rgb;wire [7:0] alpha;wire [2:0] error;
 bmp_scale_stream dut(.clk(clk),.rst(rst),.file_start(start),.file_size(size),.file_valid(fv),
  .file_byte(byte_in),.file_byte_offset(offset),.file_end(fe),.upstream_error(8'd0),
  .data_permit(permit),.pixel_valid(pv),.pixel_ready(ready),.pixel_rgb(rgb),
  .done(done),.error(error),.pixel_alpha(alpha));
 integer w,h,bpp,stride,total,dw,dh,l,t,count,xx,yy,sx,sy,cycles=0,done_count;
 integer alpha_ff,alpha_other,edge_pixels;
 reg [7:0] header[0:53];reg [23:0] expected;reg [7:0] expected_a;reg checking=0;
 function [23:0] pattern(input integer x,y);pattern={8'(x*7+y),8'(y*3+x/7),8'(x^y)};endfunction
 // Covers every byte value, including 00 and FF, across a row.
 function [7:0] apattern(input integer x,y);apattern=8'(x*5+y*11+3);endfunction
 function [7:0] source(input integer n);
  integer x,y,c;reg [31:0] p;
  begin
   if(n<54)source=header[n];
   else begin x=((n-54)%stride)/bpp;y=h-1-(n-54)/stride;c=((n-54)%stride)%bpp;
    p={apattern(x,y),pattern(x,y)};source=x>=w?8'hee:(p>>(c*8));end
  end
 endfunction
 task put32(input integer at,v);begin for(integer k=0;k<4;k=k+1)header[at+k]=v>>(k*8);end endtask
 always @(negedge clk)begin cycles=cycles+1;ready=cycles%31<20;end
 always @(posedge clk) if(!rst)begin
  if(done)begin done_count=done_count+1;if(count!=307200)$fatal(1,"early done");end
  if(checking && pv && ready)begin
   xx=count%640;yy=479-count/640;expected=0;expected_a=8'hFF;
   if(xx>=l && xx<l+dw && yy>=t && yy<t+dh)begin
    sx=(xx-l)*w/dw;sy=(yy-t)*h/dh;expected=pattern(sx,sy);
    if(bpp==4)expected_a=apattern(sx,sy);
   end else edge_pixels=edge_pixels+1;
   if(rgb!==expected || alpha!==expected_a)
    $fatal(1,"stream %0dbpp %0dx%0d pixel %0d got %h/%h expected %h/%h",bpp*8,w,h,count,rgb,alpha,expected,expected_a);
   if(alpha==8'hFF)alpha_ff=alpha_ff+1;else alpha_other=alpha_other+1;
   count=count+1;
  end
 end
 task run_image(input integer depth,width,height);
 begin
  @(negedge clk);rst=1;checking=0;fv=0;fe=0;repeat(3)@(negedge clk);rst=0;
  bpp=depth/8;w=width;h=height;stride=(w*bpp+3)&~3;total=54+stride*h;size=total;
  count=0;done_count=0;alpha_ff=0;alpha_other=0;edge_pixels=0;
  for(integer k=0;k<54;k=k+1)header[k]=0;
  header[0]="B";header[1]="M";put32(2,total);put32(10,54);put32(14,40);put32(18,w);put32(22,h);header[26]=1;header[28]=depth;
  if(w*480>=h*640)begin dw=640;dh=h*640/w;end else begin dw=w*480/h;dh=480;end
  l=(640-dw)/2;t=(480-dh)/2;
  checking=1;start=1;@(negedge clk);start=0;
  for(integer i=0;i<total;i=i+1)begin
   if(i%512==0)begin fv=0;while(!permit)@(negedge clk);end
   fv=1;offset=i;byte_in=source(i);@(negedge clk);
  end
  fv=0;fe=1;@(negedge clk);fe=0;
  wait(done_count==1);repeat(5)@(negedge clk);
  if(count!=307200 || error!=0 || done_count!=1)$fatal(1,"stream completion");
  if(bpp==3 && alpha_other!=0)$fatal(1,"24bpp alpha not FF");
  if(bpp==4 && alpha_other==0)$fatal(1,"32bpp alpha never varied");
  checking=0;
  $display("PASS alpha stream %0dbpp %0dx%0d bytes=%0d pixels=%0d letterbox=%0d alphaFF=%0d other=%0d",
   depth,w,h,total,count,edge_pixels,alpha_ff,alpha_other);
 end endtask
 initial begin
  // 1:1, enlarge, shrink with letterbox, odd sizes, portrait.
  run_image(32,640,480);run_image(32,160,120);run_image(32,1920,1080);
  run_image(32,801,601);run_image(32,1080,1920);run_image(32,3,91);
  // 24bpp: same pixels, alpha FF everywhere (padding rows included).
  run_image(24,640,480);run_image(24,801,601);run_image(24,1920,1080);
  $display("PASS alpha stream suite");$finish;
 end
 initial begin #2000000000;$fatal(1,"watchdog");end
endmodule
