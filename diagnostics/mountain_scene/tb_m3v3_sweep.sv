`timescale 1ns/1ps
// M3 v3: every T 0..255 against every t_now 0..239 for each hazard x role,
// plus pass-through blocks (no kind, thumbnail). Rows of 256 pixels with a
// 16-clock gap, so the layer's own x/y are x=i, y=row and frame terms may
// change between rows; each block starts a frame. Answers come from
// tools/hazard_v3.render via make_hazard_vectors3.py; latency is 10 clocks.
module tb_m3v3_sweep;
 parameter VEC_DIR=".";
 localparam L=9;   // index of the vector due now: latency - 1
 reg clk=0,rst=1;always #5 clk=~clk;
 reg [23:0] rgb=0;reg [7:0] T=255,t_now=0;reg [2:0] hz=0,role=0;reg thumb=0;reg [9:0] fc=0;
 reg de=0,fs=0;
 wire [23:0] out;
 hazard_layer dut(.clk(clk),.rst(rst),.rgb_in(rgb),.t_in(T),.de(de),.frame_start(fs),.t_now(t_now),
  .hazard(hz),.role(role),.enable(1'b1),.thumbnail(thumb),.frame_cnt(fc),.rgb_out(out));
 reg [23:0] want[0:L];reg live[0:L];
 integer fd,n,count=0,changed=0,index=0,errors=0;reg [23:0] e,v_rgb,src[0:L];
 integer v_T,v_t,v_fc,v_hz,v_role,v_th;
 always @(posedge clk) if(!rst)begin
  #1;
  if(live[L])begin
   if(out!==want[L])begin
    errors++;
    if(errors<8)$display("MISMATCH vector %0d (block %0d row %0d x %0d) got %h expected %h",
     count,count/61440,(count/256)%240,count%256,out,want[L]);
   end
   if(want[L]!==src[L])changed++;
   count++;
  end
 end
 task shift;begin
  for(integer i=L;i>0;i--)begin want[i]=want[i-1];src[i]=src[i-1];live[i]=live[i-1];end
  live[0]=0;
 end endtask
 initial begin
  for(integer i=0;i<=L;i++)live[i]=0;
  fd=$fopen({VEC_DIR,"/sweep.txt"},"r");if(fd==0)$fatal(1,"cannot open sweep.txt");
  repeat(3)@(negedge clk);rst=0;
  forever begin
   n=$fscanf(fd,"%h %h %h %h %d %d %d %h\n",v_rgb,v_T,v_t,v_fc,v_hz,v_role,v_th,e);
   if(n==8 && index%256==0)begin
    @(negedge clk);shift;de=0;
    repeat(16)begin @(negedge clk);shift;end              // line gap: last line leaves
    if(index%61440==0)begin fs=1;@(negedge clk);shift;fs=0;repeat(3)begin @(negedge clk);shift;end end
    t_now=v_t;fc=v_fc;hz=v_hz;role=v_role;thumb=v_th;
    repeat(2)begin @(negedge clk);shift;end
   end
   @(negedge clk);shift;
   if(n!=8)begin de=0;repeat(L+2)begin @(negedge clk);shift;end break;end
   de=1;rgb=v_rgb;T=v_T;want[0]=e;src[0]=v_rgb;live[0]=1;index++;
  end
  if(errors)$fatal(1,"%0d mismatches in %0d vectors",errors,count);
  if(count!=index || count<900000)$fatal(1,"sweep count %0d of %0d",count,index);
  $display("PASS hazard v3 sweep vectors=%0d recoloured=%0d",count,changed);$finish;
 end
endmodule
