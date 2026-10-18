`timescale 1ns/1ps
module tb_runtime_pixels;
 reg clk=0,rst=1,vs=1,de=0,enable=1,changed=0,image_valid=0;
 reg [9:0] x=0;
 reg [119:0] text=120'h4189;
 reg [3:0] len=2;
 reg [23:0] bg=24'hffffff;
 wire [23:0] rgb,final_rgb,bypass;
 wire hit,band;
 always #5 clk=~clk;
 scroll_text_overlay #(.RUNTIME_ENABLE(1)) dut(.clk(clk),.rst(rst),.vs(vs),.de(de),.pixel_x(x),
 .image_valid(image_valid),.rgb_in(bg),.rgb_out(rgb),.active(hit),.runtime_text(text),
 .runtime_length(len),.runtime_enable(enable),.runtime_text_changed(changed),.font_addr(),.font_data(16'd0),.font_valid(1'b0));
 scroll_text_overlay #(.RUNTIME_ENABLE(1),.ENABLE(0)) off_dut(.clk(clk),.rst(rst),.vs(vs),.de(de),.pixel_x(x),
 .image_valid(image_valid),.rgb_in(bg),.rgb_out(bypass),.active(),.runtime_text(text),
 .runtime_length(len),.runtime_enable(enable),.runtime_text_changed(changed),.font_addr(),.font_data(16'd0),.font_valid(1'b0));
 osd_alpha_band #(.RUNTIME_ENABLE(1)) bands(.clk(clk),.rst(rst),.vs(vs),.de(de),.pixel_x(x),
 .rgb_in(rgb),.glyph_active(hit),.subtitle_enable(enable && len!=0),.rgb_out(final_rgb),.active(band));
 reg [7:0] font_char;reg [3:0] font_row;wire [15:0] font_bits;
 osd_font_cn_16x16 font(.character(font_char),.row(font_row),.pixels(font_bits));
 reg [15:0] cn_rows[0:207];
 reg [34:0] a_bits={5'b01110,5'b10001,5'b10001,5'b11111,5'b10001,5'b10001,5'b10001};
 integer step=0,frames=0,pixels=0,lit=0,k,r;
 bit started=0;
 task draw;
  integer y,col,width,lx,row,gx;
  reg want_hit,want_band;reg [23:0] want;
  begin
   @(negedge clk);vs=0;de=0;
   if(changed)step=0;
   else if(image_valid && enable)begin
    if(!started)begin started=1;step=0;end
    else step=step==624+len*16 ? 0 : step+1;
   end
   repeat(4)@(negedge clk);vs=1;changed=0;
   for(y=0;y<480;y=y+1)begin
    width=(frames==0 || (y>=439 && y<=465))?640:1;
    for(col=0;col<width;col=col+1)begin
     @(negedge clk);de=1;x=col;bg=(col%2)?24'hff4444:24'hffffff;
     lx=col-632+step;row=y-444;want_hit=0;
     if(started && enable && col>=8 && col<632 && row>=0 && row<16 && lx>=0 && lx<len*16)begin
      if(lx<16)want_hit=cn_rows[144+row][15-lx];
      else begin gx=(lx%16)/2;if(gx<5 && row<14)want_hit=a_bits[34-(row/2)*5-gx];end
     end
     want_band=((col>=4 && col<284 && y>=4 && y<28) ||
                (enable && len!=0 && col>=8 && col<632 && y>=440 && y<464)) && !want_hit;
     want=want_hit?24'hffffff:(want_band?((col%2)?24'h7f2222:24'h7f7f7f):bg);
     #1;
     if(hit!==want_hit || final_rgb!==want || bypass!==bg || band!==want_band)
      $fatal(1,"runtime pixel f=%0d x=%0d y=%0d got=%h want=%h",frames,col,y,final_rgb,want);
     if(dut.scroll!==step)$fatal(1,"runtime motion changed within frame");
     pixels=pixels+1;if(hit)lit=lit+1;
    end
    @(negedge clk);de=0;#1;if(hit || band || rgb!==bg || final_rgb!==bg)$fatal(1,"blanking");
    repeat(2)@(negedge clk);
   end
   frames=frames+1;
  end
 endtask
 initial begin
  $readmemh("cn_reference_rows.hex",cn_rows);
  for(k=0;k<13;k=k+1)for(r=0;r<16;r=r+1)begin
   font_char=128+k;font_row=r;#1;
   if(font_bits!==cn_rows[k*16+r])$fatal(1,"CN glyph %0d row %0d",k,r);
  end
  rst=0;draw();image_valid=1;
  repeat(400)draw();enable=0;repeat(2)draw();enable=1;repeat(260)draw();
  len=0;changed=1;draw();draw();
  if(lit==0)$fatal(1,"no runtime foreground");
  $display("PASS runtime pixels: %0d frames %0d pixels %0d foreground; 208 font rows, CN/ASCII full cycle, OFF pause/ON resume, empty, bypass, glyph masks",frames,pixels,lit);
  $finish;
 end
 initial begin #250000000;$fatal(1,"runtime pixels watchdog");end
endmodule
