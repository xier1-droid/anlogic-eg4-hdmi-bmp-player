`timescale 1ns/1ps
module tb_adjust;
 reg clk=0,rst=1;always #5 clk=~clk;
 reg [23:0] rgb;reg [7:0] b=128,c=128;reg [15:0] tag;
 wire [23:0] result;wire [15:0] result_tag;
 brightness_contrast_adjust #(.SIDE_WIDTH(16)) dut(.clk(clk),.rst(rst),.rgb_in(rgb),.brightness(b),.contrast(c),.side_in(tag),.rgb_out(result),.side_out(result_tag));
 reg [23:0] expected[0:3];reg [15:0] tags[0:3];integer n=0,i,x,bi,ci;
 function [7:0] model(input integer p,input integer bv,input integer cv);
  integer t,v;begin t=(p*bv)/128;if(t>255)t=255;v=(((t-128)*cv)>>>7)+128;model=v<0?0:v>255?255:v;end
 endfunction
 always @(posedge clk)if(!rst)begin
  for(integer k=3;k>0;k=k-1)begin expected[k]=expected[k-1];tags[k]=tags[k-1];end
  expected[0]={model(rgb[23:16],b,c),model(rgb[15:8],b,c),model(rgb[7:0],b,c)};tags[0]=tag;
  n=n+1;#1;
  if(n>=4 && (result!==expected[3] || result_tag!==tags[3]))$fatal(1,"pixel mismatch n=%0d got=%h want=%h",n,result,expected[3]);
 end
 initial begin
  rgb=0;tag=0;repeat(3)@(negedge clk);rst=0;
  for(bi=0;bi<6;bi=bi+1)for(ci=0;ci<6;ci=ci+1)for(x=0;x<256;x=x+1)begin
   @(negedge clk);b=bi==5?255:bi*32;c=ci==5?255:ci*32;rgb={8'(x),8'(255-x),8'((x*37)%256)};tag=tag+1;
  end
  repeat(5)@(negedge clk);$display("PASS RGB 9216 vectors, dynamic parameters, four-cycle sidebands");$finish;
 end
endmodule

module tb_adjust_decimal;
 reg clk=0,rst=1,vs=1;always #5 clk=~clk;
 reg [7:0] b=128,c=128;reg [3:0] v=10;
 adjust_osd_overlay dut(.clk(clk),.rst(rst),.vs(vs),.de(1'b0),.pixel_x(10'd0),.rgb_in(24'd0),
 .mode(2'd1),.selected(2'd0),.brightness(b),.contrast(c),.volume_level(v),.rgb_out(),.active());
 function integer number(input [11:0] bcd);
  begin number=bcd[11:8]*100+bcd[7:4]*10+bcd[3:0];end
 endfunction
 initial begin
  repeat(3)@(negedge clk);rst=0;
  for(integer i=0;i<256;i++)begin
   @(negedge clk);b=i;c=255-i;v=i%11;vs=0;
   repeat(3)@(negedge clk);vs=1;repeat(26)@(negedge clk);
   if(number(dut.b_bcd)!=i || number(dut.c_bcd)!=255-i || number(dut.v_bcd)!=(i%11)*10)$fatal(1,"BCD value %0d",i);
  end
  $display("PASS decimal all 256 picture values and 11 volume levels within blanking");$finish;
 end
endmodule

module tb_volume;
 reg clk=0,rst=1;always #5 clk=~clk;
 reg [3:0] level=10;reg iv=0,ready=0;wire ir,ov;reg signed [15:0] l,r;wire signed [15:0] ol,orr;
 pcm_master_volume dut(.clk(clk),.rst(rst),.volume_level(level),.fade_mute(1'b0),.in_valid(iv),.in_ready(ir),.in_left(l),.in_right(r),.out_valid(ov),.out_ready(ready),.out_left(ol),.out_right(orr));
 integer gain=65536,target,next_gain,accepted=0,consumed=0;reg signed [15:0] ql[$],qr[$];reg signed [15:0] el,er;
 reg stalled=0;reg signed [15:0] sl,sr;
 function integer coefficient(input integer v);
  begin coefficient=(v*65536+5)/10;end
 endfunction
 always @(posedge clk)if(!rst)begin
  if(stalled && (!ov || ol!==sl || orr!==sr))$fatal(1,"stalled sample changed");
  if(ov && ready)begin
   if(ql.size()==0)$fatal(1,"unexpected sample");el=ql.pop_front();er=qr.pop_front();
   if(ol!==el || orr!==er)$fatal(1,"volume mismatch %0d / %0d",ol,el);consumed++;
  end
  if(iv && ir)begin
   target=coefficient(level);next_gain=gain;
   if(gain<target)next_gain=target-gain>256?gain+256:target;
   if(gain>target)next_gain=gain-target>256?gain-256:target;
   gain=next_gain;ql.push_back((longint'(l)*gain)>>>16);qr.push_back((longint'(r)*gain)>>>16);accepted++;
  end
  stalled=ov && !ready;sl=ol;sr=orr;
 end
 initial begin
  l=0;r=0;repeat(3)@(negedge clk);rst=0;
  for(integer v=10;v>=0;v--)begin
   level=v;
   for(integer j=0;j<600;j++)begin
    @(negedge clk);ready=(j%7!=0 && j%7!=1);
    if(!iv || ir)begin iv=1;l=j%4==0?-32768:j%4==1?32767:j%4==2?0:-12345;r=-1234+j;end
   end
  end
  @(negedge clk);ready=1;
  while(!ir)@(negedge clk);
  @(negedge clk);iv=0;repeat(4)@(negedge clk);
  if(ql.size()!=0 || gain!=0 || accepted!=consumed)$fatal(1,"drain/convergence failed");
  $display("PASS volume all 11 levels stereo extremes ramp stalls samples=%0d",consumed);$finish;
 end
endmodule

module tb_adjust_cdc;
 reg sc=0,dc=0,sr=1,dr=1,frame=0;always #5 sc=~sc;always #7 dc=~dc;
 reg [23:0] src={2'd0,2'd0,8'd128,8'd128,4'd10};wire [23:0] dst;
 media_adjust_cdc dut(sc,sr,src,dc,dr,frame,dst);
 reg [23:0] old;integer j;
 initial begin
  repeat(4)@(negedge sc);sr=0;dr=0;old=dst;
  for(j=0;j<20;j++)begin @(negedge sc);src={2'd1,2'd2,8'(j*11),8'(255-j),4'd3};end
  repeat(20)@(negedge dc);if(dst!==old)$fatal(1,"midframe change");
  frame=1;@(negedge dc);frame=0;
  if(dst!==src)$fatal(1,"latest state not committed");old=dst;
  repeat(10)@(negedge dc);if(dst!==old)$fatal(1,"unstable frame");
  $display("PASS CDC coalescing atomic frame commit");$finish;
 end
endmodule

module tb_adjust_keys;
 reg clk=0,rst=1,k1=1,k2=1,k4=1;always #5 clk=~clk;
 reg [1:0] mode=0;wire dec,inc,res,sel,nxt,prev,scan,auto_e,activity;
 mode_key_control #(.CLK_FREQ_HZ(1000)) keys(.clk(clk),.rst(rst),.enable(1'b1),.key1(k1),.key2(k2),.key4(k4),.mode(mode),
 .next_event(nxt),.previous_event(prev),.rescan_event(scan),.auto_toggle_event(auto_e),.scene_mode(),.manual_activity(activity),
 .adjust_decrease(dec),.adjust_increase(inc),.adjust_restore(res),.adjust_select(sel));
 wire [7:0] b,c;wire [3:0] v;wire [1:0] selected;
 media_adjust_control ctl(clk,rst,mode,dec,inc,res,sel,b,c,v,selected);
 integer scans=0,autos=0,pictures=0;
 always @(posedge clk)begin if(scan)scans++;if(auto_e)autos++;if(nxt||prev)pictures++;end
 task ticks(input integer t);repeat(t)@(negedge clk);endtask
 task press(input integer key,input integer duration);
  begin if(key==1)k1=0;else if(key==2)k2=0;else k4=0;ticks(duration);k1=1;k2=1;k4=1;ticks(50);end
 endtask
 initial begin
  ticks(4);rst=0;mode=1;ticks(50);
  press(1,60);if(b!=112)$fatal(1,"decrease");
  press(2,2200);if(b!=128 || scans!=0)$fatal(1,"adjust long rescan/repeat");
  press(4,60);if(selected!=2 || autos!=0)$fatal(1,"selection");
  press(1,60);if(v!=9)$fatal(1,"volume decrease");
  k1=0;ticks(45);k2=0;ticks(60);k1=1;k2=1;ticks(60);if(v!=10)$fatal(1,"combo restore");
  press(4,1100);if(selected!=2)$fatal(1,"long KEY4");
  mode=2;ticks(50);if(selected!=1)$fatal(1,"mode selection");
  for(integer j=0;j<10;j++)press(1,60);if(c!=0)$fatal(1,"lower saturation");
  for(integer j=0;j<18;j++)press(2,60);if(c!=255)$fatal(1,"upper saturation");
  k1=0;ticks(50);mode=1;ticks(100);k1=1;ticks(50);if(b!=128 || c!=255)$fatal(1,"cancel mode gesture");
  if(pictures!=0)$fatal(1,"picture event in adjust mode");
  mode=0;ticks(50);press(4,60);press(2,2200);if(scans!=1 || autos!=1)$fatal(1,"legacy control");
  $display("PASS keys modes combo endpoints long holds cancellation legacy");$finish;
 end
endmodule

module tb_adjust_osd;
 reg clk=0,rst=1,vs=1,de=0;always #5 clk=~clk;
 reg [9:0] x=0;reg [1:0] mode=1,selected=0;
 wire [23:0] rgb;wire active;integer yellow=0,white=0,percent=0;
 adjust_osd_overlay dut(.clk(clk),.rst(rst),.vs(vs),.de(de),.pixel_x(x),.rgb_in(24'h804020),
 .mode(mode),.selected(selected),.brightness(8'd128),.contrast(8'd255),.volume_level(4'd10),.rgb_out(rgb),.active(active));
 initial begin
  repeat(3)@(negedge clk);rst=0;vs=0;repeat(3)@(negedge clk);vs=1;
  for(integer y=0;y<55;y++)begin
   for(integer px=0;px<640;px++)begin
    @(negedge clk);de=1;x=px;#1;
    if(active)begin
     if(y<32 || y>=48 || px<8 || px>=296)$fatal(1,"glyph region");
     if(rgb==24'hffff00)yellow++;else if(rgb==24'hffffff)white++;else $fatal(1,"glyph color");
     if(px>=280)percent++;
    end else if(y>=28 && y<52 && px>=4 && px<300)begin if(rgb!==24'h402010)$fatal(1,"band");end
    else if(rgb!==24'h804020)$fatal(1,"outside overlay");
   end
   @(negedge clk);de=0;repeat(3)@(negedge clk);
  end
  if(dut.b_digits!==24'h313238 || dut.c_digits!==24'h323535 || dut.v_digits!==24'h313030)$fatal(1,"decimal conversion");
  if(yellow==0 || white==0 || percent==0)$fatal(1,"missing glyphs");
  mode=0;de=1;x=10;#1;if(rgb!==24'h804020 || active)$fatal(1,"hidden mode");
  $display("PASS OSD bounds highlight decimal and percent pixels");$finish;
 end
endmodule
