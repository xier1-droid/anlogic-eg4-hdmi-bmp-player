`timescale 1ns/1ps
module tb_audio_stream;
 reg clk=0,rd=0;always #5 clk=~clk;always #19 rd=~rd;
 reg rst=1,enable=0,found=1,images=1,inject=0;reg [31:0] size=1202;
 wire pen,byte_valid;wire [7:0] byte_data,err;wire [31:0] loops;
 wire stop,player_stop,permit,low,fr,sv,active,overrun;wire signed [15:0] left,right;wire [31:0] uf;
 wire ar,ab,av,ad;wire [31:0] al;wire [7:0] ae,data;wire [8:0] idx;
 reg pr=0;wire pb,pv,pd;wire [7:0] pe;
 wire raw_req;wire [31:0] raw_lba;reg [7:0] raw_data=0;reg raw_valid=0,raw_end=0,raw_fail=0;
 wire [9:0] level;
 fat32_pcm_stream source(.clk(clk),.rst_n(!rst),.enable(enable),.audio_found(found),.first_cluster(32'd10),.file_size(size),
 .sectors_per_cluster(8'd1),.fat_start_lba(32'd1),.data_start_lba(32'd100),.max_cluster(32'd100),
 .sector_permit(permit),.player_stopped(player_stop),.player_ready(fr),.player_enable(pen),.file_valid(byte_valid),.file_byte(byte_data),
 .stopped(stop),.error_code(err),.error_flag(),.loop_count(loops),.sector_req(ar),.sector_lba(al),.sector_busy(ab),.sector_valid(av),
 .sector_done(ad),.sector_byte(data),.sector_error(ae),.sector_index(idx));
 pcm_stream_player #(.ADDR_WIDTH(9),.CLOCK_HZ(1000000),.SAMPLE_HZ(48000),.PREFILL(256),.LOW_WATER(128),.HIGH_WATER(384)) player(
 .wr_clk(clk),.wr_rst_n(!rst),.play_enable(pen),.file_valid(byte_valid),.file_byte(byte_data),.file_ready(fr),
 .sector_permit(permit),.buffer_low(low),.stopped(player_stop),.write_level(level),
 .rd_clk(rd),.rd_rst_n(!rst),.sample_ready(1'b1),.sample_valid(sv),.sample_left(left),.sample_right(right),
 .active(active),.underflow_count(uf),.output_overrun(overrun));
 sd_sector_service #(.CLK_FREQ_HZ(100000000),.TIMEOUT_MS(1)) service(
 .clk(clk),.rst(rst),.p_req(pr),.p_lba(32'd200),.p_cancel(1'b0),.p_busy(pb),.p_accepted(),.p_valid(pv),.p_done(pd),.p_error(pe),
 .a_req(ar),.a_lba(al),.a_cancel(1'b0),.a_enable(1'b1),.a_urgent(low),.a_busy(ab),.a_accepted(),.a_valid(av),.a_done(ad),.a_error(ae),
 .sector_byte(data),.sector_index(idx),.sd_sec_read(raw_req),.sd_sec_read_addr(raw_lba),
 .sd_sec_read_data(raw_data),.sd_sec_read_data_valid(raw_valid),.sd_sec_read_end(raw_end),.sd_sec_read_failed(raw_fail));
 function [7:0] media_byte(input integer lba,input integer offset);
 integer at,sample;reg [15:0] val;
 begin
  media_byte=0;
  if(lba==1)begin
   if(offset==40)media_byte=15;
   if(offset==60)media_byte=11;
   if(offset>=44 && offset<=47)media_byte=8'hff;
  end else if(lba==200)media_byte=8'ha5;
  else begin
   case(lba)108:at=offset;113:at=512+offset;109:at=1024+offset;default:begin at=0;$fatal(1,"unexpected audio LBA %0d",lba);end endcase
   sample=at/2;val=sample*62-20000;media_byte=at%2 ? val[15:8]:val[7:0];
  end
 end endfunction
 integer pos=0,pictures=0,reads=0,audio_reads=0;reg serving=0,released=1;reg [31:0] saved_lba;
 always @(negedge clk)begin
  pr=0;raw_valid=0;raw_end=0;raw_fail=0;
  if(rst)begin serving=0;released=1;end
  else begin
   if(images && !pb)pr=1;
   if(!serving)begin
    if(!raw_req)released=1;
    if(raw_req && released)begin saved_lba=raw_lba;pos=0;serving=1;released=0;reads++;if(raw_lba!=200)audio_reads++;end
   end else if(inject && saved_lba==108 && pos==16)begin raw_fail=1;serving=0;end
   else if(pos<512)begin raw_valid=1;raw_data=media_byte(saved_lba,pos);pos++;end
   else begin raw_end=1;serving=0;end
  end
 end
 integer received=0,check_mode=1;reg signed [15:0] expected;
 always @(posedge clk)if(!rst)begin
  if(byte_valid && !fr && source.state==2)$fatal(1,"sector reservation failed at level %0d",level);
  if(pd)begin pictures++;if(pe)$fatal(1,"picture error");end
  if(pv && data!=8'ha5)$fatal(1,"audio bytes leaked to picture");
 end
 always @(posedge rd)if(!rst && sv && check_mode!=0)begin
  expected=check_mode==1 ? ((received%601)*62-20000)/2 :
           check_mode==3 ? ((received%256)*62-20000)/2 : -10000;
  if(left!==expected || right!==expected)$fatal(1,"PCM #%0d got %0d expected %0d mode%0d",received,left,expected,check_mode);
  received++;
 end
 integer old_reads;
 initial begin
  repeat(5)@(negedge clk);rst=0;wait(stop);@(negedge clk);enable=1;
  wait(received>=2500);
  if(loops<4 || pictures<5 || uf!=0 || overrun)$fatal(1,"loop/concurrency status");
  // Stop mid-sector and restart a two-byte file; the old ring must be gone.
  wait(ab && av);@(negedge clk);enable=0;check_mode=0;wait(stop);
  received=0;size=2;check_mode=2;@(negedge clk);enable=1;
  wait(received>=300);if(loops<300 || uf || overrun)$fatal(1,"short file prefill/loop");
  @(negedge clk);enable=0;check_mode=0;wait(stop);
  // Exercise every short-cache write address, including the hold-fixed bit 3.
  received=0;size=512;check_mode=3;@(negedge clk);enable=1;
  wait(received>=600);if(loops<2 || uf || overrun)$fatal(1,"512-byte cache replay");
  @(negedge clk);enable=0;check_mode=0;wait(stop);
  size=1202;inject=1;enable=1;wait(err!=0);wait(!active && player_stop);
  if(err!=8'h10)$fatal(1,"read failure not reported");
  @(negedge clk);enable=0;wait(stop);inject=0;
  old_reads=audio_reads;size=3;enable=1;wait(err!=0);repeat(30)@(negedge clk);
  if(err!=8'h30 || audio_reads!=old_reads)$fatal(1,"odd file accepted");
  enable=0;wait(stop);size=0;enable=1;wait(err!=0);repeat(30)@(negedge clk);
  if(err!=8'h30 || audio_reads!=old_reads)$fatal(1,"empty file accepted");
  enable=0;wait(stop);found=0;size=1202;enable=1;repeat(50)@(negedge clk);
  if(active || err || audio_reads!=old_reads)$fatal(1,"missing file changed fallback");
  enable=0;wait(stop);found=1;received=0;check_mode=1;enable=1;
  wait(received>=602);
  $display("PASS audio stream: fragmented 1202-byte loops, concurrent pictures=%0d, short-file prefill, mid-sector stop/restart, error fallback, odd/empty/missing",pictures);$finish;
 end
 initial begin #50000000;$fatal(1,"stream watchdog received=%0d loops=%0d state=%0d",received,loops,source.state);end
endmodule
