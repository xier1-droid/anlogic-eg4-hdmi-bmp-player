`timescale 1ns/1ps
module tb_scroll_text;
 reg clk=0,rst=1,vs=1,de=0,image_valid=0;
 reg [9:0] x=0;
 reg [23:0] rgb=24'h123456;
 wire [23:0] out_rgb,bypass;
 wire active;
 always #5 clk=~clk;
 scroll_text_overlay dut(.clk(clk),.rst(rst),.vs(vs),.de(de),.pixel_x(x),
  .image_valid(image_valid),.rgb_in(rgb),.rgb_out(out_rgb),.active(active),.runtime_text(120'd0),.runtime_length(4'd0),.runtime_enable(1'b1),.runtime_text_changed(1'b0),.font_addr(),.font_data(16'd0),.font_valid(1'b0));
 scroll_text_overlay #(.ENABLE(0)) off_dut(.clk(clk),.rst(rst),.vs(vs),.de(de),.pixel_x(x),
  .image_valid(image_valid),.rgb_in(rgb),.rgb_out(bypass),.active(),.runtime_text(120'd0),.runtime_length(4'd0),.runtime_enable(1'b1),.runtime_text_changed(1'b0),.font_addr(),.font_data(16'd0),.font_valid(1'b0));
 string slogan="ANLOGIC FPGA IMAGE PLAYER";
 integer expected_step=0,frames=0,checks=0,foreground=0;
 bit expected_started=0;
 function [34:0] bitmap(input [7:0] c);
  case(c)
   "P":bitmap={5'b11110,5'b10001,5'b10001,5'b11110,5'b10000,5'b10000,5'b10000};
   "I":bitmap={5'b01110,5'b00100,5'b00100,5'b00100,5'b00100,5'b00100,5'b01110};
   "C":bitmap={5'b01111,5'b10000,5'b10000,5'b10000,5'b10000,5'b10000,5'b01111};
   "M":bitmap={5'b10001,5'b11011,5'b10101,5'b10101,5'b10001,5'b10001,5'b10001};
   "A":bitmap={5'b01110,5'b10001,5'b10001,5'b11111,5'b10001,5'b10001,5'b10001};
   "N":bitmap={5'b10001,5'b11001,5'b10101,5'b10011,5'b10001,5'b10001,5'b10001};
   "U":bitmap={5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b01110};
   "T":bitmap={5'b11111,5'b00100,5'b00100,5'b00100,5'b00100,5'b00100,5'b00100};
   "O":bitmap={5'b01110,5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b01110};
   "E":bitmap={5'b11111,5'b10000,5'b10000,5'b11110,5'b10000,5'b10000,5'b11111};
   "R":bitmap={5'b11110,5'b10001,5'b10001,5'b11110,5'b10100,5'b10010,5'b10001};
   "0":bitmap={5'b01110,5'b10001,5'b10011,5'b10101,5'b11001,5'b10001,5'b01110};
   "1":bitmap={5'b00100,5'b01100,5'b00100,5'b00100,5'b00100,5'b00100,5'b01110};
   "2":bitmap={5'b01110,5'b10001,5'b00001,5'b00010,5'b00100,5'b01000,5'b11111};
   "3":bitmap={5'b11110,5'b00001,5'b00001,5'b01110,5'b00001,5'b00001,5'b11110};
   "4":bitmap={5'b00010,5'b00110,5'b01010,5'b10010,5'b11111,5'b00010,5'b00010};
   ":":bitmap={5'b00000,5'b00100,5'b00100,5'b00000,5'b00100,5'b00100,5'b00000};
   "-":bitmap={5'b00000,5'b00000,5'b00000,5'b11111,5'b00000,5'b00000,5'b00000};
   "F":bitmap={5'b11111,5'b10000,5'b10000,5'b11110,5'b10000,5'b10000,5'b10000};
   "G":bitmap={5'b01110,5'b10001,5'b10000,5'b10111,5'b10001,5'b10001,5'b01110};
   "L":bitmap={5'b10000,5'b10000,5'b10000,5'b10000,5'b10000,5'b10000,5'b11111};
   "Y":bitmap={5'b10001,5'b10001,5'b01010,5'b00100,5'b00100,5'b00100,5'b00100};
   default:bitmap=0;
  endcase
 endfunction
 task draw_frame(input bit full_frame);
  integer y,col,width,local_x,gx,gy;reg [34:0] bits;reg hit;reg [23:0] want;
  begin
   @(negedge clk);vs=0;de=0;
   if(image_valid) begin
    if(!expected_started)begin expected_started=1;expected_step=0;end
    else expected_step=(expected_step==1024)?0:expected_step+1;
   end
   repeat(4)@(negedge clk);vs=1;
   repeat(4)@(negedge clk);
   for(y=0;y<480;y=y+1) begin
    // Every DE row is present. Outside the subtitle band short rows accelerate
    // the exhaustive 1025-frame motion test; selected frames use full width.
    width=(full_frame || (y>=439 && y<=465))?640:1;
    for(col=0;col<width;col=col+1) begin
     @(negedge clk);de=1;x=col;rgb={8'(col),8'(y),8'(col+y)};
     local_x=col-(632-expected_step);hit=0;
     if(expected_started && col>=8 && col<632 && y>=444 && y<458 && local_x>=0 && local_x<400) begin
      gx=(local_x%16)/2;gy=(y-444)/2;bits=bitmap(slogan[local_x/16]);
      if(gx<5)hit=bits[34-gy*5-gx];
     end
     want=hit?24'hffffff:rgb;
     #1;
     if(out_rgb!==want || active!==hit)$fatal(1,"scroll pixel frame=%0d step=%0d x=%0d y=%0d got=%h want=%h",frames,expected_step,col,y,out_rgb,want);
     if(bypass!==rgb)$fatal(1,"disabled scroll changed RGB");
     if(dut.scroll!==expected_step)$fatal(1,"position changed within frame");
     checks=checks+1;if(hit)foreground=foreground+1;
    end
    @(negedge clk);de=0;x=700;rgb=24'habcdef;#1;
    if(out_rgb!==rgb || active || bypass!==rgb)$fatal(1,"blanking changed");
    repeat(2)@(negedge clk);
   end
   frames=frames+1;
  end
 endtask
 initial begin
  #21;rst=0;
  draw_frame(1);draw_frame(0);
  if(dut.started || dut.scroll!=0)$fatal(1,"scroll started without first image");
  image_valid=1;
  // Entry, full passage, complete exit, wrap, and second entry.
  repeat(1027)draw_frame(expected_step==300 || expected_step==700);
  if(foreground==0)$fatal(1,"no foreground observed");
  @(negedge clk);rst=1;repeat(3)@(negedge clk);rst=0;
  expected_started=0;expected_step=0;image_valid=0;draw_frame(1);
  $display("PASS scroll OSD: %0d frames, %0d pixels, %0d foreground; complete cycle, first-image gate, reset, clipping, blanking, bypass",frames,checks,foreground);
  $finish;
 end
 initial begin #300000000;$fatal(1,"scroll watchdog");end
endmodule
