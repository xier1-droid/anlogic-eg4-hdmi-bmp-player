`timescale 1ns/1ps
// M3 display-chain alignment. Reference: the v0.16.0 video_delay (renamed
// video_delay_base, 32-bit data). DUT: video_delay SYNC_EXTRA=2 followed by
// hazard_layer, as wired in top. The DUT must issue the same read_en and
// reproduce the reference x/hs/vs/de exactly two clocks later, with
// rgb_out = hazard(reference pixel) on those same clocks (from reset on).
// de_pix must equal the reference de_r, and the layer's x/y (counted from
// de_pix and a vs-derived frame_start) must match the reference raster.
// The read FIFO is modelled as non-show-ahead: data the clock after read_en.
module tb_m3_chain;
 `include "hazard_model.svh"
 reg clk=0,rst=1;always #5 clk=~clk;
 reg hs=1,vs=1,de=0;reg [9:0] x=0;reg [31:0] read_data=0;reg fs=0;
 reg [7:0] t_now=0;reg [1:0] stage=0,alert=0;reg en=0,thumb=0;reg [5:0] fc=0;
 wire ref_en,ref_hs,ref_vs,ref_de,dut_en,dut_hs,dut_vs,dut_de,dut_de_pix;wire [9:0] ref_x,dut_x;
 wire [31:0] ref_pixel,dut_pixel;wire [23:0] dut_rgb;
 video_delay_base #(.DATA_WIDTH(32)) u_ref(.video_clk(clk),.rst(rst),.read_en(ref_en),.read_data(read_data),
  .hs(hs),.vs(vs),.de(de),.video_x(x),.hs_r(ref_hs),.vs_r(ref_vs),.de_r(ref_de),.vout_data(ref_pixel),.video_x_r(ref_x));
 video_delay #(.DATA_WIDTH(32),.SYNC_EXTRA(2)) u_delay(.video_clk(clk),.rst(rst),.read_en(dut_en),.read_data(read_data),
  .hs(hs),.vs(vs),.de(de),.video_x(x),.hs_r(dut_hs),.vs_r(dut_vs),.de_r(dut_de),.vout_data(dut_pixel),.de_pix(dut_de_pix),.video_x_r(dut_x));
 hazard_layer u_hazard(.clk(clk),.rst(rst),.rgb_in(dut_pixel[31:8]),.t_in(dut_pixel[7:0]),.de(dut_de_pix),.frame_start(fs),.t_now(t_now),
  .stage(stage),.alert_level(alert),.enable(en),.thumbnail(thumb),.frame_cnt(fc),.rgb_out(dut_rgb));
 // Reference sync one and two clocks back. hazard_layer samples a pixel one
 // clock after the delay presents it, with the frame inputs of that clock.
 reg [12:0] sync_d[0:1]='{0,0};reg [31:0] pix_q=0;reg [23:0] want_q=0,src_q=0;
 integer cycles=0,active=0,recoloured=0,mx=0,my=0,px=0,py=0;reg [31:0] word=0;reg de_prev=0,pde=0;
 always @(posedge clk)begin
  if(ref_en!==dut_en)$fatal(1,"read_en differs at cycle %0d",cycles);
  if(dut_en)begin word=word*32'h0019660d+32'h3c6ef35f;read_data<=word;end
 end
 always @(posedge clk) if(!rst)begin
  #1;
  if({dut_x,dut_hs,dut_vs,dut_de}!==sync_d[1])$fatal(1,"sync cycle %0d got %h expected %h",cycles,{dut_x,dut_hs,dut_vs,dut_de},sync_d[1]);
  if(dut_rgb!==want_q)$fatal(1,"pixel cycle %0d got %h expected %h",cycles,dut_rgb,want_q);
  if(dut_de_pix!==ref_de)$fatal(1,"de_pix differs at cycle %0d",cycles);
  if(dut_de)begin active++;if(want_q!==src_q)recoloured++;end
  want_q=hazard_model(pix_q[31:8],pix_q[7:0],t_now,stage,alert,en && pde,thumb,fc,px,py);src_q=pix_q[31:8];
  pix_q=ref_pixel;pde=ref_de;px=mx;py=my;
  // Reference raster position of ref_pixel.
  if(fs)my=0;else if(de_prev && !ref_de)my++;
  mx=ref_de ? mx+1 : 0;de_prev=ref_de;
sync_d[1]=sync_d[0];sync_d[0]={ref_x,ref_hs,ref_vs,ref_de};
  cycles++;
 end
 task frame(input integer lines);
  begin
   @(negedge clk);vs=0;de=0;fs=1;@(negedge clk);fs=0;repeat(11)@(negedge clk);vs=1;
   for(integer y=0;y<lines;y++)
    for(integer px=0;px<800;px++)begin @(negedge clk);de=px<640;x=px;hs=!(px>=656 && px<752);end
   repeat(30)@(negedge clk);
  end
 endtask
 initial begin
  repeat(5)@(negedge clk);rst=0;
  frame(4);                                     // layer disabled: pure delay
  en=1;stage=1;alert=1;t_now=120;fc=6'h3f;frame(4);
  stage=2;alert=2;t_now=239;fc=6'h00;frame(4);
  stage=3;alert=3;t_now=60;fc=6'h24;frame(4);
  stage=0;alert=0;t_now=230;fc=6'h11;frame(40);                 // rain, needs real x/y
  thumb=1;frame(4);
  thumb=0;stage=0;alert=0;t_now=200;fc=6'h20;frame(4);
  rst=1;repeat(3)@(negedge clk);sync_d='{0,0};pix_q=0;pde=0;want_q=0;src_q=0;mx=0;my=0;px=0;py=0;de_prev=0;rst=0;frame(2);   // re-prime after reset
  if(active<6*4*640+40*640+2*640 || recoloured==0)$fatal(1,"missing observations active=%0d recoloured=%0d",active,recoloured);
  $display("PASS M3 chain cycles=%0d active=%0d recoloured=%0d",cycles,active,recoloured);$finish;
 end
endmodule
