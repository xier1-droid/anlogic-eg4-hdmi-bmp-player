`timescale 1ns/1ps
// Hazard layer v3 (cause -> hazard -> evacuation cards). Bit-exact RTL of
// tools/hazard_v3.render; the scene contract is in tools/scenes/README.md.
// Per image: hazard (1 landslide, 2 debris flow, 3 flood, 4 earthquake) and
// role (1 cause, 2 onset, 3 aftermath, 4 evacuation) from BMP header bytes
// 6-7; anything else passes the image through. Per pixel: T=255 no layer,
// else region T[7:6] and time T[5:0] (60..63 are per-region special codes).
// LATENCY clocks from {rgb,T} to rgb_out; the caller delays its syncs by the
// same amount (video_delay SYNC_EXTRA). de must accompany rgb_in; x/y count
// active pixels from frame_start. Frame inputs (t_now, hazard, role, enable,
// thumbnail, frame_cnt) may change only while no active pixel is in flight.
//   C1 decode, flags, hashes          C4 rain far, effect blend
//   C2 noise interpolation, rain      C5 overlay blends (haze/puff, grain/rock)
//   C3 noise, selection, rain near    C6..C10 shake: 9-tap line delay, clamp
module hazard_layer_v017 #(parameter integer LATENCY=10)(   // fixed; documents the caller's SYNC_EXTRA
 input clk,rst,
 input [23:0] rgb_in,input [7:0] t_in,input de,frame_start,
 input [7:0] t_now,input [2:0] hazard,role,
 input enable,thumbnail,input [9:0] frame_cnt,
 output reg [23:0] rgb_out
);
 localparam [23:0] RAIN_NEAR=24'hc8d2dc,RAIN_FAR=24'ha8b4c0;
 // Palette indices; colour terms come from the ROM below.
 localparam [4:0] ZONE=5'd0,DANGER=5'd1,ROUTE=5'd2,DASH=5'd3,ROUTE_TIP=5'd4,ROUTE_TIP_OFF=5'd5,REFUGE=5'd6,MUD=5'd7;
 localparam [4:0] RIPPLE=5'd8,FOAM=5'd9,CRACK=5'd10,SLIDE_DARK=5'd11,SOIL=5'd12,ROCK=5'd13,DUST=5'd14,DEPOSIT=5'd15;
 localparam [4:0] STONE=5'd16,DEPOSIT_EDGE=5'd17,SLURRY=5'd18,SURGE=5'd19,HEAD=5'd20,BOULDER=5'd21,WET_MUD=5'd22,FAULT_GLOW=5'd23;
 localparam [4:0] RING_WHITE=5'd24,RING_DARK=5'd25,QUAKE_NEW=5'd26,TILE=5'd27,WALL=5'd28,GAP=5'd29,ROCK_LIGHT=5'd30;
 localparam [2:0] LS=3'd1,DF=3'd2,FL=3'd3,EQ=3'd4;
 localparam [2:0] CAUSE=3'd1,ONSET=3'd2,AFTER=3'd3,EVAC=3'd4;
 localparam [1:0] NONE=2'd0,CONST=2'd1,BLEND=2'd2;

 function [7:0] hash8(input [7:0] a,input [7:0] b);
  reg [7:0] h;
  begin h=a*8'd73+b*8'd151+(a^b)*8'd37;hash8=h^(h>>4);end
 endfunction
 // k quarters of colour c: 1 a/2+a/4+c/4, 2 a/2+c/2, 3 a/4+c/2+c/4.
 function [23:0] blend(input [23:0] a,input [23:0] c,input [1:0] k);
  integer i;reg [7:0] p,q;
  begin
   for(i=0;i<3;i=i+1)begin
    p=a[i*8+:8];q=c[i*8+:8];
    case(k)
     2'd1:blend[i*8+:8]=(p>>1)+(p>>2)+(q>>2);
     2'd2:blend[i*8+:8]=(p>>1)+(q>>1);
     default:blend[i*8+:8]=(p>>2)+(q>>1)+(q>>2);
    endcase
   end
  end
 endfunction

 // Colour term ROM: {palette index, k} -> k=0 colour, k=1..3 cterm(colour,k).
 function [23:0] tterm(input [4:0] idx,input [1:0] k);
  case({idx,k})
   7'd0:tterm=24'hffd000;   // ZONE k0
   7'd1:tterm=24'h3f3400;
   7'd2:tterm=24'h7f6800;
   7'd3:tterm=24'hbe9c00;
   7'd4:tterm=24'hd82020;   // DANGER k0
   7'd5:tterm=24'h360808;
   7'd6:tterm=24'h6c1010;
   7'd7:tterm=24'ha21818;
   7'd8:tterm=24'h20c848;   // ROUTE k0
   7'd9:tterm=24'h083212;
   7'd10:tterm=24'h106424;
   7'd11:tterm=24'h189636;
   7'd12:tterm=24'haaffbe;   // DASH k0
   7'd13:tterm=24'h2a3f2f;
   7'd14:tterm=24'h557f5f;
   7'd15:tterm=24'h7fbe8e;
   7'd16:tterm=24'hffffff;   // ROUTE_TIP k0
   7'd17:tterm=24'h3f3f3f;
   7'd18:tterm=24'h7f7f7f;
   7'd19:tterm=24'hbebebe;
   7'd20:tterm=24'h40ff40;   // ROUTE_TIP_OFF k0
   7'd21:tterm=24'h103f10;
   7'd22:tterm=24'h207f20;
   7'd23:tterm=24'h30be30;
   7'd24:tterm=24'h00ff00;   // REFUGE k0
   7'd25:tterm=24'h003f00;
   7'd26:tterm=24'h007f00;
   7'd27:tterm=24'h00be00;
   7'd28:tterm=24'h8c6a3c;   // MUD k0
   7'd29:tterm=24'h231a0f;
   7'd30:tterm=24'h46351e;
   7'd31:tterm=24'h694f2d;
   7'd32:tterm=24'hc4a874;   // RIPPLE k0
   7'd33:tterm=24'h312a1d;
   7'd34:tterm=24'h62543a;
   7'd35:tterm=24'h937e57;
   7'd36:tterm=24'hf0e8d6;   // FOAM k0
   7'd37:tterm=24'h3c3a35;
   7'd38:tterm=24'h78746b;
   7'd39:tterm=24'hb4aea0;
   7'd40:tterm=24'h181008;   // CRACK k0
   7'd41:tterm=24'h060402;
   7'd42:tterm=24'h0c0804;
   7'd43:tterm=24'h120c06;
   7'd44:tterm=24'h3a2c1e;   // SLIDE_DARK k0
   7'd45:tterm=24'h0e0b07;
   7'd46:tterm=24'h1d160f;
   7'd47:tterm=24'h2b2116;
   7'd48:tterm=24'h9a7850;   // SOIL k0
   7'd49:tterm=24'h261e14;
   7'd50:tterm=24'h4d3c28;
   7'd51:tterm=24'h735a3c;
   7'd52:tterm=24'h504c48;   // ROCK k0
   7'd53:tterm=24'h141312;
   7'd54:tterm=24'h282624;
   7'd55:tterm=24'h3c3936;
   7'd56:tterm=24'hb0a088;   // DUST k0
   7'd57:tterm=24'h2c2822;
   7'd58:tterm=24'h585044;
   7'd59:tterm=24'h847866;
   7'd60:tterm=24'h7a5e40;   // DEPOSIT k0
   7'd61:tterm=24'h1e1710;
   7'd62:tterm=24'h3d2f20;
   7'd63:tterm=24'h5b4630;
   7'd64:tterm=24'h625e58;   // STONE k0
   7'd65:tterm=24'h181716;
   7'd66:tterm=24'h312f2c;
   7'd67:tterm=24'h494642;
   7'd68:tterm=24'hb89c78;   // DEPOSIT_EDGE k0
   7'd69:tterm=24'h2e271e;
   7'd70:tterm=24'h5c4e3c;
   7'd71:tterm=24'h8a755a;
   7'd72:tterm=24'h4e3a26;   // SLURRY k0
   7'd73:tterm=24'h130e09;
   7'd74:tterm=24'h271d13;
   7'd75:tterm=24'h3a2b1c;
   7'd76:tterm=24'h7e6242;   // SURGE k0
   7'd77:tterm=24'h1f1810;
   7'd78:tterm=24'h3f3121;
   7'd79:tterm=24'h5e4931;
   7'd80:tterm=24'h34281c;   // HEAD k0
   7'd81:tterm=24'h0d0a07;
   7'd82:tterm=24'h1a140e;
   7'd83:tterm=24'h271e15;
   7'd84:tterm=24'h585450;   // BOULDER k0
   7'd85:tterm=24'h161514;
   7'd86:tterm=24'h2c2a28;
   7'd87:tterm=24'h423f3c;
   7'd88:tterm=24'h5a442e;   // WET_MUD k0
   7'd89:tterm=24'h16110b;
   7'd90:tterm=24'h2d2217;
   7'd91:tterm=24'h433322;
   7'd92:tterm=24'he83020;   // FAULT_GLOW k0
   7'd93:tterm=24'h3a0c08;
   7'd94:tterm=24'h741810;
   7'd95:tterm=24'hae2418;
   7'd96:tterm=24'hfafafa;   // RING_WHITE k0
   7'd97:tterm=24'h3e3e3e;
   7'd98:tterm=24'h7d7d7d;
   7'd99:tterm=24'hbbbbbb;
   7'd100:tterm=24'h181818;   // RING_DARK k0
   7'd101:tterm=24'h060606;
   7'd102:tterm=24'h0c0c0c;
   7'd103:tterm=24'h121212;
   7'd104:tterm=24'hffe040;   // QUAKE_NEW k0
   7'd105:tterm=24'h3f3810;
   7'd106:tterm=24'h7f7020;
   7'd107:tterm=24'hbea830;
   7'd108:tterm=24'h404244;   // TILE k0
   7'd109:tterm=24'h101011;
   7'd110:tterm=24'h202122;
   7'd111:tterm=24'h303133;
   7'd112:tterm=24'ha49680;   // WALL k0
   7'd113:tterm=24'h292520;
   7'd114:tterm=24'h524b40;
   7'd115:tterm=24'h7b7060;
   7'd116:tterm=24'h1e1a16;   // GAP k0
   7'd117:tterm=24'h070605;
   7'd118:tterm=24'h0f0d0b;
   7'd119:tterm=24'h161310;
   7'd120:tterm=24'h8e8a84;   // ROCK_LIGHT k0
   7'd121:tterm=24'h232221;
   7'd122:tterm=24'h474542;
   7'd123:tterm=24'h6a6763;
   default:tterm=24'd0;
  endcase
 endfunction
 // Split form of blend: blend(a,c,k) = aterm(a,k) + cterm(c,k), exactly
 // (each channel adds two 8-bit terms whose sum stays below 256). The
 // selection stage folds cterm of its constant colour; C4/C5 add.
 function [23:0] cterm(input [23:0] c,input [1:0] k);
  integer i;reg [7:0] q;
  begin
   for(i=0;i<3;i=i+1)begin
    q=c[i*8+:8];
    case(k) 2'd1:cterm[i*8+:8]=q>>2; 2'd2:cterm[i*8+:8]=q>>1; default:cterm[i*8+:8]=(q>>1)+(q>>2); endcase
   end
  end
 endfunction
 function [23:0] aterm(input [23:0] a,input [1:0] k);
  integer i;reg [7:0] p;
  begin
   for(i=0;i<3;i=i+1)begin
    p=a[i*8+:8];
    case(k) 2'd1:aterm[i*8+:8]=(p>>1)+(p>>2); 2'd2:aterm[i*8+:8]=p>>1; 2'd3:aterm[i*8+:8]=p>>2; default:aterm[i*8+:8]=8'd0; endcase
   end
  end
 endfunction
 function [23:0] add3(input [23:0] a,input [23:0] b);
  integer i;begin for(i=0;i<3;i=i+1)add3[i*8+:8]=a[i*8+:8]+b[i*8+:8];end
 endfunction

 // Active pixel position of rgb_in.
 reg [9:0] x;reg [8:0] y;reg de_q;
 always @(posedge clk or posedge rst)begin
  if(rst)begin x<=0;y<=0;de_q<=0;end
  else begin
   de_q<=de;x<=de ? x+1'b1 : 10'd0;
   if(frame_start)y<=0;else if(de_q && !de)y<=y+1'b1;
  end
 end

 // ---------------------------------------------------------------- frame terms
 wire active_kind=enable && !thumbnail && hazard>=LS && hazard<=EQ && role>=CAUSE && role<=EVAC;
 wire [5:0] t6=t_now[7:2];
 wire fast=role==EVAC || role==AFTER ? frame_cnt[2] : role==ONSET ? frame_cnt[3] : frame_cnt[4];
 wire slow=frame_cnt[5];
 // Rain level: cause 2, onset/aftermath 1; none for evacuation and earthquake.
 wire [7:0] density=(hazard==EQ || role==EVAC) ? 8'd0 : role==CAUSE ? 8'd32+t6 : 8'd28;
 // Earthquake close-up shake: amplitude 4..0 decaying from t=40, phase by fc.
 wire [7:0] shake_t=t_now-8'd40;
 wire [2:0] shake_amp=(t_now<8'd40 || shake_t[7:5]>=3'd4) ? 3'd0 : 3'd4-shake_t[7:5];
 wire shake_on=active_kind && hazard==EQ && role==ONSET;

 // ---------------------------------------------------------------- C1
 wire layer=t_in!=8'hff;
 wire [1:0] region=t_in[7:6];
 wire [5:0] time_=t_in[5:0];
 wire covered=layer && time_<=t6;
 wire [5:0] age=t6-time_;
 wire [9:0] xy=x+y;
 wire zone_stripe=(((xy>>2)-(frame_cnt>>3))&10'd3)<10'd2;
 wire hatch=((xy+(frame_cnt>>2))&10'd31)<10'd3;
 wire [7:0] tq={time_,2'b00};
 wire dash=((tq-frame_cnt[8:1])&8'd7)<8'd3;
 wire surge=((tq-frame_cnt[8:1])&8'd31)<8'd4;
 wire [5:0] p=frame_cnt[6:1];
 wire lead=(time_-p)==6'd0 || (time_-p-6'd32)==6'd0;
 wire puff=(p-time_)==6'd1 || (p+6'd32-time_)==6'd1;
 wire sunk={1'b0,t_now}+9'd16>=9'd64+y[8:2];
 wire signed [7:0] wk=$signed({2'b00,t6})-8'sd24-$signed({2'b00,time_});
 wire wave_front=wk>=0 && wk<24 && (wk==0 || wk==6 || wk==12 || wk==18);
 // Hashes: A = (x,y), B = (x/2,y/2), C = dust grain or flood fleck.
 wire [7:0] ha=hash8(x[7:0],y[7:0]);
 wire [7:0] hb=hash8(x[8:1],y[8:1]);
 wire [11:0] xf={2'b00,x}-{2'b00,frame_cnt};
 wire [9:0] yf={1'b0,y}-{1'b0,frame_cnt[9:1]};
 wire [8:0] yg={1'b0,y}+frame_cnt[9:1];
 wire [7:0] hc=hazard==FL ? hash8(xf[8:1],yf[8:1]) : hash8(x[7:0],yg[7:0]);
 // Value-noise parameters for the pixel's region (one set per pixel).
 reg [11:0] nu;reg [9:0] nv;reg [2:0] nsx,nsy;reg [7:0] nsalt;
 wire [11:0] x12={2'b00,x};
 always @* begin
  nu=x12;nv={1'b0,y};nsx=3'd2;nsy=3'd2;nsalt=8'd71;
  if(hazard==FL && role==ONSET)begin
   case(region)
    2'd1:begin nu=x12-{frame_cnt,2'b00}-{1'b0,frame_cnt,1'b0};nsx=3'd5;nsy=3'd2;nsalt=8'd3;end   // x-6fc
    2'd2:begin nv={1'b0,y}-{frame_cnt[8:0],1'b0}-frame_cnt;nsx=3'd3;nsy=3'd1;nsalt=8'd9;end    // y-3fc
    default:if(age==6'd0)begin nv={1'b0,y}+frame_cnt;nsx=3'd2;nsy=3'd2;nsalt=8'd23;end
            else begin nu=x12-{1'b0,frame_cnt,1'b0}-{2'b00,frame_cnt};nsx=3'd5;nsy=3'd2;nsalt=8'd17;end
   endcase
  end else if(hazard==EQ && role==AFTER && region==2'd0)begin nsx=3'd4;nsy=3'd4;nsalt=8'd61;end
 end
 wire [15:0] nu4={nu,4'b0000}>>nsx;
 wire [13:0] nv4={nv,4'b0000}>>nsy;
 wire [7:0] ncx=nu>>nsx;
 wire [7:0] ncy=(nv>>nsy)+nsalt;
 // Rain cells: near (16x64, length 14, 4/16 px per frame), far (8x32, 6, 2/8).
 wire [11:0] ru0=x12+{frame_cnt,2'b00};
 wire [13:0] rv0={5'd0,y}-{frame_cnt,4'b0000};
 wire [11:0] ru1=x12+{1'b0,frame_cnt,1'b0};
 wire [13:0] rv1={5'd0,y}-{1'b0,frame_cnt,3'b000};
 wire [7:0] rk0=ru0[11:4]*8'd167+rv0[13:6]*8'd89;
 wire [7:0] rk1=ru1[10:3]*8'd167+rv1[12:5]*8'd89+8'd53;

 reg [23:0] rgb1;reg [5:0] time1,age1;reg [1:0] reg1;
 reg v1,layer1,cov1,zone1,hatch1,dash1,surge1,lead1,puff1,sunk1,wave1;
 reg [7:0] ha1,hb1,hc1,h00,h10,h01,h11,rk0_1,rk1_1;reg [3:0] fx1,fy1;
 reg [3:0] rlu0,rlu1;reg [5:0] rlv0;reg [4:0] rlv1;
 always @(posedge clk)begin
  v1<=de && active_kind;rgb1<=rgb_in;time1<=time_;age1<=age;reg1<=region;
  layer1<=layer;cov1<=covered;zone1<=zone_stripe;hatch1<=hatch;dash1<=dash;surge1<=surge;
  lead1<=lead;puff1<=puff;sunk1<=sunk;wave1<=wave_front;
  ha1<=ha;hb1<=hb;hc1<=hc;fx1<=nu4[3:0];fy1<=nv4[3:0];
  h00<=hash8(ncx,ncy);h10<=hash8(ncx+8'd1,ncy);h01<=hash8(ncx,ncy+8'd1);h11<=hash8(ncx+8'd1,ncy+8'd1);
  rk0_1<=rk0;rk1_1<=rk1;rlu0<=ru0[3:0];rlu1<={1'b0,ru1[2:0]};rlv0<=rv0[5:0];rlv1<=rv1[4:0];
 end

 // ---------------------------------------------------------------- C2
 wire signed [12:0] da=$signed({1'b0,h10})-$signed({1'b0,h00});
 wire signed [12:0] db=$signed({1'b0,h11})-$signed({1'b0,h01});
 wire signed [12:0] pa=da*$signed({1'b0,fx1});
 wire signed [12:0] pb=db*$signed({1'b0,fx1});
 wire [7:0] na=h00+pa[11:4];
 wire [7:0] nb=h01+pb[11:4];
 // Rain drop: hash below density, inside the streak, on its slanted column.
 wire [7:0] rh0=rk0_1^(rk0_1>>3),rh1=rk1_1^(rk1_1>>3);
 wire [2:0] rox0=rk0_1[6:4];wire [1:0] rox1=rk1_1[5:4];
 wire [7:0] roy0b=rk0_1^(rk0_1>>5),roy1b=rk1_1^(rk1_1>>5);
 wire [4:0] roy0=roy0b[4:0];wire [3:0] roy1=roy1b[3:0];
 wire [6:0] rd0={1'b0,rlv0}-{2'b00,roy0};
 wire [5:0] rd1={1'b0,rlv1}-{2'b00,roy1};
 wire rain0=rh0<density && !rd0[6] && rd0<7'd14 && {1'b0,rlu0}+rd0[5:2]=={2'b00,rox0}+5'd3;
 wire rain1=rh1<density && !rd1[5] && rd1<6'd6 && {1'b0,rlu1}+rd1[4:2]=={3'b000,rox1}+5'd1;

 reg [23:0] rgb2;reg [5:0] time2,age2;reg [1:0] reg2;
 reg v2,layer2,cov2,zone2,hatch2,dash2,surge2,lead2,puff2,sunk2,wave2,rain0_2,rain1_2;
 reg [7:0] ha2,hb2,hc2,na2,nb2;reg [3:0] fy2;
 always @(posedge clk)begin
  v2<=v1;rgb2<=rgb1;time2<=time1;age2<=age1;reg2<=reg1;layer2<=layer1;cov2<=cov1;
  zone2<=zone1;hatch2<=hatch1;dash2<=dash1;surge2<=surge1;lead2<=lead1;puff2<=puff1;sunk2<=sunk1;wave2<=wave1;
  ha2<=ha1;hb2<=hb1;hc2<=hc1;na2<=na;nb2<=nb;fy2<=fy1;rain0_2<=rain0;rain1_2<=rain1;
 end

 // ---------------------------------------------------------------- C3
 wire signed [12:0] dn=$signed({1'b0,nb2})-$signed({1'b0,na2});
 wire signed [12:0] pn=dn*$signed({1'b0,fy2});
 wire [7:0] n=na2+pn[11:4];
 wire special=time2>=6'd60;
 wire [1:0] level=time2[1:0];
 // Dust (landslide from t=140, earthquake from t=64): levels open 16 steps
 // apart, densest first; the grain thickens for 64 steps.
 wire [7:0] dust_from=hazard==EQ ? 8'd64 : 8'd140;
 wire [8:0] dust_open={1'b0,dust_from}+{3'd0,~level,4'b0000};
 wire dust_shown=special && {1'b0,t_now}>=dust_open;
 wire [7:0] dust_t=t_now-dust_from;
 wire [4:0] grow=t_now<dust_from ? 5'd0 : dust_t[7:2]>=6'd16 ? 5'd16 : dust_t[6:2];
 wire [7:0] grain_thr=8'd4+{2'b00,level,4'b0000}+grow;
 wire grain=hc2<grain_thr;
 reg [1:0] eop,bop;reg aon;reg [4:0] ec,ac,bc;reg [1:0] ek,ak,bk;
 always @* begin
  eop=NONE;ec=5'd0;ek=2'd1;aon=1'b0;ac=5'd0;ak=2'd1;bop=NONE;bc=5'd0;bk=2'd1;
  if(role==CAUSE && hazard==EQ)begin
   case(reg2)
    2'd0:if(layer2)begin
          if(t_now>=8'd96)begin eop=BLEND;ec=FAULT_GLOW;ek=fast ? 2'd3 : 2'd2;end
          else if(t_now>=8'd16)begin eop=BLEND;ec=FAULT_GLOW;ek=slow ? 2'd2 : 2'd1;end
         end
    2'd1:if(cov2)begin
          if(age2<6'd2)begin eop=CONST;ec=QUAKE_NEW;end else begin eop=BLEND;ec=RING_WHITE;ek=2'd3;end
         end
    2'd2:if(cov2)begin eop=BLEND;ec=RING_DARK;ek=2'd2;end
    default:if(layer2 && wave2)begin eop=BLEND;ec=RING_WHITE;ek=2'd1;end
   endcase
  end else if(role==CAUSE)begin
   if(layer2 && reg2==2'd0 && zone2 && slow)begin eop=BLEND;ec=ZONE;ek=2'd3;end
  end else if(role==EVAC)begin
   case(reg2)
    2'd0:if(cov2)begin
          if(age2<6'd2)begin eop=CONST;ec=fast ? ROUTE_TIP : ROUTE_TIP_OFF;end
          else if(dash2)begin eop=CONST;ec=DASH;end
          else begin eop=BLEND;ec=ROUTE;ek=2'd3;end
         end
    2'd1:if(layer2 && hatch2)begin eop=BLEND;ec=DANGER;ek=2'd3;end
    2'd2:if(layer2 && slow)begin eop=CONST;ec=REFUGE;end
    default:;
   endcase
  end else if(hazard==LS && role==ONSET)begin
   case(reg2)
    2'd0:if(cov2)begin eop=BLEND;ec=CRACK;ek=age2<6'd2 ? 2'd2 : 2'd3;end
    2'd1:begin
          if(cov2)begin eop=BLEND;ec=SOIL;ek=age2<6'd12 ? 2'd1 : 2'd2;end
          if(layer2 && dust_shown)begin
           if(level==2'd3)begin aon=1'b1;ac=DUST;ak=2'd1;end
           if(grain)begin bop=BLEND;bc=DUST;bk=2'd2;end
          end
         end
    2'd2:if(cov2)begin eop=BLEND;ec=SLIDE_DARK;ek=age2<6'd4 ? 2'd1 : 2'd2;end
    default:if(layer2)begin
          if(sunk2)begin eop=BLEND;ec=SLIDE_DARK;ek=2'd2;end
          if(t_now>=8'd80)begin
           if(lead2)begin bop=CONST;bc=ROCK;end
           else if(puff2)begin aon=1'b1;ac=DUST;ak=2'd1;end
          end
         end
   endcase
  end else if(hazard==LS && role==AFTER)begin
   if(layer2 && reg2==2'd1)begin eop=BLEND;ek=2'd2;ec=ha2<8'd28 ? STONE : SOIL;end
   if(cov2 && reg2==2'd0)begin
    eop=BLEND;
    if(age2<6'd2)begin ec=DEPOSIT_EDGE;ek=2'd2;end
    else begin ek=2'd3;ec=ha2<8'd28 ? STONE : ha2<8'd52 ? DEPOSIT_EDGE : DEPOSIT;end
   end
  end else if(hazard==EQ && role==ONSET)begin
   case(reg2)
    2'd0:if(cov2)begin eop=BLEND;ec=CRACK;ek=age2<6'd2 ? 2'd2 : 2'd3;end
    2'd1:if(layer2 && dust_shown)begin
          if(level[1])begin aon=1'b1;ac=WALL;ak=level[0] ? 2'd2 : 2'd1;end
          if(grain)begin bop=BLEND;bc=DUST;bk=2'd2;end
         end
    2'd2:if(cov2)begin eop=BLEND;ek=2'd2;ec=ha2<8'd24 ? STONE : n<8'd70 ? GAP : n<8'd150 ? TILE : WALL;end
    default:if(layer2 && t_now>=8'd56)begin
          if(lead2)begin bop=CONST;bc=ROCK;end
          else if(puff2)begin aon=1'b1;ac=DUST;ak=2'd1;end
         end
   endcase
  end else if(hazard==EQ && role==AFTER)begin
   case(reg2)
    2'd0:if(cov2)begin
          eop=BLEND;
          if(age2<6'd2)begin ec=WALL;ek=2'd2;end
          else if(ha2<8'd18)begin ec=GAP;ek=2'd1;end
          else begin ec=n>=8'd128 ? ROCK_LIGHT : STONE;ek=2'd2;end
         end
    2'd1:if(cov2)begin eop=BLEND;ec=CRACK;ek=2'd3;end
    2'd2:if(layer2)begin eop=BLEND;ek=2'd2;ec=ha2<8'd24 ? STONE : n<8'd70 ? GAP : n<8'd150 ? TILE : WALL;end
    default:;
   endcase
  end else if(hazard==DF && role==ONSET)begin
   if(cov2 && reg2==2'd0)begin
    eop=BLEND;
    if(age2<6'd3)begin ec=HEAD;ek=2'd3;end else begin ec=surge2 ? SURGE : SLURRY;ek=2'd2;end
   end
   if(cov2 && reg2==2'd1)begin eop=BLEND;ec=WET_MUD;ek=age2<6'd4 ? 2'd2 : 2'd1;end
  end else if(hazard==DF && role==AFTER)begin
   if(layer2 && reg2==2'd1)begin eop=BLEND;ec=SLURRY;ek=2'd2;end
   if(cov2 && reg2==2'd0)begin
    eop=BLEND;ek=2'd3;
    if(hb2<8'd8)ec=BOULDER;
    else if(ha2<8'd18)ec=STONE;
    else if(age2<6'd10)ec=WET_MUD;
    else begin ec=DEPOSIT;ek=time2[2] ? 2'd3 : 2'd2;end
   end
  end else if(hazard==FL && role==ONSET)begin
   if(cov2)begin
    eop=BLEND;
    case(reg2)
     2'd1:if(age2==6'd0)begin ec=n>=8'd120 ? FOAM : MUD;ek=2'd2;end
          else if(n>=8'd185)begin ec=FOAM;ek=2'd2;end
          else begin ec=n>=8'd150 ? RIPPLE : MUD;ek=2'd1;end
     2'd2:begin ec=n>=8'd165 ? FOAM : MUD;ek=2'd2;end
     2'd0:if(age2==6'd0)begin ec=FOAM;ek=(n>=8'd110 && fast) ? 2'd2 : 2'd1;end
          else if(n>=8'd190)begin ec=RIPPLE;ek=2'd1;end
          else begin ec=MUD;ek=age2<6'd4 ? 2'd1 : 2'd2;end
     default:eop=NONE;
    endcase
   end
  end else if(hazard==FL && role==AFTER)begin
   if(layer2 && reg2==2'd0)begin
    eop=BLEND;
    if(hc2<8'd10)begin ec=RIPPLE;ek=2'd2;end else begin ec=MUD;ek=time2<6'd12 ? 2'd2 : 2'd1;end
   end
  end
  if(!v2)begin eop=NONE;aon=1'b0;bop=NONE;end
 end
 wire [23:0] near=rain0_2 && v2 ? blend(rgb2,RAIN_NEAR,2'd2) : rgb2;

 // Colour terms are folded here: CONST becomes operand 0 + colour.
 reg [23:0] rgb3,near3,et3,at3,bt3;reg [1:0] eop3,ek3,ak3,bop3,bk3;reg aon3,rain1_3;
 always @(posedge clk)begin
  rgb3<=rgb2;near3<=near;rain1_3<=rain1_2 && v2;
  eop3<=eop;ek3<=eop==CONST ? 2'd0 : ek;et3<=tterm(ec,eop==CONST ? 2'd0 : ek);
  aon3<=aon;ak3<=ak;at3<=tterm(ac,ak);
  bop3<=bop;bk3<=bop==CONST ? 2'd0 : bk;bt3<=tterm(bc,bop==CONST ? 2'd0 : bk);
 end

 // ---------------------------------------------------------------- C4
 wire [23:0] rained=rain1_3 ? blend(near3,RAIN_FAR,2'd1) : near3;
 wire [23:0] base=eop3!=NONE ? add3(aterm(rgb3,ek3),et3) : rained;
 reg [23:0] base4,at4,bt4;reg [1:0] ak4,bop4,bk4;reg aon4;
 always @(posedge clk)begin
  base4<=base;aon4<=aon3;at4<=at3;ak4<=ak3;bop4<=bop3;bt4<=bt3;bk4<=bk3;
 end

 // ---------------------------------------------------------------- C5
 wire [23:0] over_a=aon4 ? add3(aterm(base4,ak4),at4) : base4;
 wire [23:0] over_b=bop4!=NONE ? add3(aterm(over_a,bk4),bt4) : over_a;

 // de travels beside the pixel (de_d[3] marks over_b) for the shake.
 reg [3:0] de_d;
 always @(posedge clk or posedge rst)begin
  if(rst)de_d<=0;else de_d<={de_d[2:0],de};
 end

 // ---------------------------------------------------------------- shake
 // sr[0] holds the newest pixel, sr[k] the one k clocks older; the output is
 // sr[4] shifted by s: in[x-s] = sr[4+s], s in -4..4. Taps outside the line
 // take its first (s>0) or last (s<0) pixel.
 reg [23:0] sr[0:8];reg [8:0] sv;reg [23:0] first_px,last_px;
 integer k;
 always @(posedge clk or posedge rst)begin
  if(rst)begin sv<=0;first_px<=0;last_px<=0;end
  else begin
   sv<={sv[7:0],de_d[3]};
   if(de_d[3] && !sv[0])first_px<=over_b;
   if(de_d[3])last_px<=over_b;
  end
 end
 always @(posedge clk or posedge rst)begin
  if(rst)for(k=0;k<9;k=k+1)sr[k]<=24'd0;
  else begin sr[0]<=over_b;for(k=1;k<9;k=k+1)sr[k]<=sr[k-1];end
 end
 // Frame terms are stable while the line is in flight.
 wire signed [3:0] s=!shake_on ? 4'sd0 :
  frame_cnt[1:0]==2'd1 ? $signed({1'b0,shake_amp}) : frame_cnt[1:0]==2'd3 ? -$signed({1'b0,shake_amp}) : 4'sd0;
 wire [3:0] tap=4'd4+s;
 wire [23:0] tap_px=sr[tap];
 wire tap_ok=sv[tap];
 always @(posedge clk or posedge rst)begin
  if(rst)rgb_out<=0;
  else rgb_out<=!sv[4] || tap_ok ? (sv[4] ? tap_px : sr[4]) : s>0 ? first_px : last_px;
 end
endmodule
