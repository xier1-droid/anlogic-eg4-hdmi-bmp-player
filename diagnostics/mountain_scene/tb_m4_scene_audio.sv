`timescale 1ns/1ps
// sd_card_bmp scene audio (sector model and timing as pcm_audio/tb_pcm_production).
// Each audio file has its own sample pattern, so every player session is
// identified by its first sample and then compared sample by sample. The card
// has PIC1-4, BGM, SND1, SND2, SND4 (no SND3). Checks: BGM outside scene
// mode; long KEY4 switches to the displayed stage's SNDn (KEY1 in scene mode
// is the M5 warning key, covered by tb_m5_scene); KEY2 steps the stage and
// its file, SND3 falling back to BGM;
// scene AUTO advances only after scene_stage_done and never while held;
// rescan in scene mode restarts on SND1; leaving scene mode returns to BGM and
// KEY1; a card without SND keeps BGM playing across stage changes. The stream
// file changes only while stopped; a scan never starts before the audio stops;
// no underrun or overrun. PREVIEW_ENABLE=1 as in production: without preview
// and transitions a rescan leaves rescan_pending set (existing behaviour of
// that unused configuration), which blocks later picture requests.
module tb_m4_scene_audio;
 reg clk=0,pix=0,rst=1;
 always #5 clk=~clk;
 always #20 pix=~pix;
 reg key4=1,key1=1,key2=1,stage_done=0;
 wire req,cancel,done,commit,bvalid,bactive,scene_mode;
 wire preview_request;reg preview_ack=0;
 always @(posedge pix)if(rst)preview_ack<=0;else preview_ack<=preview_request;
 wire bready=1'b1;
 wire signed [15:0] bl,br;
 reg finish=0;
 wire [1:0] image;
 wire image_valid,display_valid;
 sd_card_bmp #(.CLK_FREQ_HZ(1000),.LOAD_TIMEOUT_MS(5000),.AUDIO_ENABLE(1),.PREVIEW_ENABLE(1)) app(
 .clk(clk),.rst(rst),.sdram_ready(1'b1),.key1(key1),.key2(key2),.key4(key4),.mode(2'd0),
 .scene_mode(scene_mode),.scene_stage_done(stage_done),
 .preview_ack(preview_ack),.preview_request(preview_request),.preview_descriptor(),
 .adjust_select(),.adjust_restore(),.adjust_increase(),.adjust_decrease(),
 .state_code(),.sd_debug(),.diagnostics(),.combo_event_count(),.combo_debug_active(),.auto_play_indicator(),.osd_error_code(),
 .bmp_width(16'd1),.bmp_height(16'd1),.display_valid(display_valid),.committed_image(image),.committed_valid(image_valid),.committed_ready(1'b1),
 .write_cancel_req(cancel),.write_cancel_ack(cancel),.source_frame_done(done),.source_frame_error(),
 .frame_error_toggle(1'b0),.frame_memory_error(3'd0),.reader_error(3'd0),.reader_underflow(1'b0),
 .write_finish_toggle(finish),.display_commit_ack(commit),.display_commit_request(commit),
 .transition_pix_clk(pix),.transition_pix_rst(rst),.transition_frame_start(1'b0),.transition_commit_done(1'b0),
 .write_buf_idx(),.disp_buf_idx(),.transition_active(),.transition_level(),.transition_wipe(),
 .write_req(req),.write_req_ack(req),.write_ready(1'b1),.write_en(),.write_data(),.SD_nCS(),.SD_DCLK(),.SD_MOSI(),.SD_MISO(1'b1),.scene_kinds(),
 .bgm_valid(bvalid),.bgm_active(bactive),.bgm_ready(bready),.bgm_left(bl),.bgm_right(br),.warn_mode(),.bin_wr(),.bin_sel(),.bin_addr(),.bin_data(),.font_loaded(),.text_loaded());
 always @(posedge clk)if(rst)finish<=0;else if(done)finish<=~finish;

 reg [7:0] disk[0:16383];
 reg raw_valid=0,raw_end=0;reg [7:0] raw_byte=0;
 wire initialized=!app.sd_local_rst;
 initial begin
  force app.sd_init_done=initialized;force app.sd_init_failed=1'b0;
  force app.sd_sec_read_data=raw_byte;force app.sd_sec_read_data_valid=raw_valid;
  force app.sd_sec_read_end=raw_end;force app.sd_sec_read_failed=1'b0;
 end
 integer pos=0,saved=0,gap=0;reg serving=0,released=1;
 always @(negedge clk)begin
  raw_valid=0;raw_end=0;
  if(rst)begin serving=0;released=1;end
  else if(serving)begin
   if(app.sd_local_rst)$fatal(1,"reset cut physical sector short");
   if(gap)gap--;
   else if(pos<512)begin raw_valid=1;raw_byte=disk[saved*512+pos];pos++;gap=7;end
   else begin raw_end=1;serving=0;end
  end else begin
   if(!app.sd_sec_read)released=1;
   if(app.sd_sec_read && released)begin
    if(app.sd_sec_read_addr>31)$fatal(1,"invalid disk LBA");
    saved=app.sd_sec_read_addr;pos=0;serving=1;released=0;
   end
  end
 end
 // File f (0-3 SND1-4, 4 BGM), 512 samples in clusters 8+2f and 9+2f.
 function signed [15:0] sample_of(input integer f,input integer i);
  sample_of=-15000+f*6000+(i%512)*3;
 endfunction
 task word32(input integer at,input reg [31:0] v);
 begin for(integer j=0;j<4;j++)disk[at+j]=v>>(8*j);end endtask
 task entry(input integer at,input reg [87:0] name,input integer cluster,input integer size);
 begin
  for(integer j=0;j<11;j++)disk[at+j]=name[(10-j)*8+:8];
  disk[at+11]=32;disk[at+26]=cluster;word32(at+28,size);
 end endtask
 task setup(input reg [3:0] snd);
 reg [15:0] value;integer lba,c,e;
 begin
  for(integer j=0;j<16384;j++)disk[j]=0;
  disk[12]=2;disk[13]=1;disk[14]=1;disk[16]=1;
  word32(32,101);word32(36,1);word32(44,2);disk[510]=8'h55;disk[511]=8'haa;
  word32(512+4*2,32'h0fffffff);
  for(integer j=0;j<4;j++)begin
   entry(1024+j*32,{"PIC",8'(49+j),"    BMP"},4+j,58);
   lba=(4+j)*512;disk[lba]="B";disk[lba+1]="M";word32(lba+2,58);disk[lba+10]=54;disk[lba+14]=40;
   disk[lba+18]=1;disk[lba+22]=1;disk[lba+26]=1;disk[lba+28]=24;disk[lba+54]=20+j;
  end
  e=1024+4*32;
  for(integer f=0;f<5;f++)begin
   c=8+2*f;word32(512+4*c,c+1);word32(512+4*(c+1),32'h0fffffff);
   for(integer j=0;j<1024;j++)begin
    value=sample_of(f,j/2);disk[(c+j/512)*512+j%512]=j%2?value[15:8]:value[7:0];
   end
   if(f==4)begin entry(e,"BGM     PCM",c,1024);e+=32;end
   else if(snd[f])begin entry(e,{"SND",8'(49+f),"    PCM"},c,1024);e+=32;end
  end
 end endtask

 // Sessions: a rise of bgm_active; its first sample names the file.
 integer sessions=0,file=-1,n=0,total=0,first;reg was_active=0;
 reg signed [15:0] expected;
 always @(posedge pix)if(!rst)begin
  if(!bactive)begin was_active=0;file=-1;n=0;end
  else begin
   if(!was_active)begin was_active=1;sessions++;file=-1;n=0;end
   if(bvalid && bready)begin
    if(file<0)begin
     first=bl;file=(first+7500)/3000;
     if(file<0 || file>4 || first!=(sample_of(file,0)>>>1))$fatal(1,"session %0d starts with unknown sample %0d",sessions,first);
    end
    expected=sample_of(file,n)>>>1;
    if(bl!==expected || br!==expected)$fatal(1,"file %0d sample %0d got %0d expected %0d",file,n,bl,expected);
    n++;total++;
   end
  end
  if(app.g_audio.u_player.underflow_count || app.g_audio.u_player.output_overrun)$fatal(1,"under/overrun");
 end
 // Sampled after each edge: a slot change in a session needs a stopped stream
 // with the enable already low on the deciding edge.
 reg [2:0] slot_q=4;reg session_q=0,stopped_q=1,run_q=0;
 always @(posedge clk)begin
  #1;
  if(!rst)begin
   if(app.scan_accept && (app.audio_run || !app.audio_stopped || app.a_busy))$fatal(1,"scan accepted before audio stop");
   if(app.play_slot!=slot_q && session_q && (!stopped_q || run_q))
    $fatal(1,"stream file changed while the stream was running");
   if(app.ctrl_request_accept && app.ctrl_auto_load_request && app.scene_mode && app.scene_auto_hold)
    $fatal(1,"scene AUTO advanced while held");
  end
  slot_q=app.play_slot;session_q=app.audio_session;stopped_q=app.audio_stopped;run_q=app.audio_run;
 end
 task press(input integer which,input integer cycles);
 begin
  if(which==1)key1=0;else if(which==2)key2=0;else key4=0;
  repeat(cycles)@(negedge clk);key1=1;key2=1;key4=1;repeat(40)@(negedge clk);
 end endtask
 // Wait for a session of file f with enough samples.
 task expect_file(input integer f,input string what);
 begin
  fork
   begin wait(file==f && n>=300);end
   begin repeat(8000000)@(negedge clk);$fatal(1,"%s: no session of file %0d (now file %0d, %0d samples)",what,f,file,n);end
  join_any
  disable fork;
  $display("  %s: file %0d, session %0d",what,f,sessions);
 end endtask
 task expect_image(input integer i,input string what);
 begin
  fork
   begin wait(image==i && display_valid);end
   begin repeat(200000)@(negedge clk);$fatal(1,"%s: image %0d not committed (image %0d)",what,i,image);end
  join_any
  disable fork;
 end endtask
 integer s0;
 initial begin
  setup(4'b1011);repeat(5)@(negedge clk);rst=0;
  expect_image(0,"first image");
  expect_file(4,"picture mode plays BGM");
  if(scene_mode)$fatal(1,"scene mode after reset");
  press(4,1100);if(!scene_mode)$fatal(1,"long KEY4 did not enter scene mode");
  expect_file(0,"scene stage 1 SND1");
  press(2,100);expect_image(1,"KEY2 stage 2");expect_file(1,"stage 2 SND2");
  press(2,100);expect_image(2,"KEY2 stage 3");expect_file(4,"stage 3 without SND3 falls back to BGM");
  press(2,100);expect_image(3,"KEY2 stage 4");expect_file(3,"stage 4 SND4");
  // AUTO waits for the stage end.
  press(4,100);if(!app.ctrl_auto_play_en || !scene_mode)$fatal(1,"short KEY4 did not toggle AUTO in scene mode");
  repeat(30000)@(negedge clk);if(image!=3)$fatal(1,"scene AUTO advanced before the stage end");
  stage_done=1;expect_image(0,"scene AUTO after the stage end");stage_done=0;
  expect_file(0,"AUTO stage 1 SND1");
  repeat(30000)@(negedge clk);if(image!=0)$fatal(1,"scene AUTO advanced without a new stage end");
  stage_done=1;expect_image(1,"second scene AUTO step");stage_done=0;
  press(4,100);if(app.ctrl_auto_play_en)$fatal(1,"AUTO not turned off");
  expect_file(1,"stage 2 after AUTO");
  // Rescan in scene mode starts again at stage 1.
  press(2,2100);wait(app.scan_busy);wait(!app.scan_busy);
  expect_image(0,"rescan first image");expect_file(0,"rescan in scene mode SND1");
  if(!scene_mode)$fatal(1,"rescan left scene mode");
  // Leave scene mode: BGM and KEY1 previous again.
  press(4,1100);if(scene_mode)$fatal(1,"long KEY4 did not leave scene mode");
  expect_file(4,"exit plays BGM");
  press(1,100);expect_image(3,"KEY1 previous after exit");
  // A card without stage files: BGM keeps playing through scene stages.
  setup(4'b0000);press(2,2100);wait(app.scan_busy);wait(!app.scan_busy);
  expect_image(0,"plain card first image");expect_file(4,"plain card BGM");
  press(4,1100);if(!scene_mode)$fatal(1,"scene mode on plain card");
  repeat(20000)@(negedge clk);s0=sessions;
  press(2,100);expect_image(1,"plain card stage 2");repeat(200000)@(negedge clk);
  if(sessions!=s0 || file!=4)$fatal(1,"BGM restarted on a card without SND");
  $display("PASS M4 scene audio: %0d sessions, %0d exact samples; BGM/SNDn per stage, SND3 fallback, scene AUTO
 gated by stage end, rescan, exit, plain card",sessions,total);
  $finish;
 end
 initial begin #900000000;$fatal(1,"scene audio watchdog scan=%0d stream=%0d file=%0d",app.scan_state,app.g_audio.u_stream.state,file);end
endmodule
