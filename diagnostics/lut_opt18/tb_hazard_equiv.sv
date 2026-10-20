`timescale 1ns/1ps
// v0.18 S1 batch 2: hazard_layer (shared noise-corner hashes, one dust/fleck
// hash, fixed noise shifts) against the frozen v0.17.0 module, compared every
// clock. Full 640x480 frames in an 800x525 raster; each frame draws new frame
// terms (hazard 0..7, role 0..7, t_now, frame_cnt, enable, thumbnail), mostly
// active kinds; rgb and T are random per pixel with T=255 and the special
// codes 60..63 weighted. Frame terms change only in vertical blanking. The
// registered noise-corner/fleck hashes and fractions are compared as well.
module tb_hazard_equiv;
 parameter integer FRAMES=40;
 parameter integer SEED=18;
 reg clk=0,rst=1;
 always #20 clk=~clk;
 integer hc=0,vc=0,seed=SEED;
 wire de=hc<640 && vc<480;
 reg frame_start=0;
 reg [23:0] rgb_in=0;reg [7:0] t_in=8'hff;
 reg [7:0] t_now=0;reg [2:0] hazard=0,role=0;reg enable=0,thumbnail=0;reg [9:0] frame_cnt=0;
 wire [23:0] ref_rgb,dut_rgb;
 hazard_layer_v017 ref_(.clk(clk),.rst(rst),.rgb_in(rgb_in),.t_in(t_in),.de(de),.frame_start(frame_start),
  .t_now(t_now),.hazard(hazard),.role(role),.enable(enable),.thumbnail(thumbnail),.frame_cnt(frame_cnt),.rgb_out(ref_rgb));
 hazard_layer dut(.clk(clk),.rst(rst),.rgb_in(rgb_in),.t_in(t_in),.de(de),.frame_start(frame_start),
  .t_now(t_now),.hazard(hazard),.role(role),.enable(enable),.thumbnail(thumbnail),.frame_cnt(frame_cnt),.rgb_out(dut_rgb));
 integer frames=0,checked=0,differ_in=0,active_frames=0;
 task new_frame_terms;
  integer r;
  begin
   r=$urandom(seed)%8;seed=seed+1;
   hazard=r<6 ? 3'd1+$urandom%4 : $urandom%8;
   role=r<6 ? 3'd1+$urandom%4 : $urandom%8;
   enable=($urandom%16)!=0;thumbnail=($urandom%16)==0;
   t_now=$urandom;frame_cnt=$urandom;
   if(enable && !thumbnail && hazard>=1 && hazard<=4 && role>=1 && role<=4)active_frames++;
  end
 endtask
 always @(posedge clk)begin
  if(rst)begin hc<=0;vc<=0;end
  else begin
   if(hc==799)begin hc<=0;vc<=vc==524 ? 0 : vc+1;end else hc<=hc+1;
   frame_start<=(hc==799 && vc==524);
   // Pixel inputs for the next active pixel.
   rgb_in<=$urandom;
   case($urandom%8)
    0,1:t_in<=8'hff;
    2:t_in<={2'($urandom%4),6'(60+$urandom%4)};
    default:t_in<=$urandom;
   endcase
   if(hc==700 && vc==500)new_frame_terms;
   if(hc==799 && vc==524)frames<=frames+1;
  end
 end
 always @(negedge clk)if(!rst)begin
  if(dut_rgb!==ref_rgb)$fatal(1,"frame %0d x=%0d y=%0d hazard=%0d role=%0d t=%0d fc=%0d: %h vs ref %h",
   frames,hc,vc,hazard,role,t_now,frame_cnt,dut_rgb,ref_rgb);
  // The rewritten C1 terms must also agree on every clock (they reach the
  // output only for some kinds and thresholds).
  if({dut.h00,dut.h10,dut.h01,dut.h11,dut.hc1,dut.fx1,dut.fy1}!=={ref_.h00,ref_.h10,ref_.h01,ref_.h11,ref_.hc1,ref_.fx1,ref_.fy1})
   $fatal(1,"C1 terms differ: frame %0d x=%0d y=%0d hazard=%0d role=%0d",frames,hc,vc,hazard,role);
  checked++;if(ref_rgb!==rgb_in)differ_in++;
 end
 initial begin
  new_frame_terms;
  repeat(5)@(posedge clk);rst=0;
  wait(frames==FRAMES);
  if(active_frames<FRAMES/2)$fatal(1,"only %0d active frames",active_frames);
  $display("PASS hazard equiv: %0d frames (%0d active kinds), %0d clocks compared",frames,active_frames,checked);
  $finish;
 end
endmodule
