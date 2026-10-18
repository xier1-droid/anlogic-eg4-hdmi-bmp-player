`timescale 1ns/1ps
module tb_scroll_params;
 reg clk=0,rst=1,vs=1,de=0,valid=0;
 reg [9:0] x=0;
 wire [23:0] rgb;
 wire active;
 always #5 clk=~clk;
 scroll_text_overlay #(.TEXT_LEN(1),.TEXT("A"),.WINDOW_LEFT(4),
  .WINDOW_RIGHT(36),.TEXT_Y(4),.PIXELS_PER_FRAME(5)) dut(
  .clk(clk),.rst(rst),.vs(vs),.de(de),.pixel_x(x),.image_valid(valid),
  .rgb_in(24'h123456),.rgb_out(rgb),.active(active),.runtime_text(120'd0),.runtime_length(4'd0),.runtime_enable(1'b1),.runtime_text_changed(1'b0),.font_addr(),.font_data(16'd0),.font_valid(1'b0));
 reg [34:0] bitmap={5'b01110,5'b10001,5'b10001,5'b11111,5'b10001,5'b10001,5'b10001};
 integer f,y,col,step=0,lx,gx,gy,checks=0;
 bit hit;
 initial begin
  #21;rst=0;valid=1;
  for(f=0;f<24;f=f+1)begin
   @(negedge clk);vs=0;de=0;
   if(f>0)step=(step==48)?0:((step+5>=48)?48:step+5);
   repeat(4)@(negedge clk);vs=1;
   for(y=0;y<24;y=y+1)begin
    for(col=0;col<40;col=col+1)begin
     @(negedge clk);de=1;x=col;
     lx=col-36+step;gx=(lx%16)/2;gy=(y-4)/2;hit=0;
     if(col>=4 && col<36 && y>=4 && y<18 && lx>=0 && lx<16 && gx<5)
      hit=bitmap[34-gy*5-gx];
     #1;
     if(active!==hit || rgb!==(hit?24'hffffff:24'h123456))
      $fatal(1,"parameterized scroll f=%0d x=%0d y=%0d",f,col,y);
     checks=checks+1;
    end
    @(negedge clk);de=0;repeat(2)@(negedge clk);
   end
  end
  $display("PASS scroll parameters: %0d pixels, shifted window, step five, clamped exit and wrap",checks);
  $finish;
 end
 initial begin #1000000;$fatal(1,"parameter watchdog");end
endmodule
