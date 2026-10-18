`timescale 1ns/1ps
// mode_key_control scene entry (clock 1 kHz: 1 cycle = 1 ms). Mode 0 KEY4:
// release before 1 s toggles AUTO at the release, a 1 s hold toggles scene
// mode once with no AUTO toggle. Scene mode survives mode changes, blocks
// KEY1 in mode 0 only, and keeps KEY2 next and long rescan. Mode 3 keeps the
// KEY4 press toggle; modes 1-3 and mode changes during a hold never toggle
// scene mode; nothing happens while disabled.
module tb_m4_keys;
 reg clk=0,rst=1,enable=1,key1=1,key2=1,key4=1;reg [1:0] mode=0;
 wire next_event,previous_event,auto_toggle_event,manual_activity,rescan_event,scene_mode;
 mode_key_control #(.CLK_FREQ_HZ(1000),.PREVIEW_ENABLE(1)) dut(.adjust_decrease(),.adjust_increase(),.adjust_restore(),.adjust_select(),.*);
 always #5 clk=~clk;
 integer nexts=0,prevs=0,toggles=0,rescans=0,scene_changes=0,last_toggle=0,cycle=0;
 reg scene_q=0;
 always @(posedge clk)if(!rst)begin
  cycle++;
  if(next_event)nexts++;if(previous_event)prevs++;
  if(auto_toggle_event)begin toggles++;last_toggle=cycle;end
  if(rescan_event)rescans++;
  if(scene_mode!=scene_q)scene_changes++;scene_q<=scene_mode;
 end
 task settle;begin repeat(35)@(negedge clk);end endtask
 task automatic press(ref reg k,input integer ms);begin k=0;repeat(ms)@(negedge clk);k=1;settle();end endtask
 task want(input integer n,p,t,r,s,input bit scene,input string what);
  begin
   if(nexts!=n || prevs!=p || toggles!=t || rescans!=r || scene_changes!=s || scene_mode!==scene)
    $fatal(1,"%s: next=%0d prev=%0d toggle=%0d rescan=%0d scene_changes=%0d scene=%b",what,nexts,prevs,toggles,rescans,scene_changes,scene_mode);
  end
 endtask
 integer t_release;
 initial begin
  repeat(3)@(negedge clk);rst=0;settle();
  // Picture mode short KEY4: AUTO on release, not on press.
  key4=0;repeat(400)@(negedge clk);
  want(0,0,0,0,0,0,"no AUTO toggle while KEY4 held");
  key4=1;t_release=cycle;settle();
  want(0,0,1,0,0,0,"short KEY4 toggles AUTO");
  if(last_toggle<t_release)$fatal(1,"AUTO toggled before release");
  press(key1,40);press(key2,40);want(1,1,1,0,0,0,"picture mode KEY1/KEY2");
  // Long KEY4 enters scene mode during the hold; the release adds nothing.
  key4=0;repeat(1100)@(negedge clk);want(1,1,1,0,1,1,"scene entered during hold");
  repeat(2000)@(negedge clk);key4=1;settle();want(1,1,1,0,1,1,"long KEY4 toggles once, no AUTO");
  // Scene mode: KEY1 reserved, KEY2 next, long KEY2 rescan, short KEY4 AUTO.
  press(key1,40);want(1,1,1,0,1,1,"KEY1 ignored in scene mode");
  press(key2,40);want(2,1,1,0,1,1,"KEY2 next in scene mode");
  press(key2,2100);want(2,1,1,1,1,1,"long KEY2 rescan in scene mode");
  press(key4,300);want(2,1,2,1,1,1,"short KEY4 AUTO in scene mode");
  // Other modes: scene mode stays; KEY4 never toggles it there.
  mode=1;settle();press(key4,1500);want(2,1,2,1,1,1,"mode 1 long KEY4");
  mode=3;settle();press(key4,1500);want(2,1,3,1,1,1,"mode 3 KEY4 press toggle only");
  press(key1,40);want(2,2,3,1,1,1,"mode 3 KEY1 still moves preview focus");
  mode=0;settle();
  // A hold that crosses a mode change does nothing.
  key4=0;repeat(500)@(negedge clk);mode=2;repeat(1000)@(negedge clk);key4=1;settle();mode=0;settle();
  want(2,2,3,1,1,1,"KEY4 hold across mode change");
  key4=0;repeat(500)@(negedge clk);mode=1;settle();mode=0;repeat(1000)@(negedge clk);key4=1;settle();
  want(2,2,3,1,1,1,"KEY4 hold across mode change and back");
  // Disabled (scan busy): no events.
  enable=0;press(key4,1500);press(key4,100);press(key2,40);enable=1;settle();
  want(2,2,3,1,1,1,"disabled");
  // Leave scene mode; KEY1 is previous again.
  press(key4,1200);want(2,2,3,1,2,0,"long KEY4 leaves scene mode");
  press(key1,40);want(2,3,3,1,2,0,"KEY1 previous after exit");
  $display("PASS M4 keys: AUTO on short KEY4 release, scene toggle on 1 s hold, KEY1 reserved in scene mode, modes 1-3 and mode changes unaffected");
  $finish;
 end
endmodule
