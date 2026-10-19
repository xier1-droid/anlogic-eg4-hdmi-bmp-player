// Parameter state in the SD control domain. Selection 0=B, 1=C, 2=V, 3=S
// (scene speed 0:1x 1:2x 2:4x, selectable only in scene mode, after V).
module media_adjust_control(
 input clk,rst,input [1:0] mode,
 input decrease,increase,restore,select_next,
 output reg [7:0] brightness,contrast,
 output reg [3:0] volume_level,output reg [1:0] selected,
 input scene_mode,output reg [1:0] speed
);
 reg [1:0] mode_q;
 function [7:0] step;
  input [7:0] value;input up;
  begin step=up ? (value>239?8'd255:value+8'd16) : (value<16?8'd0:value-8'd16);end
 endfunction
 always @(posedge clk or posedge rst)begin
  if(rst)begin brightness<=128;contrast<=128;volume_level<=10;selected<=0;mode_q<=0;speed<=0;end
  else begin
   mode_q<=mode;
   if(mode!=mode_q || (selected==3 && !scene_mode))selected<=mode==2?1:0;
   else if(mode==1 || mode==2)begin
    if(select_next)selected<=selected==2 && scene_mode ? 2'd3 : selected[1] ? (mode==2?2'd1:2'd0) : 2'd2;
    else if(restore)begin
     case(selected)0:brightness<=128;1:contrast<=128;2:volume_level<=10;3:speed<=0;endcase
    end else if(decrease || increase)begin
     case(selected)
      0:brightness<=step(brightness,increase);
      1:contrast<=step(contrast,increase);
      2:if(increase && volume_level<10)volume_level<=volume_level+1'b1;
        else if(decrease && volume_level>0)volume_level<=volume_level-1'b1;
      3:if(increase && speed<2)speed<=speed+1'b1;
        else if(decrease && speed>0)speed<=speed-1'b1;

     endcase
    end
   end
  end
 end
endmodule
