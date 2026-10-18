`timescale 1ns/1ps
module tb_mode_key_control;
 reg clk=0,rst=1,enable=1,key1=1,key2=1,key4=1; reg [1:0] mode=0;
 wire next_event,previous_event,auto_toggle_event,manual_activity,rescan_event,scene_mode,warn_mode;

 mode_key_control #(.CLK_FREQ_HZ(1000)) dut(.adjust_decrease(),.adjust_increase(),.adjust_restore(),.adjust_select(),.*);
 always #5 clk=~clk;
 reg seen_next, seen_prev, seen_auto;
 always @(posedge clk) begin
   if(!rst) begin seen_next<=seen_next|next_event; seen_prev<=seen_prev|previous_event; seen_auto<=seen_auto|auto_toggle_event; end
 end
 task hold_key(input integer which,input integer cycles);
   begin @(negedge clk); if(which==1) key1=0; else if(which==2) key2=0; else key4=0;
   repeat(cycles) @(negedge clk);
   if(which==1) key1=1; else if(which==2) key2=1; else key4=1;
   repeat(25) @(negedge clk); end
 endtask
 initial begin
   repeat(3) @(negedge clk); rst=0; repeat(25) @(negedge clk);
   seen_prev=0; hold_key(1,25); if(!seen_prev) $fatal(1,"previous event missing");
   seen_prev=0; mode=1; hold_key(1,25); if(seen_prev) $fatal(1,"mode 1 generated previous");
   seen_next=0; mode=2; hold_key(2,25); if(seen_next) $fatal(1,"mode 2 generated next");
   seen_auto=0; mode=3; hold_key(4,25); if(!seen_auto) $fatal(1,"KEY4 toggle missing");
   seen_next=0; mode=0; hold_key(2,25); if(!seen_next) $fatal(1,"next event missing");
   $display("PASS mode-gated single press events and KEY4"); $finish;
 end
 initial begin #100000; $fatal(1,"timeout"); end
endmodule
