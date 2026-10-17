`timescale 1ns/1ps
// UART log and UART subtitle removal: the default top (both off) against the
// previous wiring (both on, uart_rx idle) under identical forced video. The
// final OSD pixels must match on every active pixel of full-height frames, so
// the scrolling subtitle and its band are covered; uart_tx must stay high.
// +define+MUTANT replaces the fixed subtitle text and must fail.
module tb_m3_uart_off;
 reg clk=0,pix=0,rst=1;always #5 clk=~clk;always #20 pix=~pix;
 reg hs=1,vs=1,de=0;reg [9:0] x=0;reg [31:0] read_data=0;
 wire [5:0] sel_old,sel_new;wire [7:0] seg_old,seg_new;wire tx_old,tx_new;
 top #(.UART_LOG_ENABLE(1),.UART_SUBTITLE_ENABLE(1)) dut_old(.clk(clk),.rst_n(!rst),.key1(1'b1),.key2(1'b1),.key4(1'b1),
 .sw1(1'b0),.sw2(1'b0),.sd_miso(1'b1),.uart_rx(1'b1),.uart_tx(tx_old),.seg_sel(sel_old),.seg_data(seg_old));
 top dut_new(.clk(clk),.rst_n(!rst),.key1(1'b1),.key2(1'b1),.key4(1'b1),
 .sw1(1'b0),.sw2(1'b0),.sd_miso(1'b1),.uart_rx(1'b1),.uart_tx(tx_new),.seg_sel(sel_new),.seg_data(seg_new));
 function [31:0] word(input integer px,input integer py);
  word={8'(px*5),8'(py*37),8'(px^py),8'(px+py*3)};
 endfunction
 integer line=0,col=0,checks=0,glyphs=0,tx_low=0;
 always @(posedge pix)if(dut_new.video_read_en)begin
  read_data<=word(col,line);
  if(col==639)begin col=0;line++;end else col++;
 end
 always @(posedge pix)if(!rst)begin
  #1;
  if(dut_old.video_read_en!==dut_new.video_read_en)$fatal(1,"read_en differs");
  if({dut_old.ring_hs,dut_old.ring_vs,dut_old.ring_de}!=={dut_new.ring_hs,dut_new.ring_vs,dut_new.ring_de})
   $fatal(1,"sync differs");
  if(dut_new.ring_de)begin
   if(dut_old.band_rgb!==dut_new.band_rgb)$fatal(1,"x=%0d line=%0d old %h new %h",
    dut_new.ring_x,dut_new.u_scroll_osd.line_y,dut_old.band_rgb,dut_new.band_rgb);
   if(dut_new.scroll_glyph_active)glyphs++;
   checks++;
  end
 end
 always @(posedge clk)if(!rst && tx_new!==1'b1)tx_low++;
 task frame(input integer lines);
  begin
   @(negedge pix);vs=0;de=0;repeat(12)@(negedge pix);line=0;col=0;vs=1;
   for(integer y=0;y<lines;y++)
    for(integer px=0;px<800;px++)begin @(negedge pix);de=px<640;x=px;hs=!(px>=656 && px<752);end
   repeat(40)@(negedge pix);
  end
 endtask
 `define DRIVE(d) \
  force d.video_clk=pix;force d.sd_card_clk=clk;force d.rst_video=rst;force d.rst_sd=rst; \
  force d.hs_0=hs;force d.vs_0=vs;force d.de_0=de;force d.video_x_0=x;force d.video_read_data=read_data; \
  force d.display_valid=1'b1;force d.pixel_descriptor=18'd0;force d.transition_level=5'd16;force d.transition_wipe=1'b0; \
  force d.audio_enable=1'b1;force d.audio_image=2'd0; \
  force d.brightness_src=8'd128;force d.contrast_src=8'd128;force d.volume_src=4'd10;force d.selected_src=2'd0;force d.switch_mode=2'd0;
 initial begin
  `DRIVE(dut_old)
  `DRIVE(dut_new)
`ifdef MUTANT
  force dut_new.sub_text_pixel=120'h000000414141414141414141414141;
`endif
  repeat(10)@(negedge pix);rst=0;
  // Start both scrolls mid-way so the whole subtitle is on screen at once.
  dut_old.u_scroll_osd.started=1;dut_old.u_scroll_osd.scroll=200;
  dut_new.u_scroll_osd.started=1;dut_new.u_scroll_osd.scroll=200;
  repeat(6)frame(470);
  if(checks<6*470*640-640 || glyphs<1000)$fatal(1,"missing observations checks=%0d glyphs=%0d",checks,glyphs);
  if(tx_low)$fatal(1,"uart_tx left idle %0d cycles",tx_low);
  $display("PASS UART removal checks=%0d glyphs=%0d",checks,glyphs);$finish;
 end
 initial begin #400000000;$fatal(1,"top watchdog");end
endmodule
