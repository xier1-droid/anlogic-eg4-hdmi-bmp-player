`timescale 1ns/1ps
// v0.18 S2 batch 8: audio ring in production mode (audio_ring_levels
// SYNC_READ=1, audio_ring_overlay LEVEL_LATENCY=1, BRAM32k ROM) against the
// frozen v0.17.0 pair, clock by clock. 800x525 raster with x/y counting as
// adjust_x/adjust_y do; frame_start one clock after VS falls, as
// osd_pixel_position; random RGB; per frame a new PCM rate (none, sparse,
// production-like, dense), amplitude envelope and enable. The first frames
// cover a partly filled history (unwritten heights read as zero).
module tb_ring_lockstep;
 parameter integer FRAMES=36;
 parameter integer SEED=18;
 reg clk=0,rst=1;
 always #20 clk=~clk;
 integer hc=0,vc=0;
 wire de=hc<640 && vc<480;
 wire hs=!(hc>=656 && hc<752);
 wire vs=!(vc>=490 && vc<492);
 wire [9:0] x=hc[9:0];
 wire [8:0] y=vc<480 ? vc[8:0] : 9'd479;
 reg [23:0] rgb=0;
 reg en=1,vs_q=1,frame_start=0;
 reg pcm_valid=0;reg signed [15:0] pl=0,pr=0;
 integer rate=0,amp=0;
 wire [6:0] r_index,n_index;wire [4:0] r_height,n_height;
 wire r_hs,r_vs,r_de,n_hs,n_vs,n_de;wire [9:0] r_x,n_x;wire [23:0] r_rgb,n_rgb;
 audio_ring_levels_v017 r_levels(.clk(clk),.rst(rst),.frame_start(frame_start),.pcm_valid(pcm_valid),
  .pcm_left(pl),.pcm_right(pr),.bar_index(r_index),.bar_height(r_height));
 audio_ring_overlay_v017 r_ring(.clk(clk),.rst(rst),.hs(hs),.vs(vs),.de(de),.enable(en),.pixel_x(x),.pixel_y(y),
  .rgb_in(rgb),.bar_height(r_height),.bar_index(r_index),.hs_out(r_hs),.vs_out(r_vs),.de_out(r_de),.x_out(r_x),.rgb_out(r_rgb));
 audio_ring_levels #(.SYNC_READ(1)) n_levels(.clk(clk),.rst(rst),.frame_start(frame_start),.pcm_valid(pcm_valid),
  .pcm_left(pl),.pcm_right(pr),.bar_index(n_index),.bar_height(n_height));
 audio_ring_overlay #(.LEVEL_LATENCY(1)) n_ring(.clk(clk),.rst(rst),.hs(hs),.vs(vs),.de(de),.enable(en),.pixel_x(x),.pixel_y(y),
  .rgb_in(rgb),.bar_height(n_height),.bar_index(n_index),.hs_out(n_hs),.vs_out(n_vs),.de_out(n_de),.x_out(n_x),.rgb_out(n_rgb));
 integer frames=0,checked=0,bar_px=0,ring_px=0;
 reg [23:0] rgb_d1=0,rgb_d2=0;
 always @(posedge clk)begin
  if(rst)begin hc<=0;vc<=0;end
  else begin
   if(hc==799)begin hc<=0;vc<=vc==524 ? 0 : vc+1;end else hc<=hc+1;
   rgb<=$urandom;
   vs_q<=vs;frame_start<=vs_q && !vs;
   // PCM beside video, as the HDMI audio tap.
   pcm_valid<=rate!=0 && ($urandom%rate)==0;
   pl<=$signed($urandom%(2*amp+1))-amp;pr<=$signed($urandom%(2*amp+1))-amp;
   if(hc==700 && vc==500)begin
    frames<=frames+1;
    case($urandom%5)0:rate=0;1:rate=4000;2:rate=520;default:rate=8+$urandom%40;endcase
    amp=$urandom%5==0 ? 32767 : $urandom%(1<<($urandom%16));
    en<=($urandom%8)!=0;
   end
  end
  rgb_d1<=rgb;rgb_d2<=rgb_d1;
 end
 always @(negedge clk)if(!rst)begin
  if({n_hs,n_vs,n_de,n_x,n_rgb}!=={r_hs,r_vs,r_de,r_x,r_rgb})
   $fatal(1,"ring differs: frame %0d hc=%0d vc=%0d rgb %h vs ref %h",frames,hc,vc,n_rgb,r_rgb);
  checked++;
  if(r_de && r_rgb!==rgb_d2)begin ring_px++;if(r_rgb!==24'h0)bar_px++;end
 end
 initial begin
  void'($urandom(SEED));
  repeat(5)@(posedge clk);rst=0;
  wait(frames==FRAMES);
  if(bar_px==0 || ring_px==bar_px)$fatal(1,"coverage: %0d ring pixels, %0d bar pixels",ring_px,bar_px);
  $display("PASS ring lockstep: %0d frames, %0d clocks, %0d ring pixels (%0d coloured bar pixels)",frames,checked,ring_px,bar_px);
  $finish;
 end
endmodule
