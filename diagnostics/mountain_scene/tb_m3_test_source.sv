`timescale 1ns/1ps
// M3 temporary driver with the scene kind path: the SD-domain kind table
// crosses scene_kind_cdc (SD 100 MHz -> pixel 25 MHz); hazard_test_source
// takes the committed image's {hazard,role} and restarts t_now=0 at the
// first frame_start after each commit (media_update), also for the same
// image or a pulse on the frame_start clock; t_now +1 every second frame
// otherwise, 239 -> 0 wrap; frame_cnt (10 bits) counts every frame.
module tb_m3_test_source;
 reg sclk=0,clk=0,rst=1,fs=0,mu=0;reg [1:0] image=0;reg [23:0] src_kinds=0;
 always #5 sclk=~sclk;always #20 clk=~clk;
 wire [23:0] kinds;wire [9:0] fc;wire [7:0] t;wire [2:0] hz,role;
 scene_kind_cdc cdc(.src_clk(sclk),.src_rst(rst),.src_kinds(src_kinds),.dst_clk(clk),.dst_rst(rst),.dst_kinds(kinds));
 hazard_test_source dut(.clk(clk),.rst(rst),.frame_start(fs),.media_update(mu),.image_index(image),.kinds(kinds),
  .frame_cnt(fc),.t_now(t),.hazard(hz),.role(role));
 integer frames=0,wraps=0,restarts=0,since=0;reg [7:0] want_t=0;reg [5:0] want_kind=0;reg pending=0;
 // Table: image0 landslide/onset, 1 flood/evacuation, 2 none, 3 earthquake/cause.
 localparam [23:0] TABLE={3'd4,3'd1, 6'd0, 3'd3,3'd4, 3'd1,3'd2};
 initial begin
  repeat(3)@(negedge clk);rst=0;
  @(negedge sclk);src_kinds=TABLE;                      // loads finished in the SD domain
  repeat(20)@(negedge clk);
  if(kinds!==TABLE)$fatal(1,"kind table did not cross: %h",kinds);
  for(integer f=1;f<=2000;f++)begin
   repeat(3)@(negedge clk);
   // Commits: new images, the same image again, one on the frame_start clock.
   if(f==300 || f==700 || f==1100 || f==1400)begin image=(f/300)%4;mu=1;@(negedge clk);mu=0;pending=1;end
   repeat(2)@(negedge clk);
   if(t!==want_t || {hz,role}!==want_kind)$fatal(1,"outputs moved before frame_start (frame %0d)",f);
   if(f==1450)begin image=0;mu=1;pending=1;end
   fs=1;@(negedge clk);fs=0;mu=0;
   if(pending)begin want_kind=TABLE[image*6+:6];want_t=0;since=0;pending=0;restarts++;end
   else begin since++;if(since%2==0)begin if(want_t==239)begin want_t=0;wraps++;end else want_t++;end end
   if(t!==want_t || fc!==10'(f) || {hz,role}!==want_kind)
    $fatal(1,"frame %0d t=%0d/%0d fc=%0d kind=%b/%b",f,t,want_t,fc,{hz,role},want_kind);
   frames++;
  end
  if(restarts!=5 || wraps==0)$fatal(1,"restarts %0d wraps %0d",restarts,wraps);
  $display("PASS hazard test source frames=%0d restarts=%0d wraps=%0d",frames,restarts,wraps);$finish;
 end
endmodule
