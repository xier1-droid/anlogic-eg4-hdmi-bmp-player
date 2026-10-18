`timescale 1ns/1ps
// Real FIFOs, protected controller and command/DQ SDRAM model, 100/40/25 MHz.
module tb_cache_system;
 parameter SCALE_TEST=0;
 parameter MIXED_TEST=0;
 reg src_clk=0,mem_clk=0,pix_clk=0,rst=1;
 always #5 src_clk=~src_clk;
 always #12.5 mem_clk=~mem_clk;
 always #20 pix_clk=~pix_clk;
 wire shifted; assign #12 shifted=mem_clk;
 reg block_writer=0;
 wire init_done,refresh,busy,wr_en,rd_en,rd_valid,wr_busy,rd_busy;
 wire [20:0] wr_addr,rd_addr; wire [31:0] wr_data,rd_data;
 wire sc,ras,cas,we;wire [1:0] ba;wire [10:0] addr;wire [3:0] dm;tri [31:0] dq;
 sdram controller(.Clk(mem_clk),.Clk_sft(shifted),.Rst(rst),
  .Sdr_init_done(init_done),.Sdr_init_ref_vld(refresh),.Sdr_busy(busy),
  .App_wr_en(wr_en),.App_wr_addr(wr_addr),.App_wr_dm(4'b0),.App_wr_din(wr_data),
  .App_rd_en(rd_en),.App_rd_addr(rd_addr),.Sdr_rd_en(rd_valid),.Sdr_rd_dout(rd_data),
  .SDRAM_CLK(sc),.SDR_CKE(),.SDR_RAS(ras),.SDR_CAS(cas),.SDR_WE(we),
  .SDR_BA(ba),.SDR_ADDR(addr),.SDR_DM(dm),.SDR_DQ(dq));
 sdram_bl4_model memory(.clk(sc),.ras(ras),.cas(cas),.we(we),.ba(ba),.addr(addr),.dm(dm),.dq(dq));
 wire req,src_we,source_done,source_error,cancel;
 wire [31:0] src_data;wire [1:0] write_bank;
 wire ack,finish,cancel_ack,error_toggle,write_ready,refill_priority;wire [2:0] memory_error;
 media_frame_loader loader(.rst(rst),.mem_clk(mem_clk),.write_clk(src_clk),.write_rst(rst),
  .Sdr_init_done(init_done),.Sdr_init_ref_vld(refresh),.Sdr_busy(busy),
  .App_rd_busy(rd_busy || block_writer || (SCALE_TEST && refill_priority)),.O_wr_busy(wr_busy),
  .App_wr_en(wr_en),.App_wr_addr(wr_addr),.App_wr_din(wr_data),.App_wr_dm(),
  .write_req(req),.write_req_ack(ack),.write_cancel_req(cancel),.write_cancel_ack(cancel_ack),
  .write_addr_0(21'd0),.write_addr_1(21'd307200),.write_addr_2(21'd614400),.write_addr_3(21'd921600),
  .write_addr_index(write_bank),.write_len(21'd307200),.write_en(src_we),.write_data(src_data),
  .source_done(source_done),.source_error(source_error),.write_finish(finish),.write_ready(write_ready),
  .error_toggle(error_toggle),.memory_error(memory_error));
 wire display_valid,commit_req; wire [1:0] display_bank;
 reg hold_commit=0,reader_commit_req=0;
 always @(posedge src_clk) if(!hold_commit) reader_commit_req<=commit_req;
 wire commit_ack,read_req,read_ack,consume,read_finish,underflow;
 wire [2:0] reader_error;wire [31:0] pixel_data;
 wire hs0,vs0,de0,hs,vs,de;wire [9:0] x0,x;wire [23:0] rgb;
 video_timing_data timing(.video_clk(pix_clk),.rst(rst),.read_req(read_req),.read_req_ack(read_ack),
  .hs(hs0),.vs(vs0),.de(de0),.video_x(x0));
 video_delay delay_path(.video_clk(pix_clk),.rst(rst),.read_en(consume),.read_data(pixel_data[31:8]),
  .hs(hs0),.vs(vs0),.de(de0),.video_x(x0),.hs_r(hs),.vs_r(vs),.de_r(de),.vout_data(rgb),.video_x_r(x));
 reg suppress_return=0;
 media_frame_reader reader(.rst(rst),.mem_clk(mem_clk),.read_clk(pix_clk),.read_rst(rst),
  .Sdr_init_done(init_done),.Sdr_init_ref_vld(refresh),.Sdr_busy(busy),
  .App_wr_busy(wr_busy),.O_rd_busy(rd_busy),.App_rd_en(rd_en),.App_rd_addr(rd_addr),.refill_priority(refill_priority),
  .Sdr_rd_en(rd_valid && !suppress_return),.Sdr_rd_dout(rd_data),
  .read_req(read_req),.read_req_ack(read_ack),.read_finish(read_finish),
  .display_commit_request(reader_commit_req),.display_commit_ack(commit_ack),
  .read_addr_0(21'd0),.read_addr_1(21'd307200),.read_addr_2(21'd614400),.read_addr_3(21'd921600),
  .read_addr_index(display_bank),.read_len(21'd307200),.read_en(consume),.display_valid(display_valid),
  .read_data(pixel_data),.underflow(underflow),.reader_error(reader_error));
 reg key1=1,key2=1,key4=1;
 reg [1:0] mode=0;
 reg finish_toggle=0;
 always @(posedge mem_clk) if(rst)finish_toggle<=0;else if(finish)finish_toggle<=~finish_toggle;
 wire [3:0] state_code;
 wire [57:0] diagnostics;
 wire [1:0] committed_image,media_id;
 wire committed_valid,committed_ready,media_update,media_enable;
`ifdef TRANSITION_S1
 localparam TRANSITION_TEST=1;
