`timescale 1ns/1ps
// M5 sd_card_bmp with TEXT_ENABLE (sector model, timing and audio checks as
// tb_m4_scene_audio). The scan streams FONT.BIN and TEXT.BIN after the
// picture headers into bin_to_bram_loader; both BRAMs must hold the files
// byte for byte and the loaded flags must rise only after complete files.
// Cards: FONT 3264 B + TEXT 300 B (good); TEXT with a wrong magic; FONT of
// 5000 B (too big) and TEXT of 4096 B; no FONT/TEXT. A rescan clears the
// flags before reloading. bin_wr only while the scan runs.
// Warning mode (KEY1 in scene mode): jumps to the last image and SND4, which
// loops; KEY2 and scene AUTO are held; KEY1 again leaves it on the same
// image; entered on the last image it reloads nothing; leaving scene mode
// ends it. KEY1 outside scene mode is still "previous".
module tb_m5_scene;
 reg clk=0,pix=0,rst=1;
 always #5 clk=~clk;
 always #20 pix=~pix;
 reg key4=1,key1=1,key2=1,stage_done=0;
 wire req,cancel,done,commit,bvalid,bactive,scene_mode,warn_mode;
 wire preview_request;reg preview_ack=0;
 always @(posedge pix)if(rst)preview_ack<=0;else preview_ack<=preview_request;
 wire bready=1'b1;
 wire signed [15:0] bl,br;
 reg finish=0;
 wire [1:0] image;
 wire image_valid,display_valid;
 wire bin_wr,bin_sel,font_loaded,text_loaded;wire [11:0] bin_addr;wire [7:0] bin_data;
 sd_card_bmp #(.CLK_FREQ_HZ(1000),.LOAD_TIMEOUT_MS(5000),.AUDIO_ENABLE(1),.PREVIEW_ENABLE(1),.TEXT_ENABLE(1)) app(
 .clk(clk),.rst(rst),.sdram_ready(1'b1),.key1(key1),.key2(key2),.key4(key4),.mode(2'd0),
 .scene_mode(scene_mode),.scene_stage_done(stage_done),.warn_mode(warn_mode),
 .bin_wr(bin_wr),.bin_sel(bin_sel),.bin_addr(bin_addr),.bin_data(bin_data),.font_loaded(font_loaded),.text_loaded(text_loaded),
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
 .bgm_valid(bvalid),.bgm_active(bactive),.bgm_ready(bready),.bgm_left(bl),.bgm_right(br));
 always @(posedge clk)if(rst)finish<=0;else if(done)finish<=~finish;
 bin_to_bram_loader ram(.wr_clk(clk),.bin_wr(bin_wr),.bin_sel(bin_sel),.bin_addr(bin_addr),.bin_data(bin_data),
  .rd_clk(pix),.font_addr(11'd0),.font_data(),.text_addr(12'd0),.text_data());

 reg [7:0] disk[0:32767];
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
    if(app.sd_sec_read_addr>63)$fatal(1,"invalid disk LBA");
    saved=app.sd_sec_read_addr;pos=0;serving=1;released=0;
   end
  end
 end
 function signed [15:0] sample_of(input integer f,input integer i);
  sample_of=-15000+f*6000+(i%512)*3;
 endfunction
 // File contents of the card under test.
 function [7:0] font_byte(input integer i);font_byte=(i*37+11)^(i>>8);endfunction
 function [7:0] text_byte(input integer i,input integer magic);
  text_byte=i==0 ? "T" : i==1 ? (magic ? "X" : "Y") : i==2 ? 8'd1 : i==3 ? 8'd14 : (i*53+7)^(i>>7);
 endfunction
 task word32(input integer at,input reg [31:0] v);
 begin for(integer j=0;j<4;j++)disk[at+j]=v>>(8*j);end endtask
 task entry(input integer at,input reg [87:0] name,input integer cluster,input integer size);
 begin
  for(integer j=0;j<11;j++)disk[at+j]=name[(10-j)*8+:8];
  disk[at+11]=32;disk[at+26]=cluster;word32(at+28,size);
 end endtask
 // A file of n bytes in consecutive clusters from c (one sector each).
 task chain(input integer c,input integer bytes);
 integer k,last;
 begin
  last=c+(bytes+511)/512-1;
  for(k=c;k<last;k++)word32(512+4*k,k+1);
  word32(512+4*last,32'h0fffffff);
 end endtask
 integer font_size,text_size,text_magic;
 // snd: SND1-4 present; fs/ts: FONT/TEXT size, 0 for none; magic: TEXT "TX".
 task setup(input reg [3:0] snd,input integer fs,input integer ts,input integer magic);
 reg [15:0] value;integer lba,c,e;
 begin
  font_size=fs;text_size=ts;text_magic=magic;
  for(integer j=0;j<32768;j++)disk[j]=0;
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
   c=8+2*f;chain(c,1024);
   for(integer j=0;j<1024;j++)begin
    value=sample_of(f,j/2);disk[(c+j/512)*512+j%512]=j%2?value[15:8]:value[7:0];
   end
   if(f==4)begin entry(e,"BGM     PCM",c,1024);e+=32;end
   else if(snd[f])begin entry(e,{"SND",8'(49+f),"    PCM"},c,1024);e+=32;end
  end
  // FONT from cluster 18 (up to 10 sectors), TEXT from cluster 28.
  if(fs)begin
   chain(18,fs);entry(e,"FONT    BIN",18,fs);e+=32;
   for(integer j=0;j<fs && j<10*512;j++)disk[18*512+j]=font_byte(j);
  end
  if(ts)begin
   chain(28,ts);entry(e,"TEXT    BIN",28,ts);e+=32;
   for(integer j=0;j<ts;j++)disk[28*512+j]=text_byte(j,magic);
  end
 end endtask

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
 integer bin_writes=0;
 always @(posedge clk)if(!rst && bin_wr)begin
  if(!app.scan_busy)$fatal(1,"bin_wr outside the scan");
  if(bin_sel ? text_loaded : font_loaded)$fatal(1,"bin_wr into a file already flagged loaded");
  bin_writes++;
 end
 always @(posedge clk)begin
  #1;
  if(!rst && app.ctrl_request_accept && app.ctrl_auto_load_request && app.scene_mode && app.scene_auto_hold)
   $fatal(1,"scene AUTO advanced while held");
 end
 task press(input integer which,input integer cycles);
 begin
  if(which==1)key1=0;else if(which==2)key2=0;else key4=0;
  repeat(cycles)@(negedge clk);key1=1;key2=1;key4=1;repeat(40)@(negedge clk);
 end endtask
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
 // After a scan: flags and BRAM contents for the current card.
 task check_bins(input string what);
 reg want_font,want_text;
 begin
  want_font=font_size>0 && font_size<=4096;
  want_text=text_size>=4 && text_size<=4096 && text_magic;
  if(font_loaded!==want_font || text_loaded!==want_text)
   $fatal(1,"%s: font_loaded %b text_loaded %b, expected %b %b",what,font_loaded,text_loaded,want_font,want_text);
  if(want_font)for(integer k=0;k<font_size/2;k++)
   if(ram.font_mem[k]!=={font_byte(2*k),font_byte(2*k+1)})$fatal(1,"%s: FONT word %0d = %h",what,k,ram.font_mem[k]);
  if(text_size>=4 && text_size<=4096)for(integer k=0;k<text_size;k++)
   if(ram.text_mem[k]!==text_byte(k,text_magic))$fatal(1,"%s: TEXT byte %0d = %h",what,k,ram.text_mem[k]);
  $display("  %s: font %b text %b, %0d bin writes so far",what,font_loaded,text_loaded,bin_writes);
 end endtask
 // The flags must drop during each rescan before the files load again.
 reg saw_clear=0;
 always @(posedge clk)if(app.scan_busy && !font_loaded && !text_loaded)saw_clear=1;
 task rescan(input string what);
 begin
  saw_clear=0;press(2,2100);wait(app.scan_busy);wait(!app.scan_busy);
  if(!saw_clear)$fatal(1,"%s: flags kept through the rescan",what);
  check_bins(what);
 end endtask
 integer s0;
 initial begin
  setup(4'b1111,3264,300,1);repeat(5)@(negedge clk);rst=0;
  wait(app.scan_busy);wait(!app.scan_busy);check_bins("first scan");
  if(bin_writes!=3264+300)$fatal(1,"bin writes %0d",bin_writes);
  expect_image(0,"first image");expect_file(4,"picture mode plays BGM");
  press(1,100);expect_image(3,"KEY1 previous outside scene mode");
  if(warn_mode)$fatal(1,"warning outside scene mode");
  press(2,100);expect_image(0,"KEY2 next");
  press(4,1100);if(!scene_mode)$fatal(1,"long KEY4 did not enter scene mode");
  expect_file(0,"scene stage 1 SND1");
  // Warning: jump to stage 4, SND4 loops, KEY2 and AUTO held.
  press(1,100);if(!warn_mode)$fatal(1,"KEY1 did not enter the warning mode");
  expect_image(3,"warning jumps to the last image");expect_file(3,"warning plays SND4");
  s0=sessions;wait(file==3 && n>=1300);
  if(sessions!=s0)$fatal(1,"SND4 restarted instead of looping");
  press(2,100);repeat(30000)@(negedge clk);if(image!=3)$fatal(1,"KEY2 moved the stage in the warning mode");
  press(4,100);if(!app.ctrl_auto_play_en)$fatal(1,"AUTO not toggled");
  stage_done=1;repeat(60000)@(negedge clk);if(image!=3)$fatal(1,"AUTO advanced in the warning mode");
  stage_done=0;press(4,100);if(app.ctrl_auto_play_en)$fatal(1,"AUTO not turned off");
  press(1,100);if(warn_mode)$fatal(1,"KEY1 did not leave the warning mode");
  repeat(30000)@(negedge clk);if(image!=3)$fatal(1,"leaving the warning mode moved the image");
  // Entered on the last image: nothing reloads.
  s0=sessions;press(1,100);if(!warn_mode)$fatal(1,"no warning on the last image");
  repeat(60000)@(negedge clk);if(image!=3 || sessions!=s0 || file!=3)$fatal(1,"warning on the last image reloaded");
  press(1,100);press(2,100);expect_image(0,"KEY2 after the warning");expect_file(0,"stage 1 again");
  // Leaving scene mode ends the warning mode.
  press(1,100);expect_image(3,"second warning");
  press(4,1100);if(scene_mode || warn_mode)$fatal(1,"scene exit kept the warning mode");
  expect_file(4,"exit plays BGM");
  // Cards: bad TEXT magic; FONT too big with a full 4096-byte TEXT; none.
  setup(4'b1111,3264,300,0);rescan("TEXT with a wrong magic");
  setup(4'b1111,5000,4096,1);rescan("FONT of 5000 B, TEXT of 4096 B");
  setup(4'b1111,0,0,1);rescan("no FONT/TEXT");
  expect_image(0,"plain card first image");
  setup(4'b1111,3264,300,1);rescan("good card again");
  $display("PASS M5 scene: %0d bin writes, %0d sessions, %0d exact samples; FONT/TEXT load and flags, bad magic, oversize, plain card, rescan; warning jump, SND4 loop, KEY2/AUTO held, exit",
   bin_writes,sessions,total);
  $finish;
 end
 initial begin #1500000000;$fatal(1,"scene watchdog scan=%0d reader=%0d file=%0d",app.scan_state,app.bmp_read_m0.state,file);end
endmodule
