`timescale 1ns/1ps
// M5 subtitle font source: scroll_text_overlay with the case font (BRAM_FONT=0)
// against BRAM_FONT=1 reading a FONT.BIN from tools/make_scene_pack.py --text
// (font_valid=1) and BRAM_FONT=1 without a font (font_valid=0; v0.18: no case
// font, Chinese glyphs blank). Runtime text carries all 13 original glyphs
// 0x80-0x8C and two ASCII letters; the outputs must agree on every pixel at
// scroll positions covering each glyph at every sub-cell offset, plus the
// production text. Without a font the expected output is the case font with
// its Chinese pixels removed.
module tb_m5_scroll_font;
 parameter string FONT_FILE="FONT.BIN";
 reg pix=0,sd=0,rst=1;
 always #20 pix=~pix;
 always #5 sd=~sd;
 reg [7:0] font[0:4095];
 reg bin_wr=0;reg [11:0] bin_addr=0;reg [7:0] bin_data=0;
 wire [10:0] font_addr;wire [15:0] font_data;
 bin_to_bram_loader ram(.wr_clk(sd),.bin_wr(bin_wr),.bin_sel(1'b0),.bin_addr(bin_addr),.bin_data(bin_data),
  .rd_clk(pix),.font_addr(font_addr),.font_data(font_data),.text_addr(12'd0),.text_data());
 integer hc=0,vc=0;
 wire de=hc<640 && vc<480;
 wire vs=!(vc>=490 && vc<492);
 wire [9:0] px=hc;
 wire [23:0] bg={px[7:0],vc[7:0],8'h33};
 reg [119:0] text;reg [3:0] length;
 wire [23:0] case_rgb,bram_rgb,fallback_rgb;wire case_hit,bram_hit,fallback_hit;
 scroll_text_overlay #(.CN_ENABLE(1),.RUNTIME_ENABLE(1)) case_font(.clk(pix),.rst(rst),.vs(vs),.de(de),.pixel_x(px),
  .image_valid(1'b1),.rgb_in(bg),.rgb_out(case_rgb),.active(case_hit),.runtime_text(text),.runtime_length(length),
  .runtime_enable(1'b1),.runtime_text_changed(1'b0),.font_addr(),.font_data(16'd0),.font_valid(1'b0));
 scroll_text_overlay #(.CN_ENABLE(1),.RUNTIME_ENABLE(1),.BRAM_FONT(1)) bram_font(.clk(pix),.rst(rst),.vs(vs),.de(de),.pixel_x(px),
  .image_valid(1'b1),.rgb_in(bg),.rgb_out(bram_rgb),.active(bram_hit),.runtime_text(text),.runtime_length(length),
  .runtime_enable(1'b1),.runtime_text_changed(1'b0),.font_addr(font_addr),.font_data(font_data),.font_valid(1'b1));
 scroll_text_overlay #(.CN_ENABLE(1),.RUNTIME_ENABLE(1),.BRAM_FONT(1)) no_font(.clk(pix),.rst(rst),.vs(vs),.de(de),.pixel_x(px),
  .image_valid(1'b1),.rgb_in(bg),.rgb_out(fallback_rgb),.active(fallback_hit),.runtime_text(text),.runtime_length(length),
  .runtime_enable(1'b1),.runtime_text_changed(1'b0),.font_addr(),.font_data(16'hffff),.font_valid(1'b0));
 always @(posedge pix)if(!rst)begin
  if(hc==799)begin hc<=0;vc<=vc==524 ? 0 : vc+1;end else hc<=hc+1;
 end
 integer checked=0,hits=0,cn_blanked=0,frames=0;
 wire cn_pixel=case_hit && case_font.is_cn;
 wire [23:0] no_font_rgb=cn_pixel ? bg : case_rgb;
 always @(negedge pix)if(!rst && de)begin
  if(bram_rgb!==case_rgb || bram_hit!==case_hit)$fatal(1,"BRAM font: frame %0d x=%0d y=%0d %h vs case %h",frames,hc,vc,bram_rgb,case_rgb);
  if(fallback_rgb!==no_font_rgb || fallback_hit!==(case_hit && !cn_pixel))$fatal(1,"no font: frame %0d x=%0d y=%0d %h vs %h",frames,hc,vc,fallback_rgb,no_font_rgb);
  checked++;if(case_hit)hits++;if(cn_pixel)cn_blanked++;
 end
 task show_at(input integer s);
 begin
  wait(vc==495);@(negedge pix);
  case_font.scroll=s;bram_font.scroll=s;no_font.scroll=s;
  wait(vc==0);wait(vc==481);frames++;
 end endtask
 integer fd,n;
 initial begin
  for(integer i=0;i<4096;i++)font[i]=0;
  fd=$fopen(FONT_FILE,"rb");if(!fd)$fatal(1,"no %s",FONT_FILE);n=$fread(font,fd);$fclose(fd);
  // Runtime text is little-endian by character: index 0 in bits 7:0.
  for(integer i=0;i<13;i++)text[i*8+:8]=8'h80+i;
  text[13*8+:8]="F";text[14*8+:8]="A";length=15;
  repeat(4)@(posedge sd);
  for(integer a=0;a<4096;a++)begin @(negedge sd);bin_wr=1;bin_addr=a;bin_data=font[a];end
  @(negedge sd);bin_wr=0;
  @(negedge pix);rst=0;
  // Text width 240: positions 0..864 in steps of 17 put every glyph at
  // several offsets inside the window [8,632).
  for(integer s=0;s<=864;s+=17)show_at(s);
  // The production subtitle (fixed default text).
  text=120'h0000002041475046208c8b8b8a8389;length=12;
  for(integer s=0;s<=816;s+=23)show_at(s);
  if(hits==0)$fatal(1,"no glyph pixels");
  if(cn_blanked==0)$fatal(1,"no Chinese pixels blanked");
  $display("PASS M5 subtitle font: %0d frames, %0d pixels (%0d glyph), BRAM font equals the case font, no font blanks %0d Chinese pixels (FONT %0d B)",frames,checked,hits,cn_blanked,n);
  $finish;
 end
 initial begin #(64'd4000000000);$fatal(1,"watchdog");end
endmodule
