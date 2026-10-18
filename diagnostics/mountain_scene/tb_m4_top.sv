`timescale 1ns/1ps
// M4 production top wiring (clocks, resets and frame events forced as in
// tb_m3_top): scenario_fsm drives the layer enable and kind from the
// committed image, takes scene mode from the SD-domain key control, mutes
// the master volume through fade_mute on a scene transition, and returns
// stage_done to sd_card_bmp; the M3 test source is out of the build.
module tb_m4_top;
 reg clk=0,pix=0,rst=1;always #5 clk=~clk;always #20 pix=~pix;
 reg fs=0,update=0,scene=0,transition=0,running=0,tick=0;reg [1:0] image=0;
 wire [5:0] seg_sel;wire [7:0] seg_data;
 top dut(.clk(clk),.rst_n(!rst),.key1(1'b1),.key2(1'b1),.key4(1'b1),.sw1(1'b0),.sw2(1'b0),
 .sd_miso(1'b1),.uart_rx(1'b1),.seg_sel(seg_sel),.seg_data(seg_data));
 integer checks=0;
 task check(input bit ok,input string what);begin if(!ok)$fatal(1,"%s",what);checks++;end endtask
 task frame;begin @(negedge pix);fs=1;@(negedge pix);fs=0;end endtask
 initial begin
  force dut.video_clk=pix;force dut.sd_card_clk=clk;force dut.rst_video=rst;force dut.rst_sd=rst;
  force dut.sub_frame_start=fs;force dut.audio_update=update;force dut.audio_image=image;force dut.audio_enable=1'b1;
  force dut.scene_kinds=24'o43_32_21_14;force dut.scene_mode_sd=scene;force dut.transition_active=transition;
  force dut.bgm_active=running;force dut.bgm_valid=tick;force dut.bgm_ready=1'b1;
  repeat(5)@(negedge pix);rst=0;repeat(5)@(negedge pix);
  check(!$isunknown(dut.hazard_enable) && dut.g_scenario.u_scenario_fsm.SAMPLE_STEP==1600,"scenario_fsm in the build");
  @(negedge pix);image=2;update=1;@(negedge pix);update=0;frame;
  check(!dut.hazard_enable && dut.hazard_kind_hazard==3 && dut.hazard_kind_role==2,"picture mode: kind follows the image, layer off");
  transition=1;@(negedge pix);check(!dut.u_master_volume.fade_mute,"no mute outside scene mode");transition=0;
  scene=1;repeat(4)@(negedge pix);check(dut.u_master_volume.fade_mute,"scene entry mutes the master volume");
  frame;check(dut.hazard_enable && dut.hazard_t_now==0,"scene mode turns the layer on");
  for(integer i=0;i<31;i++)frame;check(!dut.u_master_volume.fade_mute,"mute released (no audio)");
  for(integer i=0;i<480;i++)frame;check(dut.hazard_t_now==239,"t reaches 239 on frames");
  repeat(4)@(negedge clk);check(dut.sd_card_bmp_m0.scene_stage_done && dut.sd_card_bmp_m0.stage_done_sync[1],"stage_done reaches sd_card_bmp");
  transition=1;@(negedge pix);check(dut.u_master_volume.fade_mute,"scene transition mutes");transition=0;
  @(negedge pix);image=1;update=1;@(negedge pix);update=0;frame;
  check(dut.hazard_t_now==0 && dut.hazard_kind_hazard==2 && dut.hazard_kind_role==1 && !dut.scene_stage_done,"commit restarts stage 2");
  // Audio samples drive t: release the hold through a restart, then 1600 ticks.
  running=1;repeat(3)@(negedge pix);running=0;repeat(3)@(negedge pix);running=1;repeat(3)@(negedge pix);
  check(!dut.u_master_volume.fade_mute,"hold released by audio restart");
  repeat(1600)begin @(negedge pix);tick=1;end @(negedge pix);tick=0;frame;
  check(dut.hazard_t_now==1,"1600 accepted samples step t");
  scene=0;repeat(4)@(negedge pix);frame;check(!dut.hazard_enable,"scene exit turns the layer off");
  $display("PASS M4 production top: %0d checks",checks);$finish;
 end
 initial begin #50000000;$fatal(1,"top watchdog");end
endmodule