`else
 localparam TRANSITION_TEST=0;
`endif
 wire transition_active,transition_wipe;wire [4:0] transition_level;
 reg transition_vs_q=1;
 wire transition_frame_start=transition_vs_q && !vs;
 always @(posedge pix_clk) if(rst) transition_vs_q<=1;else transition_vs_q<=vs;
`ifdef PCM_S3
 localparam AUDIO_TEST=1;
`else
 localparam AUDIO_TEST=0;
`endif
 wire bgm_valid,bgm_ready,bgm_active;
 wire signed [15:0] bgm_left,bgm_right;
 sd_card_bmp #(.SCALE_ENABLE(SCALE_TEST),.AUDIO_ENABLE(AUDIO_TEST),.TRANSITION_ENABLE(TRANSITION_TEST),.CLK_FREQ_HZ(1000),.LOAD_TIMEOUT_MS(5000),.USE_FRAME_RESULT(1)) app(
  .bgm_valid(bgm_valid),.bgm_ready(bgm_ready),.bgm_active(bgm_active),.bgm_left(bgm_left),.bgm_right(bgm_right),
  .transition_pix_clk(pix_clk),.transition_pix_rst(rst),
  .transition_frame_start(transition_frame_start),.transition_commit_done(media_update),
  .transition_active(transition_active),.transition_level(transition_level),.transition_wipe(transition_wipe),
  .clk(src_clk),.rst(rst),.sdram_ready(init_done),.key1(key1),.key2(key2),.key4(key4),.mode(mode),
  .state_code(state_code),.sd_debug(),.diagnostics(diagnostics),.combo_event_count(),.combo_debug_active(),.auto_play_indicator(),
  .bmp_width(16'd640),.bmp_height(16'd480),.display_valid(display_valid),
  .committed_image(committed_image),.committed_valid(committed_valid),.committed_ready(committed_ready),
  .write_cancel_req(cancel),.write_cancel_ack(cancel_ack),.source_frame_done(source_done),.source_frame_error(source_error),
  .frame_error_toggle(error_toggle),.frame_memory_error(memory_error),.reader_error(reader_error),.reader_underflow(underflow),
  .write_finish_toggle(finish_toggle),.display_commit_ack(commit_ack),.display_commit_request(commit_req),
  .write_buf_idx(write_bank),.disp_buf_idx(display_bank),.write_req(req),.write_req_ack(ack),.write_ready(write_ready),.write_en(src_we),.write_data(src_data),
  .SD_nCS(),.SD_DCLK(),.SD_MOSI(),.SD_MISO(1'b1),.scene_kinds(),.scene_mode(),.scene_stage_done(1'b0)
 ,.warn_mode(),.bin_wr(),.bin_sel(),.bin_addr(),.bin_data(),.font_loaded(),.text_loaded());
 media_commit_cdc cdc(.src_clk(src_clk),.dst_clk(pix_clk),.src_rst(rst),.dst_rst(rst),
  .src_image(committed_image),.src_valid(committed_valid),.src_ready(committed_ready),
  .media_id(media_id),.media_update(media_update),.media_enable(media_enable));
 pcm_media_tone #(.CLOCK_HZ(480000)) tone(.clk(pix_clk),.rst_n(!rst),.enable(media_enable),
  .media_update(media_update),.media_id(media_id),.volume(8'd128),.sample_ready(1'b1),
  .sample_valid(),.sample_left(),.sample_right(),.overflow(),.blip_active());

`ifdef PCM_S3
 `include "cache_pcm_checks.svh"
`else
 assign bgm_ready=1;
