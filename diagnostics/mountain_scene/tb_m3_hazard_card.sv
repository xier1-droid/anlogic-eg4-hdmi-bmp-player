`timescale 1ns/1ps
// M3: stream the demo village PIC1-4 {RGB,T} through hazard_layer one pixel
// per clock in display order (top row first) and compare every output with the
// make_scene_pack expected frame: t=0/120/239 x blink on/off, mixed blink
// phases, enable=0 and thumbnail bypass (cases.txt).
module tb_m3_hazard_card;
 parameter FILE_DIR=".";
 parameter VEC_DIR=".";
 localparam W=640,H=480,N=W*H;
 reg clk=0,rst=1;always #5 clk=~clk;
 reg [23:0] rgb=0;reg [7:0] T=255,t_now=0;reg [1:0] stage=0;reg en=0,thumb=0;reg [5:0] fc=0;
 wire [23:0] out;
 hazard_layer dut(.clk(clk),.rst(rst),.rgb_in(rgb),.t_in(T),.t_now(t_now),.stage(stage),.alert_level(stage),
  .enable(en),.thumbnail(thumb),.frame_cnt(fc),.rgb_out(out));
 reg [7:0] bmp[0:4*N+53];reg [7:0] exp[0:3*N-1];
 integer fd,n,loaded=0,pic,t,f,e_en,e_th,offset,count,changed,frames=0;
 string name;
 integer idx[0:1];reg live[0:1]='{0,0};
 always @(posedge clk) if(!rst)begin
  #1;
  if(live[1])begin
   if(out!=={exp[idx[1]*3],exp[idx[1]*3+1],exp[idx[1]*3+2]})
    $fatal(1,"%0s pixel x=%0d y=%0d got %h expected %h",name,idx[1]%W,idx[1]/W,out,{exp[idx[1]*3],exp[idx[1]*3+1],exp[idx[1]*3+2]});
   count++;
  end
 end
 task load_pic(input integer p);
  begin
   fd=$fopen($sformatf("%s/PIC%0d.BMP",FILE_DIR,p),"rb");if(fd==0)$fatal(1,"cannot open PIC%0d.BMP",p);
   n=$fread(bmp,fd);$fclose(fd);if(n!=4*N+54)$fatal(1,"PIC%0d size %0d",p,n);
   offset={bmp[13],bmp[12],bmp[11],bmp[10]};loaded=p;
  end
 endtask
 integer cfd,base,changes;
 initial begin
  cfd=$fopen({VEC_DIR,"/cases.txt"},"r");if(cfd==0)$fatal(1,"cannot open cases.txt");
  repeat(3)@(negedge clk);rst=0;
  while($fscanf(cfd,"%d %d %d %d %d %s\n",pic,t,f,e_en,e_th,name)==6)begin
   if(loaded!=pic)load_pic(pic);
   fd=$fopen({VEC_DIR,"/",name},"rb");if(fd==0)$fatal(1,"cannot open %0s",name);
   n=$fread(exp,fd);$fclose(fd);if(n!=3*N)$fatal(1,"%0s size %0d",name,n);
   // Frame parameters change in blanking, as hazard_test_source does.
   repeat(4)@(negedge clk);
   stage=pic-1;t_now=t;fc=f;en=e_en;thumb=e_th;count=0;changes=0;
   for(integer i=0;i<N;i++)begin
    @(negedge clk);
    idx[1]=idx[0];live[1]=live[0];
    base=offset+((H-1-i/W)*W+i%W)*4;   // bottom-up BMP rows
    rgb={bmp[base+2],bmp[base+1],bmp[base]};T=bmp[base+3];idx[0]=i;live[0]=1;
    if({exp[i*3],exp[i*3+1],exp[i*3+2]}!==rgb)changes++;
   end
   @(negedge clk);idx[1]=idx[0];live[1]=live[0];live[0]=0;
   @(negedge clk);live[1]=0;
   if(count!=N)$fatal(1,"%0s count %0d",name,count);
   frames++;
   $display("PASS %0s stage=%0d t=%0d frame_cnt=%02h en=%0d thumb=%0d recoloured=%0d",name,pic-1,t,f,e_en,e_th,changes);
  end
  if(frames!=44)$fatal(1,"card frames %0d",frames);
  $display("PASS hazard card frames=%0d pixels=%0d",frames,frames*N);$finish;
 end
endmodule
