`timescale 1ns/1ps
// M3 temporary driver: t_now +1 every second frame_start, 239 -> 0 wrap,
// stage/alert follow image_index only at frame_start, frame_cnt counts frames.
module tb_m3_test_source;
 reg clk=0,rst=1,fs=0;reg [1:0] image=0;always #5 clk=~clk;
 wire [5:0] fc;wire [7:0] t;wire [1:0] stage,alert;
 hazard_test_source dut(.clk(clk),.rst(rst),.frame_start(fs),.image_index(image),
  .frame_cnt(fc),.t_now(t),.stage(stage),.alert_level(alert));
 integer frames=0,wraps=0;reg [7:0] want_t=0;reg [1:0] want_stage=0;
 initial begin
  repeat(3)@(negedge clk);rst=0;
  for(integer f=1;f<=1000;f++)begin
   repeat(3)@(negedge clk);
   image=f/300;                             // changes between frame_starts
   @(negedge clk);if(stage!==want_stage)$fatal(1,"stage moved before frame_start");
   fs=1;@(negedge clk);fs=0;
   want_stage=image;
   if(f%2==0)begin if(want_t==239)begin want_t=0;wraps++;end else want_t++;end
   if(t!==want_t || fc!==6'(f) || stage!==want_stage || alert!==want_stage)
    $fatal(1,"frame %0d t=%0d/%0d fc=%0d stage=%0d alert=%0d",f,t,want_t,fc,stage,alert);
   frames++;
  end
  if(wraps!=2)$fatal(1,"wraps %0d",wraps);
  $display("PASS hazard test source frames=%0d wraps=%0d",frames,wraps);$finish;
 end
endmodule
