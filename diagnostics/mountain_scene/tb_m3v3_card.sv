`timescale 1ns/1ps
// M3 v3: stream each format 3 card image {RGB,T} through hazard_layer in
// display order and compare every output pixel with hazard_v3.render
// (cards.txt). Hazard and role come from the BMP header bytes 6-7, as the
// SD path delivers them. Lines carry de with a 16-clock gap and every frame
// starts with frame_start, so the layer's own x/y match the image.
module tb_m3v3_card;
 parameter VEC_DIR=".";
 parameter integer FRAMES=0;          // expected case count (0: any)
 localparam W=640,H=480,N=W*H,L=9;    // L: latency - 1
 reg clk=0,rst=1;always #5 clk=~clk;
 reg [23:0] rgb=0;reg [7:0] T=255,t_now=0;reg [2:0] hz=0,role=0;reg [9:0] fc=0;reg de=0,fs=0;
 wire [23:0] out;
 hazard_layer dut(.clk(clk),.rst(rst),.rgb_in(rgb),.t_in(T),.de(de),.frame_start(fs),.t_now(t_now),
  .hazard(hz),.role(role),.enable(1'b1),.thumbnail(1'b0),.frame_cnt(fc),.rgb_out(out));
 reg [7:0] bmp[0:4*N+53];reg [7:0] exp[0:3*N-1];
 integer fd,n,t,f,offset,count,frames=0,changes;
 string path,name,loaded;
 integer idx[0:L];reg live[0:L];
 always @(posedge clk) if(!rst)begin
  #1;
  if(live[L])begin
   if(out!=={exp[idx[L]*3],exp[idx[L]*3+1],exp[idx[L]*3+2]})
    $fatal(1,"%0s pixel x=%0d y=%0d got %h expected %h",name,idx[L]%W,idx[L]/W,out,{exp[idx[L]*3],exp[idx[L]*3+1],exp[idx[L]*3+2]});
   count++;
  end
 end
 task shift;begin
  for(integer i=L;i>0;i--)begin idx[i]=idx[i-1];live[i]=live[i-1];end
  live[0]=0;
 end endtask
 integer cfd,base;
 initial begin
  for(integer i=0;i<=L;i++)live[i]=0;
  loaded="";
  cfd=$fopen({VEC_DIR,"/cards.txt"},"r");if(cfd==0)$fatal(1,"cannot open cards.txt");
  repeat(3)@(negedge clk);rst=0;
  while($fscanf(cfd,"%s %d %d %s\n",path,t,f,name)==4)begin
   if(path!=loaded)begin
    fd=$fopen(path,"rb");if(fd==0)$fatal(1,"cannot open %0s",path);
    n=$fread(bmp,fd);$fclose(fd);if(n!=4*N+54)$fatal(1,"%0s size %0d",path,n);
    offset={bmp[13],bmp[12],bmp[11],bmp[10]};loaded=path;
   end
   fd=$fopen({VEC_DIR,"/",name},"rb");if(fd==0)$fatal(1,"cannot open %0s",name);
   n=$fread(exp,fd);$fclose(fd);if(n!=3*N)$fatal(1,"%0s size %0d",name,n);
   repeat(4)@(negedge clk);
   hz=bmp[6][2:0];role=bmp[7][2:0];t_now=t;fc=f;count=0;changes=0;
   fs=1;@(negedge clk);fs=0;repeat(3)@(negedge clk);
   for(integer i=0;i<N;i++)begin
    if(i%W==0 && i)repeat(16)begin @(negedge clk);shift;de=0;end
    @(negedge clk);shift;
    base=offset+((H-1-i/W)*W+i%W)*4;   // bottom-up BMP rows
    de=1;rgb={bmp[base+2],bmp[base+1],bmp[base]};T=bmp[base+3];idx[0]=i;live[0]=1;
    if({exp[i*3],exp[i*3+1],exp[i*3+2]}!==rgb)changes++;
   end
   @(negedge clk);shift;de=0;
   repeat(L+2)begin @(negedge clk);shift;end
   if(count!=N)$fatal(1,"%0s count %0d",name,count);
   frames++;
   $display("PASS %0s hazard=%0d role=%0d recoloured=%0d",name,hz,role,changes);
  end
  if(FRAMES && frames!=FRAMES)$fatal(1,"card frames %0d of %0d",frames,FRAMES);
  $display("PASS hazard v3 cards frames=%0d pixels=%0d",frames,frames*N);$finish;
 end
endmodule
