`timescale 1ns/1ps
module tb_rescan_key;
reg clk=0,rst=1,enable=1,key1=1,key2=1,key4=1;
reg [1:0] mode=0;
wire next_event,rescan_event,previous_event,auto_toggle_event,manual_activity,scene_mode;
integer next_count=0, rescan_count=0;
always #5 clk=~clk;
mode_key_control #(.CLK_FREQ_HZ(1000)) dut(.adjust_decrease(),.adjust_increase(),.adjust_restore(),.adjust_select(),.*);
always @(posedge clk) begin
    if(next_event) next_count=next_count+1;
    if(rescan_event) rescan_count=rescan_count+1;
end
task cycles(input integer n); repeat(n) @(negedge clk); endtask
initial begin
    cycles(4); rst=0; cycles(25);
    key2=0; cycles(60);
    if(next_count) $fatal(1,"next must wait for release");
    key2=1; cycles(30);
    if(next_count!=1) $fatal(1,"short release missing");
    key2=0; cycles(2100);
    if(rescan_count!=1 || next_count!=1) $fatal(1,"long press event");
    mode=2; cycles(2100); key2=1; cycles(30);
    if(rescan_count!=1 || next_count!=1) $fatal(1,"held/release retrigger");
    enable=0; mode=0; key2=0; cycles(2100); key2=1; cycles(30);
    if(rescan_count!=2) $fatal(1,"init/error long press disabled");
    enable=1; mode=0; key2=0; cycles(40); mode=1; cycles(10); mode=0;
    key2=1; cycles(30);
    if(next_count!=1) $fatal(1,"mode change converted gesture");
    $display("PASS KEY2 release, long hold once, disabled recovery, mode change"); $finish;
end
initial begin #100000; $fatal(1,"watchdog"); end
endmodule
