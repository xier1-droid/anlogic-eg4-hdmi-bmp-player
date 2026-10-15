`timescale 1ns/1ps
// video_delay with the default SYNC_EXTRA=0 against the pre-BRAM reference
// (lut_reduction/video_delay_ref.v): all outputs every cycle under random
// syncs, data and resets. The video half of tb_batch2_equiv, whose tone half
// already mismatches during reset on unmodified v0.16.0 sources.
module tb_m3_video_delay_equiv;
 reg clk=0,rst=1;always #5 clk=~clk;
 integer cycle=0,errors=0,resets=0,nonzero_x=0;
 reg hs=0,vs=0,de=0;reg [9:0] x=0;reg [23:0] data=0;
 wire r_en,r_hs,r_vs,r_de,n_en,n_hs,n_vs,n_de;wire [23:0] r_out,n_out;wire [9:0] r_x,n_x;
 video_delay_ref vref(.video_clk(clk),.rst(rst),.read_en(r_en),.read_data(data),.hs(hs),.vs(vs),.de(de),.video_x(x),
  .hs_r(r_hs),.vs_r(r_vs),.de_r(r_de),.vout_data(r_out),.video_x_r(r_x));
 video_delay vnew(.video_clk(clk),.rst(rst),.read_en(n_en),.read_data(data),.hs(hs),.vs(vs),.de(de),.video_x(x),
  .hs_r(n_hs),.vs_r(n_vs),.de_r(n_de),.vout_data(n_out),.video_x_r(n_x));
 always @(negedge clk)begin
  if({r_en,r_hs,r_vs,r_de,r_out,r_x}!=={n_en,n_hs,n_vs,n_de,n_out,n_x})begin
   errors++;if(errors<10)$display("MISMATCH video_delay cycle=%0d",cycle);
  end
  if(r_x!=0)nonzero_x++;
 end
 always @(posedge clk)begin
  cycle<=cycle+1;
  #1;
  hs=$urandom;vs=($urandom%50==0) ? ~vs : vs;de=$urandom;x=$urandom;data=$urandom;
  if(cycle>100 && $urandom%40000==0)begin rst=1;resets++;end
  else if(cycle==10)rst=0;
  else if(rst && cycle>10 && $urandom%3==0)rst=0;
 end
 initial begin
  wait(cycle==300000);
  if(resets<3 || nonzero_x<1000)$fatal(1,"insufficient coverage resets=%0d x=%0d",resets,nonzero_x);
  if(errors)$fatal(1,"%0d mismatches",errors);
  $display("PASS video_delay equivalence cycles=%0d resets=%0d nonzero_x=%0d",cycle,resets,nonzero_x);$finish;
 end
endmodule
