`timescale 1ns/1ps
// M3 v3 display-chain alignment. Reference: the v0.16.0 video_delay (renamed
// video_delay_base, 32-bit data). DUT: video_delay SYNC_EXTRA=10 followed by
// hazard_layer, wired as in top (layer de = read_en delayed two clocks).
// The DUT must issue the same read_en and reproduce the reference x/hs/vs/de
// exactly ten clocks later; rgb_out must be the reference pixel on those
// clocks (pass-through, thumbnail), or for the earthquake close-up the
// reference line shifted by s = +-amp with the line ends repeated. T=FF, so
// only the shake acts. Checked every clock from reset on, twice.
// The read FIFO is modelled as non-show-ahead: data the clock after read_en.
module tb_m3_chain;
 localparam L=10;
 reg clk=0,rst=1;always #5 clk=~clk;
 reg hs=1,vs=1,de=0;reg [9:0] x=0;reg [31:0] read_data=0;reg fs=0;
 reg [7:0] t_now=0;reg [2:0] hz=0,role=0;reg thumb=0;reg [9:0] fc=0;
 wire ref_en,ref_hs,ref_vs,ref_de,dut_en,dut_hs,dut_vs,dut_de;wire [9:0] ref_x,dut_x;
 wire [31:0] ref_pixel,dut_pixel;wire [23:0] dut_rgb;
 reg [1:0] de_pix_d=0;wire dut_de_pix=de_pix_d[1];
 video_delay_base #(.DATA_WIDTH(32)) u_ref(.video_clk(clk),.rst(rst),.read_en(ref_en),.read_data(read_data),
  .hs(hs),.vs(vs),.de(de),.video_x(x),.hs_r(ref_hs),.vs_r(ref_vs),.de_r(ref_de),.vout_data(ref_pixel),.video_x_r(ref_x));
 video_delay #(.DATA_WIDTH(32),.SYNC_EXTRA(L)) u_delay(.video_clk(clk),.rst(rst),.read_en(dut_en),.read_data(read_data),
  .hs(hs),.vs(vs),.de(de),.video_x(x),.hs_r(dut_hs),.vs_r(dut_vs),.de_r(dut_de),.vout_data(dut_pixel),.video_x_r(dut_x));
 always @(posedge clk or posedge rst)if(rst)de_pix_d<=0;else de_pix_d<={de_pix_d[0],dut_en};
 hazard_layer u_hazard(.clk(clk),.rst(rst),.rgb_in(dut_pixel[31:8]),.t_in(dut_pixel[7:0]),.de(dut_de_pix),.frame_start(fs),
  .t_now(t_now),.hazard(hz),.role(role),.enable(1'b1),.thumbnail(thumb),.frame_cnt(fc),.rgb_out(dut_rgb));
 // Reference outputs L clocks back, and the reference line being shown.
 reg [12:0] sync_d[0:L-1];reg [23:0] pix_d[0:L-1];reg de_d[0:L-1];integer x_d[0:L-1];
 reg [23:0] line[0:639];integer mx=0,last=0;reg de_prev=0;
 integer cycles=0,active=0,shifted=0,s,src;reg [23:0] want;reg [31:0] word=0;
 always @(posedge clk)begin
  if(ref_en!==dut_en)$fatal(1,"read_en differs at cycle %0d",cycles);
  if(dut_en)begin word=word*32'h0019660d+32'h3c6ef35f;read_data<={word[31:8],8'hff};end
 end
 function integer shake;
  input integer dummy;
  integer amp;
  begin
   amp=(t_now<40 || ((t_now-40)>>5)>=4) ? 0 : 4-((t_now-40)>>5);
   shake=(thumb || hz!=4 || role!=2) ? 0 : fc[1:0]==1 ? amp : fc[1:0]==3 ? -amp : 0;
  end
 endfunction
 always @(posedge clk) if(!rst)begin
  #1;
  if({dut_x,dut_hs,dut_vs,dut_de}!==sync_d[L-1])$fatal(1,"sync cycle %0d got %h expected %h",cycles,{dut_x,dut_hs,dut_vs,dut_de},sync_d[L-1]);
  if(dut_de_pix!==ref_de)$fatal(1,"layer de differs at cycle %0d",cycles);
  if(dut_de!==de_d[L-1])$fatal(1,"de not aligned at cycle %0d",cycles);
  if(dut_de)begin
   s=shake(0);src=x_d[L-1]-s;
   if(src<0)src=0;else if(src>last)src=last;
   want=line[src];
   if(dut_rgb!==want)$fatal(1,"pixel cycle %0d x=%0d s=%0d got %h expected %h",cycles,x_d[L-1],s,dut_rgb,want);
   if(s!=0)shifted++;
   active++;
  end else if(dut_rgb!==pix_d[L-1])$fatal(1,"blank cycle %0d got %h expected %h",cycles,dut_rgb,pix_d[L-1]);
  for(integer i=L-1;i>0;i--)begin sync_d[i]=sync_d[i-1];pix_d[i]=pix_d[i-1];de_d[i]=de_d[i-1];x_d[i]=x_d[i-1];end
  sync_d[0]={ref_x,ref_hs,ref_vs,ref_de};pix_d[0]=ref_pixel[31:8];de_d[0]=ref_de;
  // Reference raster: pixel mx of the current line.
  if(ref_de)begin line[mx]=ref_pixel[31:8];last=mx;x_d[0]=mx;mx=mx+1;end else begin x_d[0]=0;mx=0;end
  de_prev=ref_de;
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
 task prime;begin
  for(integer i=0;i<L;i++)begin sync_d[i]=0;pix_d[i]=0;de_d[i]=0;x_d[i]=0;end
  mx=0;last=0;
 end endtask
 initial begin
  prime;
  repeat(5)@(negedge clk);rst=0;
  frame(4);                                                         // no kind: pure delay
  hz=4;role=2;t_now=50;fc=10'd1;frame(4);                           // shake +4
  fc=10'd3;frame(4);                                                // shake -4
  t_now=110;fc=10'd5;frame(4);                                      // +2
  t_now=150;fc=10'd7;frame(4);                                      // -1
  t_now=200;fc=10'd1;frame(4);                                      // amplitude 0
  t_now=50;thumb=1;frame(4);                                        // thumbnail: bypass
  thumb=0;hz=1;role=4;frame(4);                                     // active kind, no rain, T=FF: unchanged
  rst=1;repeat(3)@(negedge clk);prime;hz=0;role=0;rst=0;frame(2);   // re-prime after reset
  if(active!=8*4*640+2*640 || shifted!=4*4*640)$fatal(1,"missing observations active=%0d shifted=%0d",active,shifted);
  $display("PASS M3 chain cycles=%0d active=%0d shifted=%0d",cycles,active,shifted);$finish;
 end
endmodule
