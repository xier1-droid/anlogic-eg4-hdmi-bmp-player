// Elastic stereo sample register. Gain advances only when input is accepted.
// fade_mute ramps the gain to 0 and, once released, back to the volume target
// in steps of 14 per sample (about 100 ms at 48 kHz); volume changes use 256.
module pcm_master_volume(
 input clk,rst,input [3:0] volume_level,input fade_mute,
 input in_valid,output wire in_ready,input signed [15:0] in_left,in_right,
 output reg out_valid,input out_ready,output reg signed [15:0] out_left,out_right
);
 reg [16:0] gain;
 reg [16:0] target,next_gain,step;
 reg fading;
 always @*begin
  case(volume_level)
   0:target=0;1:target=6554;2:target=13107;3:target=19661;4:target=26214;
   5:target=32768;6:target=39322;7:target=45875;8:target=52429;9:target=58982;
   default:target=65536;
  endcase
  if(fade_mute)target=0;
  step=(fading || fade_mute)?17'd14:17'd256;
  if(gain<target)next_gain=(target-gain>step)?gain+step:target;
  else next_gain=(gain-target>step)?gain-step:target;
 end
 wire signed [33:0] left_product=in_left*$signed({1'b0,next_gain});
 wire signed [33:0] right_product=in_right*$signed({1'b0,next_gain});
 assign in_ready=!rst && (!out_valid || out_ready);
 always @(posedge clk or posedge rst)begin
  if(rst)begin gain<=65536;fading<=0;out_valid<=0;out_left<=0;out_right<=0;end
  else begin
   // The fade-in step lasts until the gain is back at the volume target.
   if(fade_mute)fading<=1;
   else if(in_ready && in_valid && next_gain==target)fading<=0;
   if(in_ready)begin
    out_valid<=in_valid;
    if(in_valid)begin gain<=next_gain;out_left<=left_product>>>16;out_right<=right_product>>>16;end
   end
  end
 end
endmodule
