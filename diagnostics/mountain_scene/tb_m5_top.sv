`timescale 1ns/1ps
// M5 production top wiring (clocks, resets and frame events forced as in
// tb_m4_top): the speed item reaches scenario_fsm through its synchronizer
// at frame_start; the SD warning level reaches the FSM (t 239) and the scene
// OSD; scene mode hides the audio ring and the status text and switches the
// FONT BRAM address to the scene OSD; the panel shows the stage or A; the
// loaded flags are synchronized; the HDMI bridge takes the scene OSD output;
// the scan streams FONT/TEXT (TEXT_ENABLE).
module tb_m5_top;
 reg clk=0,pix=0,rst=1;always #5 clk=~clk;always #20 pix=~pix;
 reg fs=0,scene=0,warn=0,fl=0,tl=0;reg [1:0] speed=0,image=3;
 wire [5:0] seg_sel;wire [7:0] seg_data;
 top dut(.clk(clk),.rst_n(!rst),.key1(1'b1),.key2(1'b1),.key4(1'b1),.sw1(1'b0),.sw2(1'b0),
 .sd_miso(1'b1),.uart_rx(1'b1),.seg_sel(seg_sel),.seg_data(seg_data));
 integer checks=0;
 task check(input bit ok,input string what);begin if(!ok)$fatal(1,"%s",what);checks++;end endtask
 task frame;begin @(negedge pix);fs=1;@(negedge pix);fs=0;end endtask
 initial begin
  force dut.video_clk=pix;force dut.sd_card_clk=clk;force dut.rst_video=rst;force dut.rst_sd=rst;
  force dut.sub_frame_start=fs;force dut.audio_update=1'b0;force dut.audio_image=2'd3;force dut.audio_enable=1'b1;
  force dut.scene_kinds=24'o43_32_21_14;force dut.scene_mode_sd=scene;force dut.warn_sd=warn;force dut.speed_src=speed;
  force dut.font_loaded_sd=fl;force dut.text_loaded_sd=tl;force dut.committed_image=image;
  force dut.bgm_active=1'b0;force dut.bgm_valid=1'b0;force dut.bgm_ready=1'b1;force dut.transition_active=1'b0;
  repeat(5)@(negedge pix);rst=0;repeat(5)@(negedge pix);
  check(dut.sd_card_bmp_m0.TEXT_ENABLE==1 && dut.sd_card_bmp_m0.bmp_read_m0.SCAN_TEXT==1,"FONT/TEXT scan enabled");
  check(dut.u_scroll_osd.BRAM_FONT==1,"subtitle reads the FONT BRAM");
  // Speed: synchronized, then taken at frame_start.
  speed=2;repeat(4)@(negedge pix);check(dut.speed_frame==0,"speed waits for frame_start");
  frame;check(dut.speed_frame==2 && dut.g_scenario.u_scenario_fsm.speed==2,"speed reaches scenario_fsm");
  // Loaded flags.
  fl=1;tl=1;repeat(3)@(negedge pix);check(dut.font_ok && dut.text_ok,"loaded flags synchronized");
  // Picture mode: subtitle owns the FONT BRAM, ring and status as before.
  frame;check(!dut.scene_on && dut.u_bin_loader.font_addr===dut.scroll_font_addr,"picture mode: subtitle addresses FONT");
  check(dut.u_audio_ring.enable==(dut.adjust_audio && !dut.adjust_preview),"ring enable unchanged outside scene mode");
  // Scene mode.
  scene=1;repeat(4)@(negedge pix);frame;
  check(dut.scene_on && dut.u_bin_loader.font_addr===dut.scene_font_addr,"scene mode: scene OSD addresses FONT");
  check(!dut.u_audio_ring.enable,"scene mode hides the audio ring");
  check(dut.u_scene_osd.scene==!dut.preview_after_ring[1] && dut.u_parameter_osd.speed_visible,"scene OSD and speed item on");
  check(dut.panel_code==(dut.state_code<4'hd ? 4'd4 : dut.state_code),"panel shows stage 4");
  // Warning.
  warn=1;repeat(4)@(negedge pix);frame;frame;
  check(dut.warn_on && dut.u_scene_osd.warn && dut.hazard_t_now==239,"warning reaches the FSM and the OSD");
  @(negedge clk);check(dut.panel_code==(dut.state_code<4'hd ? 4'ha : dut.state_code),"panel shows A");
  check(dut.u_media_hdmi_audio_bridge.video_rgb===dut.scene_rgb,"HDMI takes the scene OSD output");
  warn=0;scene=0;repeat(4)@(negedge pix);frame;check(!dut.scene_on && !dut.warn_on,"scene exit");
  $display("PASS M5 production top: %0d checks",checks);$finish;
 end
 initial begin #50000000;$fatal(1,"top watchdog");end
endmodule
