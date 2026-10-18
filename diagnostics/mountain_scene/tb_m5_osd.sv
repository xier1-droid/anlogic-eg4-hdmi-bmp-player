`timescale 1ns/1ps
// M5 scene OSD: bin_to_bram_loader filled through its byte port with a card's
// FONT.BIN/TEXT.BIN (tools/make_scene_pack.py --text, zero-padded to 4096),
// scene_osd on 640x480 timing (800x525, lead_x = pixel_x+2 as in the top).
// Every active pixel of every frame is compared with a model written from the
// layout rules (scene_osd.v header, TEXT.BIN v1): passthrough outside scene
// mode, the four stages with title/subtitle/legend segments, subtitle scroll
// (restart on a new segment, deposited mid positions), escapes and swatches,
// warning frame/block in both blink phases with segments 0/9/13, missing font
// or text, and the undimmed status band.
module tb_m5_osd;
 parameter string FONT_FILE="FONT.BIN";
 parameter string TEXT_FILE="TEXT.BIN";
 reg pix=0,sd=0,rst=1;
 always #20 pix=~pix;
 always #5 sd=~sd;
 reg [7:0] font[0:4095],text[0:4095];
 reg bin_wr=0,bin_sel=0;reg [11:0] bin_addr=0;reg [7:0] bin_data=0;
 wire [10:0] font_addr;wire [15:0] font_data;wire [11:0] text_addr;wire [7:0] text_data;
 bin_to_bram_loader ram(.wr_clk(sd),.bin_wr(bin_wr),.bin_sel(bin_sel),.bin_addr(bin_addr),.bin_data(bin_data),
  .rd_clk(pix),.font_addr(font_addr),.font_data(font_data),.text_addr(text_addr),.text_data(text_data));
 integer hc=0,vc=0;
 wire de=hc<640 && vc<480;
 wire vs=!(vc>=490 && vc<492);
 wire [9:0] px=hc,lead=(hc+2)%800;
 wire [23:0] plain={px[7:0],vc[7:0],8'h5a};
 wire [23:0] banded=plain^24'h0f3c96;
 reg scene=0,warn=0,font_ok=0,text_ok=0;reg [1:0] stage=0;reg [7:0] t_now=0;reg [9:0] frame_cnt=0;
 wire [23:0] rgb_out;
 scene_osd dut(.clk(pix),.rst(rst),.vs(vs),.de(de),.pixel_x(px),.lead_x(lead),.rgb_in(banded),.rgb_plain(plain),
  .scene(scene),.warn(warn),.stage(stage),.t_now(t_now),.frame_cnt(frame_cnt),.font_ok(font_ok),.text_ok(text_ok),
  .font_addr(font_addr),.font_data(font_data),.text_addr(text_addr),.text_data(text_data),.rgb_out(rgb_out));
 always @(posedge pix)if(!rst)begin
  if(hc==799)begin hc<=0;vc<=vc==524 ? 0 : vc+1;end else hc<=hc+1;
 end

 // 5x7 reference glyphs, read once from the shared font module.
 reg [7:0] f_char=0;reg [2:0] f_row=0;wire [4:0] f_pix;
 osd_font_5x7 ref57(.character(f_char),.row(f_row),.pixels(f_pix));
 reg [4:0] g57[0:255][0:6];

 // Model state, updated at the frame boundary like the descriptor fetch.
 integer scroll_m=0,seg_s_q=0,frames=0,checked=0,glyph_px=0,swatch_px=0,frame_px=0,sym_px=0;
 function automatic integer seg_t();return warn ? 0 : 1+stage;endfunction
 function automatic integer seg_s();return warn ? 9 : 5+stage;endfunction
 function automatic integer seg_l();return warn ? 13 : 10+stage;endfunction
 function automatic integer off(input integer n);return {text[5+4*n][3:0],text[4+4*n]};endfunction
 function automatic integer len(input integer n);return text[6+4*n];endfunction
 function automatic bit show(input integer n);return scene && font_ok && text_ok && n<text[3] && len(n)!=0;endfunction
 function automatic [23:0] dim(input [23:0] c);return {1'b0,c[23:17],1'b0,c[15:9],1'b0,c[7:1]};endfunction
 function automatic [23:0] alert();
  case(warn ? 3 : stage)0:return 24'h2080ff;1:return 24'hffd000;2:return 24'hff8000;default:return 24'hff2020;endcase
 endfunction
 function automatic [23:0] swatch(input [2:0] k);
  case(k)0:return 24'hd82020;1:return 24'h20c848;2:return 24'h00ff00;3:return 24'h8c6a3c;
   4:return 24'hffd000;5:return 24'he83020;6:return 24'h8e8a84;default:return 24'hc8d2dc;endcase
 endfunction
 // Text layer at (x,y): 0 none, 1 white, 2 swatch (color in sw).
 function automatic integer text_hit(input integer x,input integer y,output [23:0] sw);
  integer n,rel,y0,code,col,row,w;
  sw=0;text_hit=0;
  if(y>=32 && y<48)begin n=seg_t();rel=x-376;y0=32;end
  else if(y>=416 && y<432)begin n=seg_l();rel=x-8;y0=416;end
  else if(y>=444 && y<460)begin n=seg_s();rel=scroll_m+x-632;y0=444;end
  else return 0;
  if(!show(n) || rel<0 || rel/16>=len(n) || x<8 || x>=632)return 0;
  code=text[(off(n)+rel/16)%4096];col=rel%16;row=(y-y0)%16;
  if(code<128)begin
   w={font[code*32+2*row],font[code*32+2*row+1]};
   if(w>>(15-col)&1)begin glyph_px++;return 1;end
  end else if(code>=8'hf0)begin
   if(col/2<5 && row/2<7 && g57[code<8'hfa ? 48+code-8'hf0 : code==8'hfa ? ":" : code==8'hfb ? "." :
      code==8'hfc ? "-" : code==8'hfd ? "!" : code==8'hfe ? "?" : " "][row/2]>>(4-col/2)&1)begin sym_px++;return 1;end
  end else if(code>=8'he0 && code<8'he8)begin
   if(col>=2 && col<14 && row>=2 && row<14 && (code!=8'he2 || frame_cnt[5]))begin sw=swatch(code[2:0]);swatch_px++;return 2;end
  end
  return 0;
 endfunction
 function automatic [23:0] expect_px(input integer x,input integer y);
  reg [23:0] base,sw;integer hit;
  base=(scene && x>=4 && x<284 && y>=4 && y<28) ? plain : banded;
  if(scene && warn && frame_cnt[4] && (x<8 || x>=632 || y<8 || y>=472))begin frame_px++;return 24'hff2020;end
  hit=text_hit(x,y,sw);
  if(hit==1)return 24'hffffff;
  if(hit==2)return sw;
  if(scene && x>=352 && x<368 && y>=32 && y<48 && (!warn || frame_cnt[4]))return alert();
  if(scene && x>=376 && x<616 && y>=52 && y<56)return x-376<=t_now ? alert() : 24'h404040;
  if((scene && x>=348 && x<636 && y>=28 && y<60) ||
     (show(seg_l()) && x>=4 && x<12+16*len(seg_l()) && y>=412 && y<436) ||
     (show(seg_s()) && x>=8 && x<632 && y>=440 && y<464))return dim(base);
  return base;
 endfunction
 reg [23:0] e;
 always @(negedge pix)if(!rst && de)begin
  e=expect_px(hc,vc);
  if(rgb_out!==e)$fatal(1,"frame %0d x=%0d y=%0d got %h expected %h (scene %0d warn %0d stage %0d scroll %0d)",
   frames,hc,vc,rgb_out,e,scene,warn,stage,scroll_m);
  checked++;
 end
 // The model's scroll follows the same frame rule, after the descriptors.
 always @(posedge pix)if(!rst && hc==40 && vc==490)begin
  if(seg_s()!=seg_s_q || !show(seg_s()) || scroll_m>=624+16*len(seg_s()))scroll_m=0;else scroll_m+=2;
  seg_s_q=seg_s();
  if(dut.scroll!==scroll_m)$fatal(1,"scroll %0d, model %0d",dut.scroll,scroll_m);
  frames++;
 end
 // Settings change before frame_start, as the scenario FSM outputs do.
 task next_frame(input integer s,input integer w,input integer st,input integer t,input integer fc,input integer fo,input integer to);
 begin
  wait(vc==486 && hc==0);@(negedge pix);
  scene=s;warn=w;stage=st;t_now=t;frame_cnt=fc;font_ok=fo;text_ok=to;
  wait(vc==489);
 end endtask
 task deposit(input integer v);
 begin wait(vc==495);@(negedge pix);dut.scroll=v;scroll_m=v;end endtask
 integer fd,n,fbytes,tbytes;
 initial begin
  for(integer i=0;i<4096;i++)begin font[i]=0;text[i]=0;end
  fd=$fopen(FONT_FILE,"rb");if(!fd)$fatal(1,"no %s",FONT_FILE);fbytes=$fread(font,fd);$fclose(fd);
  fd=$fopen(TEXT_FILE,"rb");if(!fd)$fatal(1,"no %s",TEXT_FILE);tbytes=$fread(text,fd);$fclose(fd);
  if(text[0]!="T" || text[1]!="X" || text[2]!=1 || text[3]!=14)$fatal(1,"TEXT.BIN header");
  for(integer c=0;c<256;c++)for(integer r=0;r<7;r++)begin f_char=c;f_row=r;#1;g57[c][r]=f_pix;end
  repeat(4)@(posedge sd);
  for(integer s=0;s<2;s++)for(integer a=0;a<4096;a++)begin
   @(negedge sd);bin_wr=1;bin_sel=s;bin_addr=a;bin_data=s ? text[a] : font[a];
  end
  @(negedge sd);bin_wr=0;
  @(negedge pix);rst=0;
  next_frame(0,0,0,0,0,1,1);next_frame(0,0,0,0,0,1,1);
  // Stage 1: the subtitle enters from the right, 2 pixels per frame.
  next_frame(1,0,0,0,16,1,1);next_frame(1,0,0,60,16,1,1);next_frame(1,0,0,120,48,1,1);
  deposit(380);next_frame(1,0,0,200,48,1,1);next_frame(1,0,0,239,0,1,1);
  // Stages 2-4: new segments restart the subtitle; mid positions deposited.
  for(n=1;n<4;n++)begin
   next_frame(1,0,n,n*50,32,1,1);deposit(250+n*130);next_frame(1,0,n,n*50+1,32,1,1);
   deposit(624+16*len(5+n)-1);next_frame(1,0,n,239,0,1,1);next_frame(1,0,n,239,0,1,1);
  end
  // Warning mode: blink on and off, then its subtitle mid-way.
  next_frame(1,1,3,239,16,1,1);next_frame(1,1,3,239,0,1,1);deposit(400);next_frame(1,1,3,239,48,1,1);
  // Missing font or text: panel only.
  next_frame(1,0,1,100,16,0,1);next_frame(1,0,1,100,16,1,0);
  next_frame(0,0,1,100,16,1,1);
  wait(vc==489);
  if(glyph_px==0 || swatch_px==0 || frame_px==0 || sym_px==0)$fatal(1,"coverage: glyph %0d swatch %0d frame %0d symbol %0d",glyph_px,swatch_px,frame_px,sym_px);
  $display("PASS M5 scene OSD: %0d frames, %0d pixels (glyph %0d, symbol %0d, swatch %0d, frame %0d), FONT %0d B TEXT %0d B",
   frames,checked,glyph_px,sym_px,swatch_px,frame_px,fbytes,tbytes);
  $finish;
 end
 initial begin #2000000000;$fatal(1,"watchdog");end
endmodule
