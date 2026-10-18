`timescale 1ns/1ps
module tb_audio_scan #(parameter integer GAP=0);
 reg clk=0;always #5 clk=~clk;reg rst=1,start=0;
 wire busy,done,req,found;wire [7:0] err;wire [31:0] lba,cluster,size;wire [3:0] pics;
 reg sbusy=0,valid=0,sdone=0;reg [7:0] byte_data=0;reg [8:0] idx=0;
 reg [7:0] disk[0:2047];integer base=0,pos=0,reads=0,scenario=0,gap_count=0;
 fat32_volume_scanner #(.SCAN_AUDIO(1)) dut(
 .clk(clk),.rst_n(!rst),.scan_start(start),.scan_busy(busy),.scan_done(done),.fs_error(err),
 .partition_lba(),.sectors_per_cluster(),.fat_start_lba(),.data_start_lba(),.max_cluster(),
 .resource_valid(pics),.resource0_cluster(),.resource1_cluster(),.resource2_cluster(),.resource3_cluster(),
 .resource0_size(),.resource1_size(),.resource2_size(),.resource3_size(),
 .audio_slot(3'd4),.snd_found(),.audio_found(found),.audio_cluster(cluster),.audio_size(size),
 .sector_req(req),.sector_lba(lba),.sector_busy(sbusy),.sector_valid(valid),.sector_byte(byte_data),
 .sector_byte_index(idx),.sector_done(sdone),.sector_error(8'd0));
 always @(negedge clk)begin
  valid=0;sdone=0;
  if(rst)begin sbusy=0;pos=0;end
  else if(!sbusy && req)begin
   if(lba>3)$fatal(1,"unexpected directory LBA %d",lba);
   base=lba*512;pos=0;sbusy=1;reads++;
  end else if(sbusy)begin
   if(pos<512 && gap_count<GAP)gap_count++;
   else if(pos<512)begin valid=1;byte_data=disk[base+pos];idx=pos;pos++;gap_count=0;end
   else begin sdone=1;sbusy=0;end
  end
 end
 task word32(input integer at,input reg [31:0] x);
 begin disk[at]=x[7:0];disk[at+1]=x[15:8];disk[at+2]=x[23:16];disk[at+3]=x[31:24];end endtask
 task entry(input integer at,input reg [87:0] name,input integer c,input reg [31:0] bytes,input reg [7:0] attr);
 integer j;begin for(j=0;j<11;j++)disk[at+j]=name[(10-j)*8+:8];disk[at+11]=attr;disk[at+26]=c;word32(at+28,bytes);end endtask
 task setup;
 integer j;begin
  for(j=0;j<2048;j++)disk[j]=0;
  disk[11]=0;disk[12]=2;disk[13]=1;disk[14]=1;disk[16]=1;
  word32(32,101);word32(36,1);word32(44,2);disk[510]=8'h55;disk[511]=8'haa;
  word32(512+8,3);word32(512+12,32'h0fffffff);
  for(j=0;j<16;j++)disk[1024+32*j]=8'he5;
 end endtask
 task scan(input integer mask,input bit af,input reg [31:0] bytes);
 begin
  @(posedge clk);#1;start=1;@(posedge clk);#1;start=0;
  wait(done);@(posedge clk);#1;
  if(err || pics!==mask[3:0] || found!==af)$fatal(1,"scan %0d: err=%h pics=%h found=%b",scenario,err,pics,found);
  if(af && (cluster!=10 || size!==bytes))$fatal(1,"audio metadata %h %h",cluster,size);
  if(!af && (cluster!=0 || size!=0))$fatal(1,"rescan retained metadata");
  scenario++;
 end endtask
 initial begin
  setup();repeat(4)@(posedge clk);#1;rst=0;
  entry(1024,"PIC1    BMP",4,100,32);entry(1056,"PIC2    BMP",5,100,32);
  entry(1088,"PIC3    BMP",6,100,32);entry(1120,"PIC4    BMP",7,100,32);
  entry(1536,"BGM     PCM",10,32'h18000020,32);scan(15,1,32'h18000020);
  if(reads!=4)$fatal(1,"did not follow directory FAT chain");
  setup();entry(1024,"BGM     PCM",10,600,1);disk[1056]=0;scan(0,1,600);
  setup();disk[1024]=0;scan(0,0,0);
  setup();entry(1024,"BGM     PCM",10,600,16);entry(1056,"BGM     PCM",10,600,8);disk[1088]=0;scan(0,0,0);
  setup();entry(1024,"BGM     WAV",10,600,32);disk[1056]=0;scan(0,0,0);
  setup();entry(1024,"BGM     PCM",10,2,32);entry(1056,"BGM     PCM",11,88,32);disk[1088]=0;scan(0,1,2);
  setup();entry(1024,"PIC1    BMP",4,32'h12345678,32);entry(1056,"PIC1    BMP",9,32'hffffffff,32);
  entry(1088,"PIC2    BMP",5,32'h87654321,32);entry(1120,"PIC3    BMP",6,32'h55aa55aa,32);
  entry(1152,"PIC4    BMP",7,32'haa55aa55,32);disk[1184]=0;scan(15,0,0);
  if(dut.resource0_cluster!=4 || dut.resource0_size!=32'h12345678 || dut.resource1_size!=32'h87654321 ||
     dut.resource2_size!=32'h55aa55aa || dut.resource3_size!=32'haa55aa55)$fatal(1,"picture metadata/duplicate mismatch");
  $display("PASS audio scan: 7 scenarios gap=%0d; directory FAT chain, only audio, rescan, attributes, extension, duplicates, all picture size bytes",GAP);$finish;
 end
 initial begin #1000000;$fatal(1,"scan watchdog");end
endmodule
