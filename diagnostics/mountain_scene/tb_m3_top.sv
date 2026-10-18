`timescale 1ns/1ps
// M3 v3 production top wiring: drive the raw video timing and the frame
// reader's 32-bit {RGB,T} words, force the layer's frame inputs, and check
// the brightness/contrast output (identity at 128/128) against the scalar
// layer of hazard_v3 at adjust_x/adjust_y. Kinds with no shake keep the
// check per pixel: landslide evacuation and debris aftermath (with rain)
// read T, x, y and frame_cnt; earthquake cause reads the wave/ring regions. Also
// thumbnail bypass, no kind (T ignored) and the black screen before
// display_valid. The full kind set is covered by tb_m3v3_sweep/card.
module tb_m3_top;
 reg clk=0,pix=0,rst=1;always #5 clk=~clk;always #20 pix=~pix;
 reg hs=1,vs=1,de=0;reg [9:0] x=0;reg [31:0] read_data=0;
 reg valid_picture=1;reg [17:0] descriptor=0;
 reg [7:0] t_now=0;reg [2:0] hz=0,role=0;reg [9:0] fc=0;
 wire [5:0] seg_sel;wire [7:0] seg_data;
 top dut(.clk(clk),.rst_n(!rst),.key1(1'b1),.key2(1'b1),.key4(1'b1),.sw1(1'b0),.sw2(1'b0),
 .sd_miso(1'b1),.uart_rx(1'b1),.seg_sel(seg_sel),.seg_data(seg_data));
 // Pixel content is a function of (x,y); T sweeps all regions and times.
 function [31:0] word(input integer px,input integer py);
  word={8'(px*5),8'(py*37),8'(px^py),8'(px+py*3)};
 endfunction
 function [7:0] hash8(input [7:0] a,input [7:0] b);
  reg [7:0] h;begin h=a*8'd73+b*8'd151+(a^b)*8'd37;hash8=h^(h>>4);end
 endfunction
 function [23:0] blend(input [23:0] a,input [23:0] c,input integer k);
  for(int i=0;i<3;i++)case(k)
   1:blend[i*8+:8]=(a[i*8+:8]>>1)+(a[i*8+:8]>>2)+(c[i*8+:8]>>2);
   2:blend[i*8+:8]=(a[i*8+:8]>>1)+(c[i*8+:8]>>1);
   default:blend[i*8+:8]=(a[i*8+:8]>>2)+(c[i*8+:8]>>1)+(c[i*8+:8]>>2);
  endcase
 endfunction
 // hazard_v3.rain_masks for one layer: (cell w/h shift, length, vx, vy, salt).
 function rain_on(input integer px,input integer py,input integer sw,input integer sh,
  input integer len,input integer vx,input integer vy,input integer salt,input integer density);
  integer u,v,lu,lv,k,hsh,ox,oy,d;
  begin
   u=(px+vx*fc)&4095;v=(py-vy*fc)&16383;
   lu=u&((1<<sw)-1);lv=v&((1<<sh)-1);
   k=((u>>sw)*167+(v>>sh)*89+salt)&255;hsh=k^(k>>3);
   ox=(k>>4)&((1<<(sw-1))-1);oy=(k^(k>>5))&((1<<(sh-1))-1);d=lv-oy;
   rain_on=hsh<density && d>=0 && d<len && lu==ox+(len>>2)-(d>>2);
  end
 endfunction
 // Scalar copies of hazard_v3.render for the three kinds used here.
 function [23:0] model(input [23:0] rgb,input [7:0] T,input integer px,input integer py);
  integer region,tm,t6,age,k,density;reg layer,covered,fast,slow;
  begin
   model=rgb;
   if(descriptor[17] || hz<1 || hz>4 || role<1 || role>4)return model;
   // Rain under the hazard terms (which blend from rgb): cause level 2,
   // onset/aftermath level 1, none for evacuation and earthquake.
   if(hz!=4 && role<=3)begin
    density=role==1 ? 32+(t_now>>2) : 28;
    if(rain_on(px,py,4,6,14,4,16,0,density))model=blend(model,24'hc8d2dc,2);
    if(rain_on(px,py,3,5,6,2,8,53,density))model=blend(model,24'ha8b4c0,1);
   end
   layer=T!=8'hff;region=T>>6;tm=T&63;t6=t_now>>2;covered=layer && tm<=t6;age=(t6-tm)&63;
   fast=role==4 || role==3 ? fc[2] : role==2 ? fc[3] : fc[4];slow=fc[5];
   if(hz==1 && role==4)begin
    if(region==0 && covered)
     model=age<2 ? (fast ? 24'hffffff : 24'h40ff40) : (((tm*4-(fc>>1))&7)<3) ? 24'haaffbe : blend(rgb,24'h20c848,3);
    else if(region==1 && layer && (((px+py+(fc>>2))&31)<3))model=blend(rgb,24'hd82020,3);
    else if(region==2 && layer && slow)model=24'h00ff00;
   end else if(hz==2 && role==3)begin
    if(region==1 && layer)model=blend(rgb,24'h4e3a26,2);
    else if(region==0 && covered)begin
     if(hash8(px>>1,py>>1)<8)model=blend(rgb,24'h585450,3);
     else if(hash8(px,py)<18)model=blend(rgb,24'h625e58,3);
     else if(age<10)model=blend(rgb,24'h5a442e,3);
     else model=blend(rgb,24'h7a5e40,(tm>>2)&1 ? 3 : 2);
    end
   end else if(hz==4 && role==1)begin
    k=t6-24-tm;
    if(region==0 && layer)begin
     if(t_now>=96)model=blend(rgb,24'he83020,fast ? 3 : 2);
     else if(t_now>=16)model=blend(rgb,24'he83020,slow ? 2 : 1);
    end else if(region==1 && covered)model=age<2 ? 24'hffe040 : blend(rgb,24'hfafafa,3);
    else if(region==2 && covered)model=blend(rgb,24'h181818,2);
    else if(region==3 && layer && k>=0 && k<24 && k%6==0)model=blend(rgb,24'hfafafa,1);
   end
  end
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
   want=!dut.adjust_valid ? 24'd0 : model(w[31:8],w[7:0],dut.adjust_x,dut.adjust_y);
   if(dut.adjusted_rgb!==want)$fatal(1,"x=%0d y=%0d kind=%0d/%0d got %h expected %h (word %h)",
    dut.adjust_x,dut.adjust_y,hz,role,dut.adjusted_rgb,want,w);
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
  force dut.hazard_enable=1'b1;force dut.hazard_t_now=t_now;force dut.hazard_kind_hazard=hz;force dut.hazard_kind_role=role;force dut.hazard_frame_cnt=fc;
  repeat(10)@(negedge pix);rst=0;
  frame(8);                                                   // no kind: T ignored
  hz=1;role=4;t_now=150;fc=10'h3a7;frame(24);                 // landslide evacuation
  hz=2;role=3;t_now=200;fc=10'h081;frame(24);                 // debris flow aftermath
  hz=4;role=1;t_now=140;fc=10'h3f0;frame(24);                 // earthquake cause (rings, wave)
  descriptor={1'b1,2'd0,3'd4,4'b1111,8'd0};frame(8);          // thumbnail: bypass
  descriptor=0;valid_picture=0;frame(8);                      // before first commit: black
  if(dut.hazard_enable!==1'b1)$fatal(1,"hazard test source not enabled");
  if(checks<(8+24*3+8+8)*640-640 || recoloured<10000)$fatal(1,"missing observations checks=%0d recoloured=%0d",checks,recoloured);
  $display("PASS M3 production top checks=%0d recoloured=%0d",checks,recoloured);$finish;
 end
 initial begin #200000000;$fatal(1,"top watchdog");end
endmodule
