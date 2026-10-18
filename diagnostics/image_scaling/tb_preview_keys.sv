`timescale 1ns/1ps
module tb_preview_keys;
 reg clk=0,rst=1,enable=1,key1=1,key2=1,key4=1;reg [1:0] mode=3;
 wire next_event,previous_event,auto_toggle_event,manual_activity,rescan_event,scene_mode;
 mode_key_control #(.CLK_FREQ_HZ(1000),.PREVIEW_ENABLE(1)) dut(.adjust_decrease(),.adjust_increase(),.adjust_restore(),.adjust_select(),.*);
 always #5 clk=~clk;
 integer nexts=0,prevs=0,toggles=0,rescans=0;
 always @(posedge clk)if(!rst)begin
  if(next_event)nexts=nexts+1;if(previous_event)prevs=prevs+1;
  if(auto_toggle_event)toggles=toggles+1;if(rescan_event)rescans=rescans+1;
 end
 task settle;begin repeat(35)@(negedge clk);end endtask
 initial begin
  repeat(3)@(negedge clk);rst=0;settle();
  key1=0;settle();key1=1;settle();
  key2=0;settle();key2=1;settle();
  key4=0;settle();key4=1;settle();
  if(nexts!=1 || prevs!=1 || toggles!=1)$fatal(1,"preview short keys");
  key2=0;repeat(2050)@(negedge clk);key2=1;settle();
  if(nexts!=1 || rescans!=1)$fatal(1,"long rescan also selected");
  key2=0;settle();mode=0;settle();key2=1;settle();
  if(nexts!=1)$fatal(1,"held key crossed mode");
  mode=1;key1=0;settle();mode=3;settle();key1=1;settle();
  if(prevs!=1)$fatal(1,"held previous crossed mode");
  $display("PASS preview keys: short, long rescan without short, held keys across modes");$finish;
 end
endmodule
