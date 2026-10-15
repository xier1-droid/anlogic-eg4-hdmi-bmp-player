`timescale 1ns/1ps
// M1: feed real 640x480 32bpp scene BMPs through bmp_scale_stream (1:1) and
// compare every output {RGB,T} with the file's BGRA bytes. Bottom-up file
// rows match the scaler's bottom-up output order, so pixel k is file pixel k.
module tb_m1_card_files;
 parameter FILE_DIR="tools/scenes/demo_village/out/sd";
 reg clk=0,rst=1,start=0,fv=0,fe=0,ready=0;
 always #5 clk=~clk;
 reg [31:0] size,offset;reg [7:0] byte_in;
 wire permit,pv,done;wire [23:0] rgb;wire [7:0] alpha;wire [2:0] error;
 bmp_scale_stream dut(.clk(clk),.rst(rst),.file_start(start),.file_size(size),.file_valid(fv),
  .file_byte(byte_in),.file_byte_offset(offset),.file_end(fe),.upstream_error(8'd0),
  .data_permit(permit),.pixel_valid(pv),.pixel_ready(ready),.pixel_rgb(rgb),
  .done(done),.error(error),.pixel_alpha(alpha));
 reg [7:0] file[0:1228853];
 integer fd,total,pixel_offset,count,cycles=0,done_count,hazard,refuge;
 reg checking=0;reg [31:0] expected;
 always @(negedge clk)begin cycles=cycles+1;ready=cycles%31<20;end
 always @(posedge clk) if(!rst && checking && pv && ready)begin
  expected={file[pixel_offset+count*4+2],file[pixel_offset+count*4+1],file[pixel_offset+count*4],file[pixel_offset+count*4+3]};
  if({rgb,alpha}!==expected)$fatal(1,"pixel %0d got %h/%h expected %h",count,rgb,alpha,expected);
  if(alpha<240)hazard=hazard+1;
  if(alpha==250)refuge=refuge+1;
  count=count+1;
 end
 always @(posedge clk) if(!rst && done)done_count=done_count+1;
 task run_file(input integer n);
 begin
  fd=$fopen($sformatf("%s/PIC%0d.BMP",FILE_DIR,n),"rb");
  if(fd==0)$fatal(1,"cannot open PIC%0d.BMP",n);
  total=$fread(file,fd);$fclose(fd);
  if(total!=1228854)$fatal(1,"PIC%0d size %0d",n,total);
  pixel_offset={file[13],file[12],file[11],file[10]};
  @(negedge clk);rst=1;checking=0;fv=0;fe=0;repeat(3)@(negedge clk);rst=0;
  size=total;count=0;done_count=0;hazard=0;refuge=0;
  checking=1;start=1;@(negedge clk);start=0;
  for(integer i=0;i<total;i=i+1)begin
   if(i%512==0)begin fv=0;while(!permit)@(negedge clk);end
   fv=1;offset=i;byte_in=file[i];@(negedge clk);
  end
  fv=0;fe=1;@(negedge clk);fe=0;
  wait(done_count==1);repeat(5)@(negedge clk);
  if(count!=307200 || error!=0 || done_count!=1)$fatal(1,"PIC%0d completion count=%0d error=%0d",n,count,error);
  checking=0;
  $display("PASS card file PIC%0d.BMP pixels=%0d T<240=%0d T=250=%0d",n,count,hazard,refuge);
 end endtask
 initial begin
  for(integer n=1;n<=4;n=n+1)run_file(n);
  $display("PASS card files");$finish;
 end
 initial begin #2000000000;$fatal(1,"watchdog");end
endmodule
