`timescale 1ns/1ps
// M4 scene timeline in the pixel domain; replaces hazard_test_source.
// The stage is the displayed image: the SD domain moves between stages
// through the ordinary next/AUTO image requests and their transition, and
// each display commit (media_update) restarts the stage at the next
// frame_start with t_now=0 and that image's scene kind, as in M3.
// t advances once per (1600>>speed) played samples of the SD audio file
// (1x: 240 steps in 8 s at 48 kHz), or every 2 frames while no file plays,
// and holds at 239. It does not advance while the audio is held muted.
// t_now, stage, kind and layer_enable change only at frame_start.
// fade_mute: in scene mode it follows the picture transition; entering or
// leaving scene mode and each commit in scene mode also hold it until the
// audio file has stopped and started again (the stage file has been
// switched) or MUTE_FRAMES frames have passed, e.g. no file or the BGM
// fallback, which keeps playing.
// M5 warning mode (warn_async, SD domain level, only in scene mode): t_now
// holds 239; entering or leaving it restarts the stage like a commit.
// scene_on/warn_on are the frame-stable copies for the OSD.
module scenario_fsm #(
 parameter integer SAMPLE_STEP=1600,
 parameter integer MUTE_FRAMES=30
)(
 input clk,rst,
 input scene_mode_async,          // SD domain level, synchronized here
 input frame_start,
 input media_update,input [1:0] image_index,input image_valid,
 input [23:0] kinds,
 input sample_tick,               // a sample of the SD audio file was accepted
 input audio_running,             // that file is playing (player active)
 input transition_active,
 input [1:0] speed,               // 0:1x 1:2x 2:4x
 input warn_async,                // SD domain level, synchronized here
 output reg [9:0] frame_cnt,output reg [7:0] t_now,output reg [1:0] stage,
 output reg [2:0] hazard,role,
 output reg layer_enable,
 output fade_mute,
 output reg stage_done,           // scene mode and t_now==239
 output reg scene_on,warn_on
);
 (* ASYNC_REG = "TRUE" *) reg [1:0] scene_sync,warn_sync;
 wire scene=scene_sync[1];
 wire warn=warn_sync[1];
 reg scene_q,warn_q,restart,half,hold,saw_stop;
 reg [7:0] t_next;
 reg [10:0] sample_count;
 reg [4:0] hold_frames;
 wire [5:0] kind=kinds[image_index*6+:6];
 wire [10:0] sample_last=(SAMPLE_STEP>>speed)-1;
 wire scene_change=scene!=scene_q;
 assign fade_mute=hold || (scene_q && transition_active);
 always @(posedge clk or posedge rst)begin
  if(rst)begin
   scene_sync<=0;scene_q<=0;frame_cnt<=0;t_now<=0;t_next<=0;stage<=0;hazard<=0;role<=0;
   warn_sync<=0;warn_q<=0;scene_on<=0;warn_on<=0;
   layer_enable<=0;stage_done<=0;restart<=0;half<=0;hold<=0;saw_stop<=0;
   sample_count<=0;hold_frames<=0;
  end else begin
   scene_sync<={scene_sync[0],scene_mode_async};
   scene_q<=scene;
   warn_sync<={warn_sync[0],warn_async};
   warn_q<=warn;
   if(media_update || scene_change || warn!=warn_q)restart<=1'b1;
   if(scene_change || (scene && media_update))begin
    hold<=1'b1;saw_stop<=!audio_running;hold_frames<=0;
   end else if(hold)begin
    if(!audio_running)saw_stop<=1'b1;
    if((saw_stop && audio_running) || hold_frames==MUTE_FRAMES)hold<=1'b0;
    else if(frame_start)hold_frames<=hold_frames+1'b1;
   end
   if(!hold && t_next!=8'd239)begin
    if(audio_running)begin
     if(sample_tick)begin
      if(sample_count>=sample_last)begin sample_count<=0;t_next<=t_next+1'b1;end
      else sample_count<=sample_count+1'b1;
     end
    end else if(frame_start)begin
     half<=~half;
     if(half)t_next<=t_next+1'b1;
    end
   end
   if(frame_start)begin
    frame_cnt<=frame_cnt+1'b1;
    layer_enable<=scene && image_valid;
    scene_on<=scene;warn_on<=warn;
    if(restart || media_update || scene_change)begin
     restart<=1'b0;stage<=image_index;{hazard,role}<=kind;
     t_now<=0;t_next<=0;half<=0;sample_count<=0;stage_done<=0;
    end else begin
     t_now<=warn ? 8'd239 : t_next;

     stage_done<=scene && t_next==8'd239;
    end
   end
  end
 end
endmodule
