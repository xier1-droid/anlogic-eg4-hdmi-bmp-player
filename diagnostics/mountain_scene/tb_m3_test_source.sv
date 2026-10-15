`timescale 1ns/1ps
// M3 temporary driver: t_now +1 every second frame, 239 -> 0 wrap; a display
// commit (media_update) restarts at the next frame_start with t_now=0 and the
// new stage, also when the image is the same or the pulse lands on the
// frame_start clock. frame_cnt counts frames regardless.
module tb_m3_test_source;
 reg clk=0,rst=1,fs=0,mu=0;reg [1:0] image=0;always #5 clk=~clk;
 wire [5:0] fc;wire [7:0] t;wire [1:0] stage,alert;
 hazard_test_source dut(.clk(clk),.rst(rst),.frame_start(fs),.media_update(mu),.image_index(image),
  .frame_cnt(fc),.t_now(t),.stage(stage),.alert_level(alert));
 integer frames=0,wraps=0,restarts=0,since=0;reg [7:0] want_t=0;reg [1:0] want_stage=0;reg pending=0;
 initial begin
  repeat(3)@(negedge clk);rst=0;
  for(integer f=1;f<=2000;f++)begin
   repeat(3)@(negedge clk);
   // Commits at fixed frames: new image, same image, and one on the frame_start clock.
   if(f==300 || f==700 || f==1100)begin image=f/400;mu=1;@(negedge clk);mu=0;pending=1;end
   repeat(2)@(negedge clk);
   if(t!==want_t || stage!==want_stage)$fatal(1,"output moved before frame_start (frame %0d)",f);
   if(f==1500)begin image=3;mu=1;pending=1;end
   fs=1;@(negedge clk);fs=0;mu=0;
   if(pending)begin want_stage=image;want_t=0;since=0;pending=0;restarts++;end
   else begin since++;if(since%2==0)begin if(want_t==239)begin want_t=0;wraps++;end else want_t++;end end
   if(t!==want_t || fc!==6'(f) || stage!==want_stage || alert!==want_stage)
    $fatal(1,"frame %0d t=%0d/%0d fc=%0d stage=%0d/%0d",f,t,want_t,fc,stage,want_stage);
   frames++;
  end
  if(restarts!=4 || wraps==0)$fatal(1,"restarts %0d wraps %0d",restarts,wraps);
  $display("PASS hazard test source frames=%0d restarts=%0d wraps=%0d",frames,restarts,wraps);$finish;
 end
endmodule
