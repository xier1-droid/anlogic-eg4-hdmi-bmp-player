`timescale 1ns/1ps
// M3 production top wiring: drive the raw video timing and the frame reader's
// 32-bit {RGB,T} words, and check the brightness/contrast output (identity at
// 128/128) against hazard(pixel(x,y)) at adjust_x/adjust_y. Covers the T byte
// select, SYNC_EXTRA alignment through the whole sideband, thumbnail bypass,
// 24-bit T=FF pixels and the black screen before display_valid.
module tb_m3_top;
 `include "hazard_model.svh"
 reg clk=0,pix=0,rst=1;always #5 clk=~clk;always #20 pix=~pix;
 reg hs=1,vs=1,de=0;reg [9:0] x=0;reg [31:0] read_data=0;
 reg valid_picture=1;reg [17:0] descriptor=0;
 reg [7:0] t_now=0;reg [1:0] stage=0;reg [5:0] fc=0;reg plain=0;
 wire [5:0] seg_sel;wire [7:0] seg_data;
 top dut(.clk(clk),.rst_n(!rst),.key1(1'b1),.key2(1'b1),.key4(1'b1),.sw1(1'b0),.sw2(1'b0),
 .sd_miso(1'b1),.uart_rx(1'b1),.seg_sel(seg_sel),.seg_data(seg_data));
 // Pixel content is a function of (x,y): T sweeps every value along a frame.
 function [31:0] word(input integer px,input integer py);
  word={8'(px),8'(py*37),8'(px^py),plain ? 8'hff : 8'(px+py*3)};
 endfunction
 integer line=0,col=0,checks=0,recoloured=0;reg [31:0] w;reg [23:0] want;
 // Non-show-ahead reader: next word the clock after read_en, in raster order.
 always @(posedge pix)if(dut.video_read_en)begin
  read_data<=valid_picture ? word(col,line) : 32'd0;
  if(col==639)begin col=0;line++;end else col++;
 end
 always @(posedge pix)if(!rst)begin
  #1;
  if(dut.adjust_de)begin
   w=word(dut.adjust_x,dut.adjust_y);
   want=!dut.adjust_valid ? 24'd0 : hazard_model(w[31:8],w[7:0],t_now,stage,stage,1'b1,descriptor[17],fc);
   if(dut.adjusted_rgb!==want)$fatal(1,"x=%0d y=%0d got %h expected %h (word %h)",dut.adjust_x,dut.adjust_y,dut.adjusted_rgb,want,w);
   if(want!==w[31:8])recoloured++;
   checks++;
  end
 end
 task frame(input integer lines);
  begin
   @(negedge pix);vs=0;de=0;repeat(12)@(negedge pix);line=0;col=0;vs=1;
   for(integer y=0;y<lines;y++)
    for(integer px=0;px<800;px++)begin @(negedge pix);de=px<640;x=px;hs=!(px>=656 && px<752);end
   repeat(40)@(negedge pix);
  end
 endtask
 initial begin
  force dut.video_clk=pix;force dut.sd_card_clk=clk;force dut.rst_video=rst;force dut.rst_sd=rst;
  force dut.hs_0=hs;force dut.vs_0=vs;force dut.de_0=de;force dut.video_x_0=x;force dut.video_read_data=read_data;
  force dut.display_valid=valid_picture;force dut.pixel_descriptor=descriptor;force dut.transition_level=5'd16;force dut.transition_wipe=1'b0;
  force dut.audio_enable=1'b1;force dut.audio_image=2'd0;
  force dut.brightness_src=8'd128;force dut.contrast_src=8'd128;force dut.volume_src=4'd10;force dut.selected_src=2'd0;force dut.switch_mode=2'd0;
  force dut.hazard_t_now=t_now;force dut.hazard_stage=stage;force dut.hazard_alert=stage;force dut.hazard_frame_cnt=fc;
  repeat(10)@(negedge pix);rst=0;
  frame(8);                                        // stage 0, t=0: refuge pixels only
  stage=1;t_now=120;fc=6'h3f;frame(8);
  stage=2;t_now=200;fc=6'h00;frame(8);
  stage=3;t_now=239;fc=6'h04;frame(8);
  descriptor={1'b1,2'd0,3'd4,4'b1111,8'd0};frame(8);   // thumbnail: bypass
  descriptor=0;plain=1;frame(8);                    // 24-bit image: T=FF
  plain=0;valid_picture=0;frame(8);                 // before first commit: black
  if(dut.hazard_enable!==1'b1)$fatal(1,"hazard test source not enabled");
  if(checks<7*8*640-640 || recoloured==0)$fatal(1,"missing observations checks=%0d recoloured=%0d",checks,recoloured);
  $display("PASS M3 production top checks=%0d recoloured=%0d",checks,recoloured);$finish;
 end
 initial begin #100000000;$fatal(1,"top watchdog");end
endmodule
