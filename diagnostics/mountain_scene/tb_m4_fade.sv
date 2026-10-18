`timescale 1ns/1ps
// pcm_master_volume fade_mute: gain moves only on accepted samples, by at
// most 14 while muting or fading back in and by at most 256 for volume
// changes; it falls monotonically to 0 under fade_mute and rises
// monotonically back to the volume target; each output equals
// (input*gain)>>>16 with no step larger than the gain step allows.
module tb_m4_fade;
 reg clk=0;always #20 clk=~clk;
 reg rst=1,fade=0,iv=0,ready=1;reg [3:0] level=10;
 reg signed [15:0] l=0,r=0;
 wire ir,ov;wire signed [15:0] ol,orr;
 pcm_master_volume dut(.clk(clk),.rst(rst),.volume_level(level),.fade_mute(fade),
  .in_valid(iv),.in_ready(ir),.in_left(l),.in_right(r),.out_valid(ov),.out_ready(ready),.out_left(ol),.out_right(orr));
 function integer target_of(input [3:0] v);
  case(v)0:target_of=0;1:target_of=6554;2:target_of=13107;3:target_of=19661;4:target_of=26214;
   5:target_of=32768;6:target_of=39322;7:target_of=45875;8:target_of=52429;9:target_of=58982;
   default:target_of=65536;endcase
 endfunction
 integer prev_gain=65536,accepted=0,fade_steps=0,vol_steps=0,checks=0;
 reg fading_model=0;
 reg signed [15:0] pl,pr;
 integer exp_l,exp_r,step,tgt,g;
 // The model mirrors the stated rule: 14 while fade_mute or until the gain is
 // back at the target after a release, otherwise 256.
 always @(posedge clk)if(!rst)begin
  if(iv && ir)begin
   tgt=fade ? 0 : target_of(level);
   step=(fade || fading_model) ? 14 : 256;
   #1;g=dut.gain;
   if(g>prev_gain+step || g<prev_gain-step)$fatal(1,"gain step %0d->%0d limit %0d",prev_gain,g,step);
   if(prev_gain<tgt && (g<prev_gain || g>tgt))$fatal(1,"gain not rising monotonically to %0d: %0d->%0d",tgt,prev_gain,g);
   if(prev_gain>tgt && (g>prev_gain || g<tgt))$fatal(1,"gain not falling monotonically to %0d: %0d->%0d",tgt,prev_gain,g);
   if(prev_gain==tgt && g!=tgt)$fatal(1,"gain left its target");
   exp_l=(integer'(pl)*g)>>>16;exp_r=(integer'(pr)*g)>>>16;
   if(ol!==exp_l || orr!==exp_r || !ov)$fatal(1,"output %0d/%0d expected %0d/%0d",ol,orr,exp_l,exp_r);
   if(step==14 && g!=prev_gain)fade_steps++;
   if(step==256 && g!=prev_gain)vol_steps++;
   if(fade)fading_model=1;else if(g==tgt)fading_model=0;
   prev_gain=g;accepted++;checks++;
  end
 end
 // Inputs change only after acceptance; out_ready stalls at random.
 always @(negedge clk)if(!rst)begin
  ready=$urandom%5!=0;
  if(!iv || ir)begin iv=$urandom%4!=0;pl=$urandom;pr=$urandom;l=pl;r=pr;end
 end
 task samples(input integer n);
  integer start;begin start=accepted;wait(accepted>=start+n);@(negedge clk);end
 endtask
 integer t0,n;
 initial begin
  repeat(3)@(negedge clk);rst=0;
  samples(20);if(dut.gain!=65536)$fatal(1,"initial gain");
  // Full mute and back: 4682 accepted samples each way (about 98 ms).
  @(negedge clk);fade=1;t0=accepted;wait(dut.gain==0);n=accepted-t0;
  if(n<4680 || n>4684)$fatal(1,"mute took %0d samples",n);
  samples(50);if(dut.gain!=0)$fatal(1,"gain left 0 while muted");
  @(negedge clk);fade=0;t0=accepted;wait(dut.gain==65536);n=accepted-t0;
  if(n<4680 || n>4684)$fatal(1,"fade-in took %0d samples",n);
  samples(10);
  // Ordinary volume change keeps 256.
  @(negedge clk);level=5;t0=accepted;wait(dut.gain==32768);n=accepted-t0;
  if(n<127 || n>130)$fatal(1,"volume change took %0d samples",n);
  // Mute reversed half way, a volume change during the fade-in, level 0.
  @(negedge clk);fade=1;samples(1000);@(negedge clk);fade=0;samples(500);
  @(negedge clk);level=8;samples(3000);
  // Volume 0 chosen during a mute: the release keeps the fade step down to 0.
  @(negedge clk);fade=1;samples(200);@(negedge clk);level=0;fade=0;wait(dut.gain==0);samples(2);
  if(dut.fading)$fatal(1,"fade step kept after reaching level 0");
  @(negedge clk);level=10;wait(dut.gain==65536);samples(10);
  if(fade_steps<9000 || vol_steps<300)$fatal(1,"coverage fade=%0d volume=%0d",fade_steps,vol_steps);
  $display("PASS M4 fade: %0d accepted samples checked, %0d fade steps <=14, %0d volume steps <=256, monotonic, exact outputs",checks,fade_steps,vol_steps);
  $finish;
 end
 initial begin #100000000;$fatal(1,"fade watchdog");end
endmodule
