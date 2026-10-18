`timescale 1ns/1ps
// fat32_volume_scanner SND1-4: each stage file gets its own slot beside
// PIC1-4 and BGM; audio_slot 0-3 reports SND1-4 and 4 reports BGM. The scan
// stops early only when every picture and audio file is found, otherwise it
// follows the directory chain to its end. Covers a second directory cluster,
// partial sets, duplicates (first wins), near-miss names and attributes, and
// a rescan clearing the table. Disk model as pcm_audio/tb_audio_scan.
module tb_m4_scanner #(parameter integer GAP=0);
 reg clk=0;always #5 clk=~clk;reg rst=1,start=0;
 reg [2:0] slot=4;
 wire busy,done,req,found;wire [7:0] err;wire [31:0] lba,cluster,size;wire [3:0] pics,snd;
 reg sbusy=0,valid=0,sdone=0;reg [7:0] byte_data=0;reg [8:0] idx=0;
 reg [7:0] disk[0:2047];integer base=0,pos=0,reads=0,scenario=0,gap_count=0,checks=0;
 fat32_volume_scanner #(.SCAN_AUDIO(1)) dut(
 .clk(clk),.rst_n(!rst),.scan_start(start),.scan_busy(busy),.scan_done(done),.fs_error(err),
 .partition_lba(),.sectors_per_cluster(),.fat_start_lba(),.data_start_lba(),.max_cluster(),
 .resource_valid(pics),.resource0_cluster(),.resource1_cluster(),.resource2_cluster(),.resource3_cluster(),
 .resource0_size(),.resource1_size(),.resource2_size(),.resource3_size(),
 .audio_slot(slot),.snd_found(snd),.audio_found(found),.audio_cluster(cluster),.audio_size(size),
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
 // Expected table: cluster and size per slot (0-3 SND1-4, 4 BGM), 0 if absent.
 integer exp_cluster[0:4],exp_size[0:4];
 task expect_none;integer j;begin for(j=0;j<5;j++)begin exp_cluster[j]=0;exp_size[j]=0;end end endtask
 task scan(input integer pic_mask,input integer exp_reads);
 integer s,reads0;reg [3:0] snd_mask;
 begin
  reads0=reads;
  @(posedge clk);#1;start=1;@(posedge clk);#1;start=0;
  wait(done);@(posedge clk);#1;
  snd_mask=0;for(s=0;s<4;s++)snd_mask[s]=exp_size[s]!=0;
  if(err || pics!==pic_mask[3:0] || snd!==snd_mask)$fatal(1,"scan %0d: err=%h pics=%h snd=%b expected %b",scenario,err,pics,snd,snd_mask);
  if(reads-reads0!=exp_reads)$fatal(1,"scan %0d: %0d sector reads, expected %0d",scenario,reads-reads0,exp_reads);
  for(s=0;s<8;s++)begin
   slot=s;#1;
   if(found!==(exp_size[s>3?4:s]!=0) || cluster!==exp_cluster[s>3?4:s] || size!==exp_size[s>3?4:s])
    $fatal(1,"scan %0d slot %0d: found=%b cluster=%0d size=%h",scenario,s,found,cluster,size);
   checks++;
  end
  slot=4;scenario++;
 end endtask
 initial begin
  setup();expect_none();repeat(4)@(posedge clk);#1;rst=0;
  // Complete scene card in the first directory cluster: stops after it.
  entry(1024,"PIC1    BMP",4,100,32);entry(1056,"PIC2    BMP",5,100,32);
  entry(1088,"PIC3    BMP",6,100,32);entry(1120,"PIC4    BMP",7,100,32);
  entry(1152,"SND3    PCM",20,32'h00030002,32);entry(1184,"BGM     PCM",10,32'h18000020,32);
  entry(1216,"SND1    PCM",21,32'h11223344,1);entry(1248,"SND4    PCM",22,600,2);
  entry(1280,"SND2    PCM",23,32'h00000400,4);
  exp_cluster='{21,23,20,22,10};exp_size='{32'h11223344,32'h400,32'h00030002,600,32'h18000020};
  scan(15,2);
  // Same files with SND2 in the second cluster: the chain is followed.
  entry(1280,"SND2    WAV",23,32'h400,32);entry(1536,"SND2    PCM",24,1234,32);
  exp_cluster[1]=24;exp_size[1]=1234;scan(15,4);
  // Without SND2 the scan runs to the directory end (second cluster, empty).
  disk[1536]=0;exp_cluster[1]=0;exp_size[1]=0;scan(15,4);
  // Stage files only, duplicates and near misses.
  setup();expect_none();
  entry(1024,"SND2    PCM",30,32'h22,32);entry(1056,"SND2    PCM",31,32'h99,32);
  entry(1088,"SND5    PCM",32,32'h55,32);entry(1120,"SND0    PCM",33,32'h50,32);
  entry(1152,"SND4    PCX",34,32'h44,32);entry(1184,"SNE4    PCM",35,32'h44,32);
  entry(1216,"SND4    PCM",36,32'h44,8'h10);entry(1248,"SND4    PCM",37,32'h44,8'h08);
  entry(1280,"SND4 1  PCM",38,32'h44,32);entry(1312,"SND4    PCM",39,32'h4444,32);
  disk[1344]=0;
  exp_cluster[1]=30;exp_size[1]=32'h22;exp_cluster[3]=39;exp_size[3]=32'h4444;
  scan(0,2);
  // Rescan of an empty card clears the table.
  setup();disk[1024]=0;expect_none();scan(0,2);
  // BGM only: the BGM fallback is still reported on slot 4.
  setup();entry(1024,"BGM     PCM",10,600,1);disk[1056]=0;expect_none();exp_cluster[4]=10;exp_size[4]=600;scan(0,2);
  $display("PASS M4 scanner: %0d scans, %0d slot checks gap=%0d; SND1-4 slots, early stop only when complete, second cluster, partial sets, duplicates, near misses, rescan, BGM-only",scenario,checks,GAP);
  $finish;
 end
 initial begin #2000000;$fatal(1,"scan watchdog");end
endmodule