`endif

`ifdef TRANSITION_S1
 `include "cache_transition_checks.svh"
`endif
`ifdef OSD_S1
 `include "cache_osd_checks.svh"
`endif

 // Sector-level card service only. FAT32, BMP, both asynchronous FIFOs,
 // protected SDRAM controller and the physical command/DQ model are real RTL.
 localparam FILE_BYTES=921654, FILE_CLUSTERS=MIXED_TEST?96:15, FILE_SPAN=FILE_CLUSTERS*128;
 function integer source_width(input integer i);
  if(!MIXED_TEST)source_width=640;
  else case(i)0:source_width=MIXED_TEST==2?1920:160;1:source_width=801;2:source_width=1920;default:source_width=1080;endcase
 endfunction
 function integer source_height(input integer i);
  if(!MIXED_TEST)source_height=480;
  else case(i)0:source_height=MIXED_TEST==2?1080:120;1:source_height=601;2:source_height=1080;default:source_height=1920;endcase
 endfunction
 function integer source_bytes(input integer i);source_bytes=54+((source_width(i)*3+3)&~3)*source_height(i);endfunction
 function [23:0] displayed_pattern(input integer i,g,n);
  integer w,h,dw,dh,l,t,x,y,srcx,srcy;
  begin
   if(!MIXED_TEST)displayed_pattern=pattern(i,g,n);
   else begin
    w=source_width(i);h=source_height(i);x=n%640;y=479-n/640;
    if(w*480>=h*640)begin dw=640;dh=h*640/w;end else begin dw=w*480/h;dh=480;end
    l=(640-dw)/2;t=(480-dh)/2;displayed_pattern=0;
    if(x>=l && x<l+dw && y>=t && y<t+dh)begin
     srcx=(x-l)*w/dw;srcy=(y-t)*h/dh;
     displayed_pattern={8'(32+i*40+g),8'(h-1-srcy),8'(srcx)};
    end
   end
  end
 endfunction
 integer card_generation=0;
 reg [3:0] card_mask=15;
 reg no_card=0;
 integer short_image=-1,short_left=0,timeout_image=-1;
 reg [7:0] sector_data=0;
 reg sector_valid=0,sector_end=0,sector_failed=0;
 wire card_initialized=!app.sd_local_rst && !no_card;
 initial begin
  force app.sd_init_done=card_initialized;
  force app.sd_init_failed=no_card;
  force app.sd_sec_read_data=sector_data;
  force app.sd_sec_read_data_valid=sector_valid;
  force app.sd_sec_read_end=sector_end;
  force app.sd_sec_read_failed=sector_failed;
 end
 function integer file_id(input integer ordinal);
  integer count;
  begin count=0;file_id=0;
   for(integer i=0;i<4;i=i+1) if(card_mask[i]) begin
    if(count==ordinal)file_id=i;
    count=count+1;
   end
  end
 endfunction
 function [23:0] pattern(input integer id,input integer generation,input integer n);
  pattern={8'(32+id*40+generation),8'(n/640),8'(n%640)};
 endfunction
 function [7:0] byte_at(input integer pos,input integer id,input integer generation);
  reg [23:0] color;
  begin byte_at=0;
   case(pos)
    0:byte_at="B";1:byte_at="M";
    2,3,4,5:byte_at=source_bytes(id)>>(8*(pos-2));
    10:byte_at=54;14:byte_at=40;
    18,19,20,21:byte_at=source_width(id)>>(8*(pos-18));
    22,23,24,25:byte_at=source_height(id)>>(8*(pos-22));
    26:byte_at=1;28:byte_at=24;
    default:if(pos>=54 && pos<source_bytes(id)) begin
     color=pattern(id,generation,(pos-54)/3);
     if(MIXED_TEST)begin
      color={8'(32+id*40+generation),8'((pos-54)/((source_width(id)*3+3)&~3)),8'(((pos-54)%((source_width(id)*3+3)&~3))/3)};
      byte_at=color>>(8*(((pos-54)%((source_width(id)*3+3)&~3))%3));
     end else byte_at=color>>(8*((pos-54)%3));
    end
   endcase
  end
 endfunction
 function [7:0] metadata(input integer lba,input integer off);
  integer entry,part,v,id;
  begin
   metadata=0;v=0;
   if(lba==0) begin
    case(off)
     11:metadata=0;12:metadata=2;13:metadata=128;14:metadata=1;16:metadata=1;
     32,33,34,35:metadata=32'd8389633>>(8*(off-32));
     36,37,38,39:metadata=32'd1024>>(8*(off-36));
     44:metadata=2;510:metadata=8'h55;511:metadata=8'haa;
     default:;
    endcase
   end else if(lba<1025) begin
    entry=(lba-1)*128+off/4;
    if(entry<=2)v=32'h0fffffff;
    else if(entry<3+4*FILE_CLUSTERS)v=((entry-3)%FILE_CLUSTERS==FILE_CLUSTERS-1)?32'h0fffffff:entry+1;
    metadata=v>>(8*(off%4));
   end else if(lba==1025) begin
    id=off/32;part=off%32;
    if(id<4) begin
     case(part)
      0:metadata=card_mask[id]?"P":8'he5;1:metadata="I";2:metadata="C";3:metadata="1"+id;
      4,5,6,7:metadata=" ";8:metadata="B";9:metadata="M";10:metadata="P";11:metadata=8'h20;
      26,27:metadata=(3+id*FILE_CLUSTERS)>>(8*(part-26));
      28,29,30,31:metadata=source_bytes(id)>>(8*(part-28));
      default:;
     endcase
    end
`ifdef PCM_S3
    else if(id==4)begin
     case(part)
      0:metadata="B";1:metadata="G";2:metadata="M";
      3,4,5,6,7:metadata=" ";8:metadata="P";9:metadata="C";10:metadata="M";11:metadata=32;
      26:metadata=70;
      28,29,30,31:metadata=32'd1202>>(8*(part-28));
      default:;
     endcase
    end
