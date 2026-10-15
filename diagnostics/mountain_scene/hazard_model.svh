// Scalar hazard_layer v2 model written from tools/scenes/README.md, for the
// chain and top tests. tb_m3_hazard_sweep/card check the RTL against Python.
function automatic [7:0] blend_ch(input [7:0] a,input [7:0] c,input integer k);
 case(k) 1:blend_ch=(a>>1)+(a>>2)+(c>>2); 2:blend_ch=(a>>1)+(c>>1); default:blend_ch=(a>>2)+(c>>1)+(c>>2); endcase
endfunction
function automatic [23:0] blend(input [23:0] a,input [23:0] c,input integer k);
 for(int ch=0;ch<3;ch++)blend[ch*8+:8]=blend_ch(a[ch*8+:8],c[ch*8+:8],k);
endfunction
function automatic [23:0] hazard_model(input [23:0] rgb,input [7:0] T,input [7:0] t_now,
 input [1:0] stage,alert,input en,thumb,input [5:0] fc,input integer x,y);
 reg covered,front,fast,slow,ripple,dash,rain;integer age,col,h,k;
 begin
  covered = T<240 && T<=t_now;
  age = (t_now-T)&255;
  front = covered && age<6;
  fast = fc[alert==3 ? 2 : alert==2 ? 3 : 4];
  slow = fc[5];
  ripple = ((T-(fc>>1))&15)<2;
  dash = ((T-(fc>>1))&7)<3;
  col = (x+(y>>2))&1023;
  h = (((col*157)&2047)>>3)^(col&255);
  rain = stage==0 && h<4+(t_now>>5) && ((y-8*fc+4*col)&31)<12;
  hazard_model = rgb;
  if(en && !thumb)begin
   if(covered && stage!=0)begin
    case(stage)
     1:hazard_model = front && fast ? 24'hffd000 : blend(rgb,24'h180e06,3);
     2:begin
      k = age<24 ? 1 : age<64 ? 2 : 3;
      hazard_model = front ? blend(rgb,24'hf0e8d6,fast ? 2 : 1) : blend(rgb,ripple ? 24'hc4a874 : 24'h8c6a3c,k);
     end
     default:hazard_model = front ? (fast ? 24'hffffff : 24'h40ff40) : dash ? 24'haaffbe : blend(rgb,24'h20c848,3);
    endcase
   end else if(T==250 && slow)hazard_model = 24'h00ff00;
   else if(rain)hazard_model = blend(rgb,24'hc8d2dc,2);
  end
 end
endfunction
