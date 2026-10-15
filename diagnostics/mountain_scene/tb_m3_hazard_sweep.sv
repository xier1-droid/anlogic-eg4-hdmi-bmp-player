`timescale 1ns/1ps
// M3: every T 0..255 against every t_now 0..255 for each stage, with random
// rgb, alert_level, frame_cnt, enable and thumbnail; one vector per clock.
// A vector driven before edge k must appear after edge k+1 (two registers).
// Answers come from make_scene_pack.py via make_hazard_vectors.py.
module tb_m3_hazard_sweep;
 parameter VEC_DIR=".";
 reg clk=0,rst=1;always #5 clk=~clk;
 reg [23:0] rgb=0;reg [7:0] T=255,t_now=0;reg [1:0] stage=0,alert=0;reg en=0,thumb=0;reg [5:0] fc=0;
 wire [23:0] out;
 hazard_layer dut(.clk(clk),.rst(rst),.rgb_in(rgb),.t_in(T),.t_now(t_now),.stage(stage),.alert_level(alert),
  .enable(en),.thumbnail(thumb),.frame_cnt(fc),.rgb_out(out));
 reg [23:0] want[0:1],src[0:1];reg live[0:1]='{0,0};
 integer fd,n,count=0,changed=0;reg [23:0] e,v_rgb;
 integer s,a,v_en,v_th,v_fc,v_T,v_t;
 always @(posedge clk) if(!rst)begin
  #1;
  if(live[1])begin
   if(out!==want[1])$fatal(1,"vector %0d got %h expected %h",count,out,want[1]);
   if(want[1]!==src[1])changed++;
   count++;
  end
 end
 initial begin
  fd=$fopen({VEC_DIR,"/sweep.txt"},"r");if(fd==0)$fatal(1,"cannot open sweep.txt");
  repeat(3)@(negedge clk);rst=0;
  forever begin
   @(negedge clk);
   want[1]=want[0];src[1]=src[0];live[1]=live[0];
   n=$fscanf(fd,"%h %h %h %d %d %d %d %h %h\n",v_rgb,v_T,v_t,s,a,v_en,v_th,v_fc,e);
   if(n!=9)begin live[0]=0;if(!live[1])break;end
   else begin rgb=v_rgb;T=v_T;t_now=v_t;stage=s;alert=a;en=v_en;thumb=v_th;fc=v_fc;want[0]=e;src[0]=v_rgb;live[0]=1;end
  end
  if(count!=262144)$fatal(1,"sweep count %0d",count);
  $display("PASS hazard sweep vectors=%0d recoloured=%0d",count,changed);$finish;
 end
endmodule
