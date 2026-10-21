`timescale 1ns/1ps
// S1 batch3: v0.15.0 vs new sd_card_cmd, sd_card_sec_read_write, pcm_stream_player and
// fat32_pcm_stream in lockstep under random inputs (small clock parameters reach timeouts).
module tb_batch3_equiv;
 reg clk=0, rclk=0, rst=1;
 always #5 clk=~clk;
 always #20 rclk=~rclk;
 integer cycle=0, errors=0;
 reg was_err=0, was_berr=0, was_fail=0, was_rec=0;
 integer cmd_timeouts=0, token_timeouts=0, init_fails=0, recovers=0, pops=0, replays=0, resets=0;
 task automatic check(input bit ok, input string what);
  if(!ok) begin errors=errors+1; if(errors<10) $display("MISMATCH %s cycle=%0d",what,cycle); end
 endtask

 // ---------------- sd_card_cmd ----------------
 reg c_req=0, c_rd=0, c_wr=0, c_ack=0; reg [47:0] c_cmd=0; reg [7:0] c_r1=0, c_wdata=0, c_dout=0; reg [15:0] c_div=0, c_len=0;
 wire [7:0] ra_resp, na_resp, ra_bdata, na_bdata, ra_sin, na_sin; wire [47:0] ra_dbg, na_dbg; wire [15:0] ra_div, na_div;
 wire ra_ack,na_ack,ra_berr,na_berr,ra_err,na_err,ra_bv,na_bv,ra_brack,na_brack,ra_wrd,na_wrd,ra_bwack,na_bwack,ra_cs,na_cs,ra_sreq,na_sreq;
 `define CMD_PORTS(P) .sys_clk(clk),.rst(rst),.spi_clk_div(c_div),.cmd_req(c_req),.cmd_req_ack(P``_ack),.block_read_error(P``_berr), \
  .cmd_response(P``_resp),.read_debug(P``_dbg),.cmd_req_error(P``_err),.cmd(c_cmd),.cmd_r1(c_r1),.cmd_data_len(c_len), \
  .block_read_req(c_rd),.block_read_valid(P``_bv),.block_read_data(P``_bdata),.block_read_req_ack(P``_brack), \
  .block_write_req(c_wr),.block_write_data(c_wdata),.block_write_data_rd(P``_wrd),.block_write_req_ack(P``_bwack), \
  .nCS_ctrl(P``_cs),.clk_div(P``_div),.spi_wr_req(P``_sreq),.spi_wr_ack(c_ack),.spi_data_in(P``_sin),.spi_data_out(c_dout)
 sd_card_cmd_v015 #(.CLK_FREQ_HZ(20000)) cmd_ref(`CMD_PORTS(ra));
 sd_card_cmd #(.CLK_FREQ_HZ(20000)) cmd_new(`CMD_PORTS(na));
 always @(negedge clk) check({ra_resp,ra_bdata,ra_sin,ra_dbg,ra_div,ra_ack,ra_berr,ra_err,ra_bv,ra_brack,ra_wrd,ra_bwack,ra_cs,ra_sreq}===
                             {na_resp,na_bdata,na_sin,na_dbg,na_div,na_ack,na_berr,na_err,na_bv,na_brack,na_wrd,na_bwack,na_cs,na_sreq},"sd_card_cmd");
 always @(posedge clk) begin
  if(!rst && cmd_ref.state==cmd_ref.S_ERR && !was_err) cmd_timeouts=cmd_timeouts+1;
  if(!rst && ra_berr && !was_berr) token_timeouts=token_timeouts+1;
  was_err=cmd_ref.state==cmd_ref.S_ERR; was_berr=ra_berr;
  #1;
  // Mostly idle SPI (0xFF) so responses rarely arrive and the timeouts fire.
  c_ack=($urandom%3==0); c_dout=($urandom%400==0) ? $urandom : 8'hff;
  if($urandom%5000==0) c_req=~c_req; if($urandom%5000==0) c_rd=~c_rd; if($urandom%20000==0) c_wr=~c_wr;
  c_cmd={$urandom,$urandom}; c_r1=$urandom; c_wdata=$urandom; c_div=$urandom%4; c_len=($urandom%2) ? 0 : $urandom%8;
 end

 // ---------------- sd_card_sec_read_write ----------------
 reg s_rd=0, s_wr=0, s_cack=0, s_cerr=0, s_bv=0, s_brack=0, s_berr=0, s_wrd=0, s_bwack=0; reg [31:0] s_raddr=0, s_waddr=0; reg [7:0] s_wdata=0, s_bdata=0;
 wire [7:0] rs_rdata, ns_rdata, rs_r1, ns_r1, rs_bwd, ns_bwd; wire [15:0] rs_div, ns_div, rs_len, ns_len; wire [47:0] rs_cmd, ns_cmd;
 wire rs_done,ns_done,rs_fail,ns_fail,rs_rec,ns_rec,rs_rfail,ns_rfail,rs_rv,ns_rv,rs_rend,ns_rend,rs_wreq,ns_wreq,rs_wend,ns_wend,rs_creq,ns_creq,rs_brreq,ns_brreq,rs_bwreq,ns_bwreq;
 `define SEC_PORTS(P) .clk(clk),.rst(rst),.sd_init_done(P``_done),.sd_init_failed(P``_fail),.sd_init_recovery(P``_rec),.sd_sec_read_failed(P``_rfail), \
  .sd_sec_read(s_rd),.sd_sec_read_addr(s_raddr),.sd_sec_read_data(P``_rdata),.sd_sec_read_data_valid(P``_rv),.sd_sec_read_end(P``_rend), \
  .sd_sec_write(s_wr),.sd_sec_write_addr(s_waddr),.sd_sec_write_data(s_wdata),.sd_sec_write_data_req(P``_wreq),.sd_sec_write_end(P``_wend), \
  .spi_clk_div(P``_div),.cmd_req(P``_creq),.cmd_req_ack(s_cack),.cmd_req_error(s_cerr),.cmd(P``_cmd),.cmd_r1(P``_r1),.cmd_data_len(P``_len), \
  .block_read_req(P``_brreq),.block_read_valid(s_bv),.block_read_data(s_bdata),.block_read_req_ack(s_brack),.block_read_error(s_berr), \
  .block_write_req(P``_bwreq),.block_write_data(P``_bwd),.block_write_data_rd(s_wrd),.block_write_req_ack(s_bwack)
 sd_card_sec_read_write_v015 #(.CLK_FREQ_HZ(10000),.INIT_TIMEOUT_MS(200)) sec_ref(`SEC_PORTS(rs));
 sd_card_sec_read_write #(.CLK_FREQ_HZ(10000),.INIT_TIMEOUT_MS(200)) sec_new(`SEC_PORTS(ns));
 always @(negedge clk) check({rs_rdata,rs_r1,rs_bwd,rs_div,rs_len,rs_cmd,rs_done,rs_fail,rs_rec,rs_rfail,rs_rv,rs_rend,rs_wreq,rs_wend,rs_creq,rs_brreq,rs_bwreq}===
                             {ns_rdata,ns_r1,ns_bwd,ns_div,ns_len,ns_cmd,ns_done,ns_fail,ns_rec,ns_rfail,ns_rv,ns_rend,ns_wreq,ns_wend,ns_creq,ns_brreq,ns_bwreq},"sd_card_sec_read_write");
 always @(posedge clk) begin
  if(!rst && rs_fail && !was_fail) init_fails=init_fails+1;
  if(!rst && sec_ref.state==sec_ref.S_RECOVER && !was_rec) recovers=recovers+1;
  was_fail=rs_fail; was_rec=sec_ref.state==sec_ref.S_RECOVER;
  #1;
  // Alternate phases: no command acknowledgement (init timeouts, recovery) and random acks.
  s_cack=((cycle/300000)%2==1) && rs_creq && ($urandom%4==0); s_cerr=($urandom%30==0);
  s_brack=rs_brreq && ($urandom%4==0); s_bv=($urandom%3==0); s_bdata=($urandom%2) ? 8'h00 : $urandom; s_berr=($urandom%5000==0);
  s_wrd=($urandom%3==0); s_bwack=rs_bwreq && ($urandom%4==0);
  if($urandom%3000==0) s_rd=~s_rd; if($urandom%30000==0) s_wr=~s_wr; s_raddr=$urandom; s_waddr=$urandom; s_wdata=$urandom;
 end

 // ---------------- pcm_stream_player ----------------
 reg p_en=0, p_fv=0, p_rdy=0; reg [7:0] p_byte=0;
 wire rp_fr,np_fr,rp_perm,np_perm,rp_low,np_low,rp_stop,np_stop,rp_sv,np_sv,rp_act,np_act,rp_ovr,np_ovr;
 wire [8:0] rp_lvl,np_lvl; wire [15:0] rp_l,np_l,rp_r,np_r; wire [31:0] rp_under,np_under;
 `define PLAYER_PORTS(P) .wr_clk(clk),.wr_rst_n(!rst),.play_enable(p_en),.file_valid(p_fv),.file_byte(p_byte),.file_ready(P``_fr), \
  .sector_permit(P``_perm),.buffer_low(P``_low),.stopped(P``_stop),.write_level(P``_lvl),.rd_clk(rclk),.rd_rst_n(!rst),.sample_ready(p_rdy), \
  .sample_valid(P``_sv),.sample_left(P``_l),.sample_right(P``_r),.active(P``_act),.underflow_count(P``_under),.output_overrun(P``_ovr)
 wire rq_fr,nq_fr,rq_perm,nq_perm,rq_low,nq_low,rq_stop,nq_stop,rq_sv,nq_sv,rq_act,nq_act,rq_ovr,nq_ovr;
 wire [8:0] rq_lvl,nq_lvl; wire [15:0] rq_l,nq_l,rq_r,nq_r; wire [31:0] rq_under,nq_under;
 pcm_stream_player_v015 #(.ADDR_WIDTH(8),.CLOCK_HZ(25000000),.PREFILL(128),.LOW_WATER(64),.HIGH_WATER(192)) ply_ref(`PLAYER_PORTS(rp));
 pcm_stream_player #(.ADDR_WIDTH(8),.CLOCK_HZ(25000000),.PREFILL(128),.LOW_WATER(64),.HIGH_WATER(192)) ply_new(`PLAYER_PORTS(np));
 pcm_stream_player_v015 #(.ADDR_WIDTH(8),.CLOCK_HZ(1234567),.SAMPLE_HZ(48000),.PREFILL(128),.LOW_WATER(64),.HIGH_WATER(192)) ply_ref2(`PLAYER_PORTS(rq));
 pcm_stream_player #(.ADDR_WIDTH(8),.CLOCK_HZ(1234567),.SAMPLE_HZ(48000),.PREFILL(128),.LOW_WATER(64),.HIGH_WATER(192)) ply_new2(`PLAYER_PORTS(nq));
 always @(negedge clk) check({rp_fr,rp_perm,rp_low,rp_stop,rp_lvl,rq_fr,rq_perm,rq_low,rq_stop,rq_lvl}==={np_fr,np_perm,np_low,np_stop,np_lvl,nq_fr,nq_perm,nq_low,nq_stop,nq_lvl},"player wr");
 always @(negedge rclk) begin
  check({rp_sv,rp_act,rp_under,rp_ovr,rq_sv,rq_act,rq_under,rq_ovr}==={np_sv,np_act,np_under,np_ovr,nq_sv,nq_act,nq_under,nq_ovr},"player rd");
  if(rp_sv) check({rp_l,rp_r}==={np_l,np_r},"player sample"); if(rq_sv) check({rq_l,rq_r}==={nq_l,nq_r},"player2 sample");
 end
 always @(posedge clk) begin #1; p_fv=($urandom%3!=0); p_byte=$urandom; if($urandom%150000==0) p_en=~p_en; if(cycle<50) p_en=1; end
 always @(posedge rclk) begin if(rp_sv && p_rdy) pops=pops+1; #1; p_rdy=($urandom%4!=0); end

 // ---------------- fat32_pcm_stream (short files reach replay) ----------------
 reg f_en=0, f_found=0, f_perm=0, f_pstop=0, f_prdy=0, f_busy=0, f_sv=0, f_sdone=0; reg [31:0] f_cluster=0, f_size=0;
 reg [7:0] f_sbyte=0, f_serr=0; reg [8:0] f_sidx=0; integer f_count=0;
 wire rf_pen,nf_pen,rf_fv,nf_fv,rf_stop,nf_stop,rf_sreq,nf_sreq; wire [7:0] rf_byte,nf_byte,rf_err,nf_err; wire [31:0] rf_loop,nf_loop,rf_lba,nf_lba;
 `define STREAM_PORTS(P) .clk(clk),.rst_n(!rst),.enable(f_en),.audio_found(f_found),.first_cluster(f_cluster),.file_size(f_size), \
  .sectors_per_cluster(8'd8),.fat_start_lba(32'd100),.data_start_lba(32'd1000),.max_cluster(32'd5000),.sector_permit(f_perm), \
  .player_stopped(f_pstop),.player_ready(f_prdy),.player_enable(P``_pen),.file_valid(P``_fv),.file_byte(P``_byte),.stopped(P``_stop), \
  .error_code(P``_err),.loop_count(P``_loop),.sector_req(P``_sreq),.sector_lba(P``_lba),.sector_busy(f_busy),.sector_valid(f_sv), \
  .sector_done(f_sdone),.sector_byte(f_sbyte),.sector_error(f_serr),.sector_index(f_sidx)
 fat32_pcm_stream_v015 str_ref(`STREAM_PORTS(rf));
 fat32_pcm_stream str_new(`STREAM_PORTS(nf),.error_flag());
 always @(negedge clk) check({rf_pen,rf_fv,rf_stop,rf_sreq,rf_byte,rf_err,rf_loop,rf_lba}==={nf_pen,nf_fv,nf_stop,nf_sreq,nf_byte,nf_err,nf_loop,nf_lba},"fat32_pcm_stream");
 always @(posedge clk) begin
  if(!rst && str_ref.state==str_ref.REPLAY_OUT && f_prdy) replays=replays+1;
  #1;
  f_perm=($urandom%8!=0); f_pstop=($urandom%4==0); f_prdy=($urandom%2); f_serr=($urandom%300==0) ? $urandom%4 : 0;
  if($urandom%200000==0 || cycle<60) begin f_en=1; f_found=1; f_cluster=2+$urandom%100; f_size=($urandom%4==0) ? 513+$urandom%3000 : 1+$urandom%512; end
  else if($urandom%400000==0) f_en=0;
  // Sector responder: after a request, 512 bytes then done.
  f_sv=0; f_sdone=0;
  if(f_count==0 && rf_sreq) begin f_busy=1; f_count=1; end
  else if(f_count>0 && f_count<=512) begin if($urandom%2) begin f_sv=1; f_sidx=f_count-1; f_sbyte=$urandom; f_count=f_count+1; end end
  else if(f_count>512) begin f_sdone=1; f_busy=0; f_count=0; end
 end

 always @(posedge clk) begin
  cycle<=cycle+1;
  #2;
  if(cycle==10) rst=0;
  else if(cycle>20 && $urandom%700000==0) begin rst=1; resets=resets+1; end
  else if(rst && cycle>10 && $urandom%5==0) rst=0;
 end
 initial begin
  wait(cycle==4000000);
  $display("coverage cmd_timeouts=%0d token_timeouts=%0d init_fails=%0d recovers=%0d pops=%0d replays=%0d resets=%0d",
   cmd_timeouts,token_timeouts,init_fails,recovers,pops,replays,resets);
  if(cmd_timeouts<5 || token_timeouts<1 || init_fails<1 || recovers<3 || pops<300 || replays<1000 || resets<2)
   $display("** Error: insufficient coverage");
  else if(errors) $display("** Error: %0d mismatches",errors);
  else $display("PASS batch3 equivalence cycles=%0d",cycle);
  $finish;
 end
endmodule
