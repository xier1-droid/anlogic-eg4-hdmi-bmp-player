`timescale 1ns/1ps
// M5 keys and the speed item (clock 1 kHz: 1 cycle = 1 ms).
// mode_key_control: KEY1 in scene mode, mode 0, toggles warn_mode (no
// previous event); outside scene mode KEY1 is previous and warn stays off;
// mode 1 KEY1 never toggles it; leaving scene mode clears it.
// media_adjust_control: KEY4 selection B->V->S (mode 1) and C->V->S (mode 2)
// only in scene mode, B<->V / C<->V outside; S steps 1x/2x/4x and clamps,
// restore gives 1x; a mode change leaves S and keeps the speed.
// adjust_osd_overlay: the S item glyphs appear only with speed_visible, in
// cells 19-22, highlighted when selected.
module tb_m5_keys;
 reg clk=0,rst=1,enable=1,key1=1,key2=1,key4=1;reg [1:0] mode=0;
 wire next_event,previous_event,auto_toggle_event,manual_activity,rescan_event,scene_mode,warn_mode;
 wire adjust_decrease,adjust_increase,adjust_restore,adjust_select;
 mode_key_control #(.CLK_FREQ_HZ(1000),.PREVIEW_ENABLE(1)) keys(.clk(clk),.rst(rst),.enable(enable),.key1(key1),.key2(key2),.key4(key4),
  .mode(mode),.next_event(next_event),.rescan_event(rescan_event),.previous_event(previous_event),.auto_toggle_event(auto_toggle_event),
  .scene_mode(scene_mode),.warn_mode(warn_mode),.adjust_decrease(adjust_decrease),.adjust_increase(adjust_increase),
  .adjust_restore(adjust_restore),.adjust_select(adjust_select),.manual_activity(manual_activity));
 wire [7:0] b,c;wire [3:0] v;wire [1:0] selected,speed;
 media_adjust_control ctl(.clk(clk),.rst(rst),.mode(mode),.decrease(adjust_decrease),.increase(adjust_increase),
  .restore(adjust_restore),.select_next(adjust_select),.brightness(b),.contrast(c),.volume_level(v),.selected(selected),
  .scene_mode(scene_mode),.speed(speed));
 always #5 clk=~clk;
 integer prevs=0;
 always @(posedge clk)if(!rst && previous_event)prevs++;
 task settle;begin repeat(250)@(negedge clk);end endtask
 task automatic press(ref reg k,input integer ms);begin k=0;repeat(ms)@(negedge clk);k=1;settle();end endtask
 integer checks=0;
 task check(input bit ok,input string what);
  begin if(!ok)$fatal(1,"%s: scene=%b warn=%b prev=%0d selected=%0d speed=%0d",what,scene_mode,warn_mode,prevs,selected,speed);checks++;end
 endtask
 // OSD: count S-item glyph pixels (cells 19-22) and their colours on line 40.
 reg pix=0;always #2 pix=~pix;
 reg vs=1,de=0,visible=0;reg [9:0] x=0;reg [1:0] osd_selected=0,osd_speed=0;
 wire [23:0] rgb;wire hit;
 adjust_osd_overlay osd(.clk(pix),.rst(rst),.vs(vs),.de(de),.pixel_x(x),.rgb_in(24'h808080),.mode(2'd1),.selected(osd_selected),
  .brightness(8'd128),.contrast(8'd128),.volume_level(4'd10),.rgb_out(rgb),.active(hit),.speed(osd_speed),.speed_visible(visible));
 integer s_hits,s_yellow,other,all_hits,dimmed;
 reg [7:0] b0;

 task osd_line(input integer line);
 begin
  s_hits=0;s_yellow=0;other=0;all_hits=0;dimmed=0;
  @(negedge pix);vs=0;@(negedge pix);vs=1;
  for(integer l=0;l<=line;l++)begin
   for(integer i=0;i<700;i++)begin
    @(negedge pix);x=i;de=i<640;#1;
    if(l==line && de && rgb==24'h404040)dimmed++;
    if(l==line && hit)all_hits++;
    if(l==line && hit)begin
     if(i>=8+19*16 && i<8+23*16)begin s_hits++;if(rgb==24'hffff00)s_yellow++;end
     else if(i>=8+18*16)other++;
    end
   end
   @(negedge pix);de=0;
  end
 end endtask
 initial begin
  repeat(5)@(negedge clk);rst=0;settle();
  // Warning key.
  press(key1,50);check(prevs==1 && !warn_mode,"KEY1 outside scene mode is previous");
  press(key4,1100);check(scene_mode && !warn_mode,"scene mode entered");
  press(key1,50);check(warn_mode && prevs==1,"KEY1 toggles warning in scene mode");
  press(key1,50);check(!warn_mode && prevs==1,"KEY1 again leaves warning");
  press(key1,50);check(warn_mode,"warning again");
  mode=1;settle();press(key1,50);check(warn_mode,"mode 1 KEY1 does not toggle warning");mode=0;settle();
  press(key4,1100);check(!scene_mode && !warn_mode,"leaving scene mode clears warning");
  // Speed item outside scene mode: B -> V -> B.
  mode=1;settle();check(selected==0,"mode 1 starts on B");
  press(key4,50);check(selected==2,"B -> V");
  press(key4,50);check(selected==0,"V -> B outside scene mode");
  mode=0;settle();press(key4,1100);check(scene_mode,"scene again");
  mode=1;settle();
  press(key4,50);press(key4,50);check(selected==3,"B -> V -> S in scene mode");
  b0=b;
  press(key2,50);check(speed==1,"S up: 2x");
  press(key2,50);press(key2,50);check(speed==2,"S clamps at 4x");
  press(key1,50);check(speed==1,"S down: 2x");
  press(key1,50);press(key1,50);check(speed==0,"S clamps at 1x");
  press(key2,50);press(key2,50);check(speed==2 && b==b0 && v==10,"S does not touch B or V");
  key1=0;key2=0;repeat(50)@(negedge clk);key1=1;key2=1;settle();check(speed==0,"KEY1+KEY2 restores 1x");
  press(key2,50);check(speed==1,"2x again");
  press(key4,50);check(selected==0,"S -> B");
  mode=2;settle();check(selected==1,"mode 2 starts on C");
  press(key4,50);press(key4,50);check(selected==3,"C -> V -> S in scene mode");
  press(key4,50);check(selected==1,"S -> C");
  press(key4,50);press(key4,50);check(selected==3,"S again");
  mode=0;settle();press(key4,1100);check(!scene_mode,"scene left");
  mode=2;settle();check(selected==1 && speed==1,"S deselected on the mode change; speed kept");
  press(key4,50);press(key4,50);check(selected==1,"no S outside scene mode");
  // OSD rendering of the S item.
  // Outside scene mode the bar stays at y 32-47; in scene mode it moves to
  // y 8-23 so it never reaches the scene panel (y 28-59).
  visible=0;osd_selected=0;osd_speed=0;osd_line(40);check(s_hits==0 && other==0 && all_hits>0,"bar at y 32-47 without speed_visible, no S");
  osd_line(30);check(dimmed>0,"band on y 30 without speed_visible");
  osd_line(16);check(all_hits==0 && dimmed==0,"nothing on y 16 without speed_visible");
  visible=1;osd_line(16);check(s_hits>0 && s_yellow==0 && all_hits>s_hits,"scene mode: bar and S at y 8-23");
  osd_line(40);check(all_hits==0,"scene mode: nothing on y 40");
  osd_line(30);check(all_hits==0 && dimmed==0,"scene mode: no band on y 30");
  osd_line(16);check(dimmed>0,"scene mode: band on y 16");

  osd_selected=3;osd_speed=2;osd_line(16);check(s_hits>0 && s_yellow==s_hits,"S selected in yellow");

  $display("PASS M5 keys: %0d checks",checks);$finish;
 end
 initial begin #100000000;$fatal(1,"watchdog");end
endmodule
