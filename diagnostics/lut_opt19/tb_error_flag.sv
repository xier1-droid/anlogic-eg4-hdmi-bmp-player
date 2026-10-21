`timescale 1ns/1ps
// fat32_pcm_stream (LOOP_BITS=1, as in production) against the frozen v0.18.0
// module in lockstep under random inputs: every old output stays identical and
// error_flag equals error_code!=0 on every cycle.
module tb_error_flag;
 reg clk=0, rst=1;
 always #5 clk=~clk;
 integer cycle=0, errors=0, flag_sets=0, crc_errors=0, bad_starts=0, loops=0, resets=0;
 task automatic check(input bit ok, input string what);
  if(!ok) begin errors=errors+1; if(errors<10) $display("MISMATCH %s cycle=%0d",what,cycle); end
 endtask
 reg f_en=0, f_found=0, f_perm=0, f_pstop=0, f_prdy=0, f_busy=0, f_sv=0, f_sdone=0; reg [31:0] f_cluster=0, f_size=0;
 reg [7:0] f_sbyte=0, f_serr=0; reg [8:0] f_sidx=0; integer f_count=0;
 wire r_pen,n_pen,r_fv,n_fv,r_stop,n_stop,r_sreq,n_sreq,r_loop,n_loop,n_flag; wire [7:0] r_byte,n_byte,r_err,n_err; wire [31:0] r_lba,n_lba;
 `define STREAM_PORTS(P) .clk(clk),.rst_n(!rst),.enable(f_en),.audio_found(f_found),.first_cluster(f_cluster),.file_size(f_size), \
  .sectors_per_cluster(8'd8),.fat_start_lba(32'd100),.data_start_lba(32'd1000),.max_cluster(32'd5000),.sector_permit(f_perm), \
  .player_stopped(f_pstop),.player_ready(f_prdy),.player_enable(P``_pen),.file_valid(P``_fv),.file_byte(P``_byte),.stopped(P``_stop), \
  .error_code(P``_err),.loop_count(P``_loop),.sector_req(P``_sreq),.sector_lba(P``_lba),.sector_busy(f_busy),.sector_valid(f_sv), \
  .sector_done(f_sdone),.sector_byte(f_sbyte),.sector_error(f_serr),.sector_index(f_sidx)
 fat32_pcm_stream_v018 #(.LOOP_BITS(1)) ref_stream(`STREAM_PORTS(r));
 fat32_pcm_stream #(.LOOP_BITS(1)) new_stream(`STREAM_PORTS(n),.error_flag(n_flag));
 always @(negedge clk) begin
  check({r_pen,r_fv,r_stop,r_sreq,r_byte,r_err,r_loop,r_lba}==={n_pen,n_fv,n_stop,n_sreq,n_byte,n_err,n_loop,n_lba},"outputs");
  check(n_flag===(n_err!=0),"error_flag");
 end
 reg flag_q=0, loop_q=0;
 always @(posedge clk) begin
  flag_q<=n_flag; loop_q<=n_loop;
  if(n_flag && !flag_q) begin flag_sets=flag_sets+1; if(n_err==8'h30) bad_starts=bad_starts+1; else crc_errors=crc_errors+1; end
  if(n_loop && !loop_q) loops=loops+1;
  #1;
  f_perm=($urandom%8!=0); f_pstop=($urandom%4==0); f_prdy=($urandom%2); f_serr=0;
  // New files often, including bad sizes/clusters that take the 8'h30 path.
  if($urandom%20000==0 || cycle<60) begin
   f_en=1; f_found=($urandom%8!=0); f_cluster=($urandom%10==0) ? $urandom%2 : 2+$urandom%100;
   f_size=($urandom%10==0) ? 2*($urandom%2)+($urandom%2) : ($urandom%3==0) ? 4098+2*($urandom%20000) : 2+2*($urandom%256);
  end
  else if($urandom%15000==0) f_en=0;
  // Sector responder: after a request, 512 bytes then done.
  f_sv=0; f_sdone=0;
  if(f_count==0 && r_sreq) begin f_busy=1; f_count=1; end
  else if(f_count>0 && f_count<=512) begin if($urandom%2) begin f_sv=1; f_sidx=f_count-1; f_sbyte=$urandom; f_count=f_count+1; end end
  else if(f_count>512) begin f_sdone=1; if($urandom%40==0) f_serr=1+$urandom%4; f_busy=0; f_count=0; end
 end
 always @(posedge clk) begin
  cycle<=cycle+1;
  #2;
  if(cycle==10) rst=0;
  else if(cycle>20 && $urandom%1000000==0) begin rst=1; resets=resets+1; end
  else if(rst && cycle>10 && $urandom%5==0) rst=0;
 end
 initial begin
  wait(cycle==3000000);
  $display("coverage flag_sets=%0d bad_starts=%0d stream_errors=%0d loops=%0d resets=%0d",flag_sets,bad_starts,crc_errors,loops,resets);
  if(flag_sets<20 || bad_starts<5 || crc_errors<5 || loops<20 || resets<2) $display("** Error: insufficient coverage");
  else if(errors) $display("** Error: %0d mismatches",errors);
  else $display("PASS error_flag equivalence cycles=%0d",cycle);
  $finish;
 end
endmodule
