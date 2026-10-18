`timescale 1ns/1ps
// M5 scenario_fsm: warning mode and speed. warn_async (synchronized) makes
// t_now 239 from the next frame and restarts the stage like a commit on entry
// and exit; scene_on/warn_on follow at frame_start. Speed 0/1/2 steps t once
// per 1600/800/400 accepted samples; a speed raised mid-step takes effect at
// once (the step count is compared with >=).
module tb_m5_fsm;
 reg clk=0;always #20 clk=~clk;
 reg rst=1,scene=0,warn=0,frame_start=0,media_update=0,sample_tick=0,running=0;
 reg [1:0] image=0,speed=0;
 wire [9:0] fc;wire [7:0] t_now;wire [1:0] stage;wire [2:0] hz,role;wire layer,mute,done,scene_on,warn_on;
 scenario_fsm dut(.clk(clk),.rst(rst),.scene_mode_async(scene),.frame_start(frame_start),
  .media_update(media_update),.image_index(image),.image_valid(1'b1),.kinds(24'o43_32_21_14),
  .sample_tick(sample_tick),.audio_running(running),.transition_active(1'b0),.speed(speed),.warn_async(warn),
  .frame_cnt(fc),.t_now(t_now),.stage(stage),.hazard(hz),.role(role),
  .layer_enable(layer),.fade_mute(mute),.stage_done(done),.scene_on(scene_on),.warn_on(warn_on));
 integer checks=0;
 task check(input bit ok,input string what);
  begin if(!ok)$fatal(1,"%s: t=%0d stage=%0d scene_on=%b warn_on=%b mute=%b",what,t_now,stage,scene_on,warn_on,mute);checks++;end
 endtask
 task frame;begin @(negedge clk);frame_start=1;@(negedge clk);frame_start=0;end endtask
 task commit(input [1:0] img);begin @(negedge clk);image=img;media_update=1;@(negedge clk);media_update=0;end endtask
 task samples(input integer n);begin repeat(n)begin @(negedge clk);sample_tick=1;end @(negedge clk);sample_tick=0;end endtask
 task restart_audio;begin @(negedge clk);running=0;repeat(3)@(negedge clk);running=1;repeat(2)@(negedge clk);end endtask
 integer s;
 initial begin
  repeat(3)@(negedge clk);rst=0;running=1;
  scene=1;repeat(3)@(negedge clk);commit(1);restart_audio;frame;
  check(scene_on && !warn_on && stage==1 && t_now==0 && !mute,"scene stage 2 at t=0");
  for(s=0;s<3;s++)begin
   speed=s;frame;
   samples((1600>>s)-1);frame;check(t_now==3*s+0,"one sample short of a step");
   samples(1);frame;check(t_now==3*s+1,"step after 1600>>speed samples");
   samples(2*(1600>>s));frame;check(t_now==3*s+3,"two more steps");
  end
  // Speed raised mid-step: 500 samples at 1x, then 4x steps at once.
  speed=0;samples(500);speed=2;samples(1);frame;check(t_now==10,"faster speed takes effect mid-step");
  // Warning: t 239 from the next frame, restart counted as a new stage.
  warn=1;repeat(3)@(negedge clk);frame;check(warn_on && t_now==0,"warning entry restarts the stage");
  frame;check(t_now==239,"warning holds t=239");
  samples(4000);frame;frame;check(t_now==239 && warn_on,"t stays 239 in the warning mode");
  commit(3);restart_audio;frame;check(stage==3 && t_now==0 && hz==4 && role==3,"warning jump commit");
  frame;check(t_now==239,"t=239 on the last stage");
  warn=0;repeat(3)@(negedge clk);frame;check(!warn_on && t_now==0,"warning exit restarts at t=0");
  samples(400*4);frame;check(t_now==4,"timeline runs again after the warning");
  scene=0;repeat(3)@(negedge clk);frame;check(!scene_on && !layer,"scene exit");
  $display("PASS M5 scenario_fsm: %0d checks",checks);$finish;
 end
 initial begin #100000000;$fatal(1,"watchdog");end
endmodule