`endif
   end
  end
 endfunction
 integer lba,id,base,generation,limit,b,sector_reads=0,picture_reads=0;
 initial forever begin
  @(negedge src_clk);
  if(!rst && app.sd_sec_read) begin
   sector_reads=sector_reads+1;lba=app.sd_sec_read_addr;
   if(!app.bmp_read_m0.adapter.owner)picture_reads=picture_reads+1;
   id=(lba-1153)/FILE_SPAN;base=((lba-1153)%FILE_SPAN)*512;generation=card_generation;limit=512;
   if(lba>=1153 && base==512 && app.bmp_read_m0.state==10 && id==timeout_image) begin
    timeout_image=-1;repeat(16)@(negedge src_clk);
    sector_failed=1;@(negedge src_clk);sector_failed=0;
   end else begin
    if(lba>=1153 && base==512 && app.bmp_read_m0.state==10 && id==short_image && short_left>0) begin
     limit=100;short_left=short_left-1;
    end
    for(b=0;b<limit;b=b+1) begin
     sector_data=(lba<1153)?metadata(lba,b):byte_at(base+b,id,generation);
`ifdef PCM_S3
     if(lba>=9729 && lba<=9731)sector_data=pcm_byte((lba-9729)*512+b);
`endif
     sector_valid=1;@(negedge src_clk);sector_valid=0;
     repeat(7)@(negedge src_clk);
    end
    sector_end=1;@(negedge src_clk);sector_end=0;
   end
   wait(!app.sd_sec_read);repeat(3)@(negedge src_clk);
  end
 end

 integer starts=0,commits=0,frames=0,pixel=0,cues=0,sent=0,completed=0,hits=0;
 integer epoch_writes=0,write_burst=0,read_burst=0,refreshes=0,last_refresh=0,mem_cycles=0;
 integer bank_id[0:3],bank_generation[0:3],start_image[0:127];
 reg [1:0] expected_cue[0:255];
 reg wr_prev=0,rd_prev=0;
 always @(posedge src_clk) if(!rst) begin
  if(app.load_start_pulse) begin
   start_image[starts]=app.load_idx;starts=starts+1;epoch_writes=0;
  end
  if(app.cache_complete) begin
   if(MIXED_TEST)$display("MIXED cached image=%0d time=%0t",app.cache_complete_image,$time);
   bank_id[write_bank]=file_id(app.cache_complete_image);bank_generation[write_bank]=card_generation;
   completed=completed+1;
  end
  if(app.cache_hit)hits=hits+1;
  if(MIXED_TEST && app.timeout_stopped)$fatal(1,"mixed stopped load=%0d parser=%0d fat=%h memory=%0d loaderfault=%0d received=%0d sourcecomplete=%b fifo=%0d",app.load_idx,app.parser_error,app.bmp_read_m0.fat_error,memory_error,loader.source_fault,loader.received,loader.source_complete,loader.fifo_words);
  if(app.diag_commit)commits=commits+1;
  if(committed_valid && committed_ready) begin
   if(!display_valid || committed_image!==app.img_idx || sent>=commits)$fatal(1,"audio association before actual commit");
   expected_cue[sent]=committed_image;sent=sent+1;
  end
 end
 always @(posedge pix_clk) if(!rst && media_update) begin
  if(cues>=sent || media_id!==expected_cue[cues])$fatal(1,"audio CDC wrong image/duplicate");
  cues=cues+1;#1;if(tone.blip_countdown!=4800)$fatal(1,"missing picture tone");
 end
 always @(posedge mem_clk) if(!rst) begin
  if(MIXED_TEST && loader.stalled==65534)$fatal(1,"stall fifo=%0d srcfifo=%0d complete=%b written=%b corestate=%0d count=%0d len=%0d rdpriority=%b rdbusy=%b writerbusy=%b init=%b busy=%b",loader.fifo_words,loader.source_fifo_words,loader.complete_sync,loader.written,loader.writer.state,loader.writer.write_cnt,loader.writer.write_len,refill_priority,rd_busy,wr_busy,init_done,busy);
  if(wr_en) begin
   if(!wr_prev && refresh)$fatal(1,"new write burst during refresh protection");
   if(display_valid && wr_addr/307200==app.current_bank)$fatal(1,"overwriting actual display bank");
   if(wr_addr!==write_bank*307200+(479-epoch_writes/640)*640+epoch_writes%640)
    $fatal(1,"write address/vertical flip at word %0d addr=%0d",epoch_writes,wr_addr);
   epoch_writes=epoch_writes+1;write_burst=write_burst+1;
  end else if(wr_prev) begin
   if(write_burst!=64)$fatal(1,"incomplete write burst %0d",write_burst);write_burst=0;
  end
  if(rd_en) begin
   if(!rd_prev && refresh)$fatal(1,"new read burst during refresh protection");
   read_burst=read_burst+1;
  end else if(rd_prev) begin
   if(read_burst!=64)$fatal(1,"incomplete read burst");read_burst=0;
  end
  if(wr_en && rd_en)$fatal(1,"read/write issue collision");
  wr_prev=wr_en;rd_prev=rd_en;
  if(reader_error!=0 && display_valid)$fatal(1,"reader return/count/overflow error %0d",reader_error);
 end
 always @(posedge sc) begin
  mem_cycles=mem_cycles+1;
  if(init_done && {ras,cas,we}==3'b001) begin
   if(refreshes>0 && mem_cycles-last_refresh!=1100)$fatal(1,"refresh cadence");
   last_refresh=mem_cycles;refreshes=refreshes+1;
  end
 end
 always @(negedge pix_clk) if(!rst && display_valid) begin
  if(underflow)$fatal(1,"unexpected displayed underflow");
  if(de) begin
   if(rgb!==displayed_pattern(bank_id[app.current_bank],bank_generation[app.current_bank],(479-pixel/640)*640+pixel%640))
    $fatal(1,"pixel mismatch bank=%0d image=%0d generation=%0d n=%0d got=%h",app.current_bank,
             bank_id[app.current_bank],bank_generation[app.current_bank],pixel,rgb);
   if(pixel==307199)begin pixel=0;frames=frames+1;if(TRANSITION_TEST && frames%32==0)$display("TRANSITION progress frames=%0d commits=%0d",frames,commits);end else pixel=pixel+1;
  end
 end
 task key_next;begin key2=0;repeat(30)@(negedge src_clk);key2=1;repeat(30)@(negedge src_clk);end endtask
 task key_prev;begin key1=0;repeat(30)@(negedge src_clk);key1=1;repeat(30)@(negedge src_clk);end endtask
 task key_auto;begin key4=0;repeat(30)@(negedge src_clk);key4=1;repeat(30)@(negedge src_clk);end endtask
 task key_rescan;begin key2=0;repeat(2030)@(negedge src_clk);key2=1;repeat(30)@(negedge src_clk);end endtask
 task wait_image(input integer idx);begin wait(app.img_idx==idx && display_valid && !app.foreground_busy && !app.transition_busy);end endtask
 integer saved_starts,saved_reads,saved_commits,saved_bank,saved_frames;
 initial begin
  #200;rst=0;
  if(MIXED_TEST)begin
   wait(app.cache_valid==15 && !app.load_busy);saved_frames=frames;wait(frames>=saved_frames+2);
   for(integer k=1;k<4;k=k+1)begin key_next();wait_image(k);saved_frames=frames;wait(frames>=saved_frames+2);end
   $display("PASS mixed physical system: four dimensions through FAT32/scaler/SDRAM/display frames=%0d",frames);
   $display("PASS cache system: mixed");$finish;
  end
  wait(display_valid && app.load_idx==1 && app.load_busy);
  if(app.cache_valid!=1)$fatal(1,"first image not displayed before background fill");
  key_prev();wait_image(3);
  if(start_image[0]!=0 || start_image[1]!=1 || start_image[2]!=3)$fatal(1,"miss priority did not precede image 2");
  if(TRANSITION_TEST) begin
   // A 32-frame effect lets background preloading finish before fade-in.
   wait(app.cache_valid==15 && !app.load_busy);
  end else begin
   wait(app.load_idx==2 && app.load_start_pulse);repeat(2)@(negedge src_clk);
  end
  saved_starts=starts;
  key_next();wait_image(0);key_next();wait_image(1);
  if(starts!=saved_starts)$fatal(1,"cached switch restarted background read");
  wait(app.cache_valid==15 && !app.load_busy);saved_reads=picture_reads;saved_starts=starts;
  repeat(4)begin saved_commits=commits;key_next();wait(commits>saved_commits);wait(!app.foreground_busy && !app.transition_busy);end
  repeat(4)begin saved_commits=commits;key_prev();wait(commits>saved_commits);wait(!app.foreground_busy && !app.transition_busy);end
  if(starts!=saved_starts || picture_reads!=saved_reads)$fatal(1,"full cache read SD again");
  saved_commits=commits;key_auto();wait(commits>=saved_commits+2);key_auto();wait(!app.foreground_busy && !app.transition_busy);
  if(starts!=saved_starts || picture_reads!=saved_reads)$fatal(1,"AUTO missed full cache");
  $display("PASS integrated cache hits/AUTO: starts=%0d reads=%0d commits=%0d",starts,sector_reads,commits);

  // Rescan while a display target is still crossing to a real frame boundary.
  hold_commit=1;key_next();wait(app.cache_display_request);saved_bank=app.current_bank;
  card_generation=1;card_mask=4'b1011;key_rescan();
  repeat(100)@(negedge src_clk);
  if(app.scan_state!=0 || app.current_bank!=saved_bank)$fatal(1,"rescan reset before pending display ack");
  hold_commit=0;
  wait(bank_generation[app.current_bank]==1 && app.first_image_committed);
  if(app.image_count!=3)$fatal(1,"missing filename list not compacted");
  // Cancel a real background transfer, then build a one-image new directory.
  wait(app.load_idx==1 && app.load_busy);card_generation=2;card_mask=1;key_rescan();
  wait(bank_generation[app.current_bank]==2 && app.first_image_committed);
  wait(!app.load_busy);saved_bank=app.current_bank;
  card_mask=0;key_rescan();wait(!app.scan_busy && app.image_count==0);
  if(!display_valid || app.current_bank!=saved_bank)$fatal(1,"empty card lost old frame");
  no_card=1;key_rescan();wait(!app.scan_busy && app.timeout_stopped);
  if(!display_valid || app.current_bank!=saved_bank)$fatal(1,"failed rescan lost old frame");
  $display("PASS integrated rescan: pending commit, active load, compact/missing/no card preserve old pixels");

  no_card=0;card_mask=3;card_generation=3;short_image=1;short_left=2;key_rescan();
  wait(app.cache_failed==2 && !app.load_busy);
  if(app.cache_valid!=1)$fatal(1,"bad frame cached");
  key_next();wait_image(1);
  if(app.cache_valid!=3 || short_left!=0)$fatal(1,"manual retry failed after drained parser cancellation");
  $display("PASS integrated ordinary failure retry/skip/manual reload with retained FAT32 volume");

  card_mask=7;card_generation=4;timeout_image=2;key_rescan();
  wait(app.timeout_stopped && !app.load_busy);
  if(app.cache_valid!=3)$fatal(1,"timeout invalidated completed cache");
  saved_reads=picture_reads;saved_starts=starts;
  key_next();wait_image(1);key_prev();wait_image(0);
  if(starts!=saved_starts || picture_reads!=saved_reads)$fatal(1,"cached hit after timeout read SD");
  saved_frames=frames;wait(frames>=saved_frames+2);repeat(100)@(negedge src_clk);
  if(cues!=sent || sent!=commits)$fatal(1,"lost/extra picture cue");
  $display("PASS integrated timeout keeps cached manual switching");
  $display("PASS cache system: starts=%0d completions=%0d commits=%0d cues=%0d hits=%0d frames=%0d refreshes=%0d",starts,completed,commits,cues,hits,frames,refreshes);
  $finish;
 end
 initial begin #(TRANSITION_TEST ? 64'd20000000000 : 64'd2500000000);$fatal(1,"cache system watchdog: scan=%0d load=%0d cache=%h stop=%b",app.scan_state,app.u_load_control.state,app.cache_valid,app.timeout_stopped);end
endmodule

// The SPI pin-level driver is covered by its existing protocol/reset suites.
module sd_card_top #(parameter CLK_FREQ_HZ=100000000)(input clk,rst,output SD_nCS,SD_DCLK,SD_MOSI,input SD_MISO,
 output [63:0] sd_debug,output sd_init_failed,sd_sec_read_failed,sd_init_done,
 input sd_sec_read,input [31:0] sd_sec_read_addr,output [7:0] sd_sec_read_data,
 output sd_sec_read_data_valid,sd_sec_read_end,input sd_sec_write,input [31:0] sd_sec_write_addr,
 output [7:0] sd_sec_write_data,output sd_sec_write_data_req,sd_sec_write_end);
 assign sd_debug=0;assign sd_init_failed=0;assign sd_sec_read_failed=0;assign sd_init_done=!rst;
 assign SD_nCS=1;assign SD_DCLK=0;assign SD_MOSI=0;assign sd_sec_read_data=0;assign sd_sec_read_data_valid=0;
 assign sd_sec_read_end=0;assign sd_sec_write_data=0;assign sd_sec_write_data_req=0;assign sd_sec_write_end=0;
endmodule
