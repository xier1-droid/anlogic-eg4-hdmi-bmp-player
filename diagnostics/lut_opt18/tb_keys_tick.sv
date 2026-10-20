`timescale 1ns/1ps
// v0.18 S1 batch 4: mode_key_control with the shared 1 ms prescaler against
// the frozen v0.17.0 module (per-counter clock timing) at CLK_FREQ_HZ=20000
// (20 clocks per ms). Random gestures: taps, window-length presses, KEY4 scene
// holds, KEY2 rescan holds, KEY1+KEY2 restore, contact bounce, mode changes
// and enable drops. Durations keep >=10 ms from the 20/100/1000/2000 ms
// thresholds, so only the 1 ms tick phase may differ: every output pulse and
// level change must occur in both, in the same order, within one tick
// (+2 clocks) of the reference (the first tick of a duration is partial).
module tb_keys_tick;
 parameter integer SEED=18;
 parameter integer GESTURES=300;
 localparam integer F=20000,MS=F/1000;
 reg clk=0,rst=1;
 always #5 clk=~clk;
 reg key1=1,key2=1,key4=1,enable=1;reg [1:0] mode=0;
 wire [12:0] o_ref,o_dut;
 mode_key_control_v017 #(.CLK_FREQ_HZ(F),.PREVIEW_ENABLE(1)) ref_(.clk(clk),.rst(rst),.enable(enable),.key1(key1),.key2(key2),.key4(key4),.mode(mode),
  .next_event(o_ref[0]),.rescan_event(o_ref[1]),.previous_event(o_ref[2]),.auto_toggle_event(o_ref[3]),.scene_mode(o_ref[4]),.warn_mode(o_ref[5]),
  .adjust_decrease(o_ref[6]),.adjust_increase(o_ref[7]),.adjust_restore(o_ref[8]),.adjust_select(o_ref[9]),.manual_activity(o_ref[10]));
 mode_key_control #(.CLK_FREQ_HZ(F),.PREVIEW_ENABLE(1)) dut(.clk(clk),.rst(rst),.enable(enable),.key1(key1),.key2(key2),.key4(key4),.mode(mode),
  .next_event(o_dut[0]),.rescan_event(o_dut[1]),.previous_event(o_dut[2]),.auto_toggle_event(o_dut[3]),.scene_mode(o_dut[4]),.warn_mode(o_dut[5]),
  .adjust_decrease(o_dut[6]),.adjust_increase(o_dut[7]),.adjust_restore(o_dut[8]),.adjust_select(o_dut[9]),.manual_activity(o_dut[10]));
 assign o_ref[12:11]=0;assign o_dut[12:11]=0;
 // Change log per output bit: times of every edge.
 longint unsigned cyc=0;
 longint unsigned tr[0:10][$],td[0:10][$];
 reg [10:0] pr=0,pd=0;
 integer counts[0:10];
 always @(posedge clk)if(!rst)begin
  cyc<=cyc+1;
  for(int i=0;i<11;i++)begin
   if(o_ref[i]!==pr[i])tr[i].push_back(cyc);
   if(o_dut[i]!==pd[i])td[i].push_back(cyc);
  end
  pr<=o_ref[10:0];pd<=o_dut[10:0];
  if(^o_dut[10:0]===1'bx)$fatal(1,"X on outputs at %0d",cyc);
 end
 // Keep each output's edges matched as they arrive: the new edge must follow
 // the reference within one tick either way.
 always @(negedge clk)if(!rst)for(int i=0;i<11;i++)begin
  while(tr[i].size()>0 && td[i].size()>0)begin
   automatic longint unsigned a=tr[i].pop_front(),b=td[i].pop_front();
   if(b+MS+2<a || b>a+MS+2)$fatal(1,"output %0d edge at %0d, reference %0d",i,b,a);
   counts[i]++;
  end
  if(tr[i].size()>0 && cyc>tr[i][0]+MS+2)$fatal(1,"output %0d: reference edge at %0d missing",i,tr[i][0]);
  if(td[i].size()>0 && cyc>td[i][0]+MS+2)$fatal(1,"output %0d: extra edge at %0d",i,td[i][0]);
 end
 task wait_ms(input integer n);repeat(n*MS)@(posedge clk);endtask
 // Bounce: up to 5 short level flips (each <1 ms apart, total <6 ms).
 task bounce_to(inout reg k,input reg level);
  integer n;
  begin
   n=$urandom%6;
   repeat(n)begin k=~level;repeat(1+$urandom%MS)@(posedge clk);k=level;repeat(1+$urandom%MS)@(posedge clk);end
   k=level;
  end
 endtask
 function integer hold_ms();
  integer pick;
  begin
   pick=$urandom%6;
   case(pick)0:hold_ms=35;1:hold_ms=60;2:hold_ms=150;3:hold_ms=400;4:hold_ms=1200;default:hold_ms=2300;endcase
   hold_ms=hold_ms+$urandom%11;
  end
 endfunction
 integer g,kind,h,off;
 initial begin
  for(int i=0;i<11;i++)counts[i]=0;
  void'($urandom(SEED));
  repeat(MS*3+7)@(posedge clk);rst=0;
  wait_ms(30);
  for(g=0;g<GESTURES;g++)begin
   // Frame terms between gestures, with all keys released.
   if($urandom%4==0)mode=$urandom%4;
   enable=($urandom%10)!=0;
   wait_ms(30+$urandom%40);
   kind=$urandom%5;h=hold_ms();
   case(kind)
    0:begin bounce_to(key1,0);wait_ms(h);bounce_to(key1,1);end
    1:begin bounce_to(key2,0);wait_ms(h);bounce_to(key2,1);end
    2:begin bounce_to(key4,0);wait_ms(h);bounce_to(key4,1);end
    3:begin // KEY1 then KEY2 inside the 100 ms window
      off=30+$urandom%40;bounce_to(key1,0);wait_ms(off);bounce_to(key2,0);wait_ms(h);
      bounce_to(key1,1);wait_ms(30);bounce_to(key2,1);end
    default:begin // mode change while a key is held
      bounce_to(key2,0);wait_ms(h);mode=$urandom%4;wait_ms(40);bounce_to(key2,1);end
   endcase
  end
  wait_ms(200);
  for(int i=0;i<11;i++)if(tr[i].size()||td[i].size())$fatal(1,"output %0d unmatched edges",i);
  if(counts[0]==0 || counts[1]==0 || counts[3]==0 || counts[4]==0 || counts[6]==0 || counts[7]==0 || counts[8]==0 || counts[9]==0)
   $fatal(1,"coverage: next %0d rescan %0d auto %0d scene %0d dec %0d inc %0d restore %0d select %0d",
    counts[0],counts[1],counts[3],counts[4],counts[6],counts[7],counts[8],counts[9]);
  $display("PASS keys tick: %0d gestures, edges next %0d rescan %0d prev %0d auto %0d scene %0d warn %0d dec %0d inc %0d restore %0d select %0d activity %0d",
   GESTURES,counts[0],counts[1],counts[2],counts[3],counts[4],counts[5],counts[6],counts[7],counts[8],counts[9],counts[10]);
  $finish;
 end
endmodule
