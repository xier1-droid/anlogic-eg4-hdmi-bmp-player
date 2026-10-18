`timescale 1ns/1ps
// scenario_fsm: stage/kind/t restart on each commit, t from accepted samples
// (1600>>speed per step) or every 2 frames without audio, hold at 239,
// stage_done, layer enable only in scene mode, and fade_mute: transition in
// scene mode, hold on scene entry/exit and on a commit until the audio file
// has stopped and restarted or MUTE_FRAMES frames passed; t frozen meanwhile.
module tb_m4_fsm;
 reg clk=0;always #20 clk=~clk;
 reg rst=1,scene=0,frame_start=0,media_update=0,image_valid=0,sample_tick=0,running=0,transition=0;
 reg [1:0] image=0,speed=0;
 reg [23:0] kinds={6'o43,6'o32,6'o21,6'o14};   // image 3..0
 wire [9:0] fc;wire [7:0] t_now;wire [1:0] stage;wire [2:0] hz,role;wire layer,mute,done;
 scenario_fsm dut(.clk(clk),.rst(rst),.scene_mode_async(scene),.frame_start(frame_start),
  .media_update(media_update),.image_index(image),.image_valid(image_valid),.kinds(kinds),
  .sample_tick(sample_tick),.audio_running(running),.transition_active(transition),.speed(speed),
  .frame_cnt(fc),.t_now(t_now),.stage(stage),.hazard(hz),.role(role),
  .layer_enable(layer),.fade_mute(mute),.stage_done(done));
 integer checks=0;
 task check(input bit ok,input string what);
  begin if(!ok)$fatal(1,"%s: t=%0d stage=%0d kind=%0d/%0d layer=%b mute=%b done=%b",what,t_now,stage,hz,role,layer,mute,done);checks++;end
 endtask
 task frame;
  begin @(negedge clk);frame_start=1;@(negedge clk);frame_start=0;end
 endtask
 task commit(input [1:0] img);
  begin @(negedge clk);image=img;media_update=1;@(negedge clk);media_update=0;end
 endtask
 // n accepted samples, one per clock.
 task samples(input integer n);
  begin repeat(n)begin @(negedge clk);sample_tick=1;end @(negedge clk);sample_tick=0;end
 endtask
 // Release a commit/entry hold through the audio restart.
 task restart_audio;
  begin @(negedge clk);running=0;repeat(3)@(negedge clk);running=1;repeat(2)@(negedge clk);end
 endtask
 integer i,step;
 initial begin
  repeat(3)@(negedge clk);rst=0;
  // Picture mode: kind/t restart on commit, no layer, no mute, no stage end.
  image_valid=1;running=1;commit(2);frame;
  check(stage==2 && {hz,role}==6'o32 && t_now==0 && !layer && !mute,"picture mode commit");
  transition=1;@(negedge clk);check(!mute,"picture mode transition does not mute");transition=0;
  samples(1600*240);frame;check(t_now==239 && !done && !layer,"picture mode t runs, no stage end");

  // Scene entry: mute hold until the file stops and starts again; the layer
  // turns on at the next frame and t restarts frozen.
  scene=1;repeat(4)@(negedge clk);check(mute,"entry holds mute");
  frame;check(layer && t_now==0 && stage==2,"entry restarts with layer");
  samples(5000);frame;check(t_now==0 && mute,"t frozen while muted");
  restart_audio();check(!mute,"entry hold released by audio restart");

  // 1x: one step per 1600 accepted samples; t changes only at frame_start.
  samples(1599);frame;check(t_now==0,"1599 samples");
  samples(1);check(t_now==0,"t waits for frame_start");frame;check(t_now==1,"1600 samples");
  samples(1600*3+5);frame;check(t_now==4,"4 steps");
  speed=1;samples(800*2);frame;check(t_now==6,"2x");
  speed=2;samples(400*3);frame;check(t_now==9,"4x");
  speed=0;
  // No audio: every second frame.
  // t_now takes the value counted before each frame_start, so the step made
  // on the tenth frame shows one frame later.
  running=0;for(i=0;i<10;i++)frame;check(t_now==13,"frame fallback");
  frame;check(t_now==14,"frame fallback next frame");
  running=1;samples(1600*300);frame;check(t_now==239 && done,"hold at 239 with stage_done");
  frame;frame;check(t_now==239 && done,"stays at 239");

  // Transition in scene mode mutes; a commit restarts and holds until the
  // audio restart; the BGM fallback (no restart) ends the hold by timeout.
  transition=1;@(negedge clk);check(mute,"scene transition mutes");
  commit(1);frame;transition=0;
  check(stage==1 && {hz,role}==6'o21 && t_now==0 && !done && mute,"commit restarts stage 1");
  restart_audio();check(!mute,"commit hold released");
  samples(1600*2);frame;check(t_now==2,"stage 1 runs");
  commit(3);
  for(i=0;i<30;i++)begin frame;check(mute && t_now==0,"timeout hold");end
  frame;check(!mute,"hold timeout after 30 frames");
  check(stage==3 && {hz,role}==6'o43,"stage 3 kind");
  samples(1600);frame;check(t_now==1,"runs after timeout");
  // A same-image commit (rescan) also restarts.
  commit(3);frame;check(t_now==0 && stage==3,"same image commit restarts");
  restart_audio();
  // Not yet valid: no layer.
  image_valid=0;frame;check(!layer,"no layer before image valid");image_valid=1;frame;check(layer,"layer with image valid");

  // Scene exit: hold for the BGM switch, layer off, no stage end.
  samples(1600*240);frame;check(done,"done before exit");
  scene=0;repeat(4)@(negedge clk);check(mute,"exit holds mute");
  frame;check(!layer && !done && t_now==0,"exit");
  restart_audio();check(!mute,"exit hold released");
  transition=1;@(negedge clk);check(!mute,"no transition mute after exit");transition=0;
  check(fc!=0,"frame counter runs");
  $display("PASS M4 scenario_fsm: %0d checks",checks);$finish;
 end
 initial begin #200000000;$fatal(1,"fsm watchdog");end
endmodule
