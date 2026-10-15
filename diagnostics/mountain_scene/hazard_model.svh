// Scalar hazard_layer model written from tools/scenes/README.md, for the
// chain and top tests. tb_m3_hazard_sweep checks the RTL against Python.
function automatic [23:0] hazard_model(input [23:0] rgb,input [7:0] T,input [7:0] t_now,
 input [1:0] stage,alert,input en,thumb,input [5:0] fc);
 reg [23:0] haz,front_c;reg covered,front,fast,haz_on,half;integer ch;
 begin
  haz = stage==1 ? 24'h603818 : stage==2 ? 24'h2060ff : 24'h20c040;
  front_c = stage==1 ? 24'hffe000 : stage==2 ? 24'hffffff : 24'h40ff40;
  covered = T<240 && T<=t_now;
  front = covered && (t_now-T)<6;
  fast = fc[alert==3 ? 2 : alert==2 ? 3 : 4];
  haz_on = stage!=0;
  hazard_model = rgb;
  if(en && !thumb)begin
   if(haz_on && covered)begin
    half = !front && stage==2;
    if(front && fast)hazard_model = front_c;
    else for(ch=0;ch<3;ch++)
     hazard_model[ch*8+:8] = half ? (rgb[ch*8+:8]>>1)+(haz[ch*8+:8]>>1)
                                  : (rgb[ch*8+:8]>>2)+(haz[ch*8+:8]>>1)+(haz[ch*8+:8]>>2);
   end else if(T==250 && fc[5])hazard_model = 24'h00ff00;
  end
 end
endfunction
