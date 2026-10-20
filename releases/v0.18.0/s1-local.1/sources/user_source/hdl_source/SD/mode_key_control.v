// Three independent active-low keys. Mode gates new picture events only.
// v0.18: one 1 ms prescaler times every key counter (debounce, holds and
// adjust gestures), so each duration may end up to 1 ms late; with
// CLK_FREQ_HZ=1000 the tick is every clock and timing is unchanged.
// Mode 0 KEY4: a press released before SCENE_HOLD_MS toggles AUTO on release;
// holding it SCENE_HOLD_MS toggles scene mode once and its release is ignored.
// Scene mode stays across modes; in mode 0 KEY1 toggles the warning mode,
// which ends with scene mode.
module mode_key_control #(
    parameter integer CLK_FREQ_HZ = 100_000_000,
    parameter integer RESCAN_HOLD_MS = 2000,
    parameter integer SCENE_HOLD_MS = 1000,
    parameter integer PREVIEW_ENABLE = 0
)(
    input wire clk, rst, enable,
    input wire key1, key2, key4,
    input wire [1:0] mode,
    output reg next_event, rescan_event,
    output wire previous_event,
    output reg auto_toggle_event,
    output reg scene_mode,
    output reg warn_mode,
    output wire adjust_decrease,adjust_increase,adjust_restore,adjust_select,
    output wire manual_activity
);
    localparam integer MS_CYCLES = CLK_FREQ_HZ / 1000;
    localparam integer MS_BITS = MS_CYCLES > 1 ? $clog2(MS_CYCLES) : 1;
    reg [MS_BITS-1:0] ms_count;
    wire ms_tick = MS_CYCLES <= 1 || ms_count == MS_CYCLES - 1;
    // The old cycle counts started at 1 and ended at N-1, two clocks short of
    // N ms. Counted in ticks that would be two ms short, so with a real
    // prescaler the limits are raised to end within 1 ms of the old timing;
    // with one clock per ms (tests) they are the old counts.
    localparam integer TICK_ADJ = MS_CYCLES > 1 ? 1 : 0;
    always @(posedge clk or posedge rst) begin
        if (rst) ms_count <= 0;
        else if (ms_tick) ms_count <= 0;
        else ms_count <= ms_count + 1'b1;
    end
    wire press1, press2, press4;
    wire stable1, stable2, stable4;
    key_ms_debounce u_key1 (
        .clk(clk), .rst(rst), .ms_tick(ms_tick), .button_in(key1),
        .press_pulse(press1), .button_stable_out(stable1)
    );
    key_ms_debounce u_key2 (
        .clk(clk), .rst(rst), .ms_tick(ms_tick), .button_in(key2),
        .press_pulse(press2), .button_stable_out(stable2)
    );
    key_ms_debounce u_key4 (
        .clk(clk), .rst(rst), .ms_tick(ms_tick), .button_in(key4),
        .press_pulse(press4), .button_stable_out(stable4)
    );
    // Capture the mode at the debounced press edge, even if mode changes on
    // that same clock. Holding a key across a mode change never creates a press.
    reg [1:0] press_mode;
    always @(posedge clk or posedge rst) begin
        if (rst) press_mode <= 0;
        else press_mode <= mode;
    end
    assign previous_event = enable && ((press_mode == 0 && !scene_mode) || (PREVIEW_ENABLE && press_mode == 3)) && press_mode==mode && press1;
    localparam integer HOLD_CYCLES = RESCAN_HOLD_MS + 2*TICK_ADJ;   // in ms ticks
    localparam integer HOLD_BITS = $clog2(HOLD_CYCLES + 1);
    reg [HOLD_BITS-1:0] held_cycles;
    reg stable2_d, long_fired, short_allowed, rescan_allowed;
    reg [1:0] short_mode;
    // Track KEY2 independently of media readiness. Only release re-arms it.
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            short_mode<=0; stable2_d <= 1; held_cycles <= 0; long_fired <= 0;
            rescan_allowed <= 0; short_allowed <= 0; next_event <= 0; rescan_event <= 0;
        end else begin
            stable2_d <= stable2;
            next_event <= 0; rescan_event <= 0;
            if (stable2_d && !stable2) begin
                short_allowed <= enable && (mode == 0 || (PREVIEW_ENABLE && mode == 3));
                short_mode<=mode; rescan_allowed <= (mode==0 || mode==3);
                held_cycles <= 1;
            end else if (!stable2) begin
                if (!enable || mode != short_mode) short_allowed <= 0;
                if(mode!=short_mode)rescan_allowed<=0;
                if (!long_fired && rescan_allowed && mode==short_mode) begin
                    if (held_cycles >= HOLD_CYCLES - 1) begin
                        rescan_event <= 1;
                        long_fired <= 1;
                        short_allowed <= 0;
                    end else if (ms_tick) held_cycles <= held_cycles + 1'b1;
                end
            end else begin
                if (!stable2_d && !long_fired && short_allowed && enable && mode == short_mode)
                    next_event <= 1;
                held_cycles <= 0; long_fired <= 0; short_allowed <= 0;
            end
        end
    end
    adjust_key_gestures #(.TICK_ADJ(TICK_ADJ)) adjust_keys(
        .clk(clk),.rst(rst),.ms_tick(ms_tick),.mode(mode),.stable1(stable1),.stable2(stable2),.stable4(stable4),
        .decrease(adjust_decrease),.increase(adjust_increase),.restore(adjust_restore),.select_next(adjust_select));
    localparam integer SCENE_CYCLES = SCENE_HOLD_MS + 2*TICK_ADJ;   // in ms ticks
    localparam integer SCENE_BITS = $clog2(SCENE_CYCLES + 1);
    reg [SCENE_BITS-1:0] held4_cycles;
    reg stable4_d, long4_fired, key4_allowed, short4_event;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            stable4_d <= 1; held4_cycles <= 0; long4_fired <= 0; key4_allowed <= 0;
            short4_event <= 0; scene_mode <= 0;
        end else begin
            stable4_d <= stable4;
            short4_event <= 0;
            if (stable4_d && !stable4) begin
                key4_allowed <= enable && mode == 0;
                held4_cycles <= 1;
            end else if (!stable4) begin
                if (!enable || mode != 0) key4_allowed <= 0;
                if (!long4_fired && key4_allowed && enable && mode == 0) begin
                    if (held4_cycles >= SCENE_CYCLES - 1) begin
                        scene_mode <= ~scene_mode;
                        long4_fired <= 1;
                    end else if (ms_tick) held4_cycles <= held4_cycles + 1'b1;
                end
            end else begin
                if (!stable4_d && !long4_fired && key4_allowed && enable && mode == 0)
                    short4_event <= 1;
                held4_cycles <= 0; long4_fired <= 0; key4_allowed <= 0;
            end
        end
    end
    always @(posedge clk or posedge rst)
        if (rst) warn_mode <= 0;
        else if (!scene_mode) warn_mode <= 0;
        else if (enable && press1 && press_mode == 0 && mode == 0) warn_mode <= ~warn_mode;
    // Register the media toggle to break mode -> preview -> cache request logic.

    // Mode 3 keeps the press edge for the preview toggle.
    always @(posedge clk or posedge rst)
        if(rst)auto_toggle_event<=0;
        else auto_toggle_event<=short4_event || (enable && press4 && press_mode==mode && mode==3);
    assign manual_activity = enable &&
        (!stable1 || !stable2 || !stable4 || press1 || press2 || press4);
endmodule

// All inputs are already debounced. Wait for release after mode changes.
// Durations count ms ticks: 100 ms press window, 1 s KEY4 long press.
module adjust_key_gestures #(parameter integer TICK_ADJ=0)(
 input clk,rst,ms_tick,input [1:0] mode,input stable1,stable2,stable4,
 output reg decrease,increase,restore,select_next
);
 localparam WINDOW=100+2*TICK_ADJ;
 localparam LONG=1000+TICK_ADJ;
 reg [1:0] mode_q,state;
 reg armed,s1_q,s2_q,s4_q,key4_active;
 reg [$clog2(WINDOW+1)-1:0] count;
 reg [$clog2(LONG+1)-1:0] hold4;
 wire p1=s1_q && !stable1,p2=s2_q && !stable2;
 always @(posedge clk or posedge rst)begin
  if(rst)begin
   mode_q<=0;state<=0;armed<=0;s1_q<=1;s2_q<=1;s4_q<=1;
   key4_active<=0;count<=0;hold4<=0;
   decrease<=0;increase<=0;restore<=0;select_next<=0;
  end else begin
   mode_q<=mode;s1_q<=stable1;s2_q<=stable2;s4_q<=stable4;
   decrease<=0;increase<=0;restore<=0;select_next<=0;
   if(mode!=mode_q || !(mode==1 || mode==2))begin
    armed<=0;state<=0;count<=0;key4_active<=0;hold4<=0;
   end else if(!armed)begin
    if(stable1 && stable2 && stable4)armed<=1;
   end else begin
    case(state)
     0:begin
      count<=0;
      if(p1 && p2)begin restore<=1;state<=3;end
      else if(p1)begin state<=1;count<=1;end
      else if(p2)begin state<=2;count<=1;end
     end
     1,2:begin
      if((state==1 && p2) || (state==2 && p1))begin restore<=1;state<=3;end
      else if(count>=WINDOW-1 || (state==1 && stable1) || (state==2 && stable2))begin
       decrease<=state==1;increase<=state==2;state<=3;
      end else if(ms_tick)count<=count+1'b1;
     end
     3:if(stable1 && stable2)state<=0;
    endcase
    if(s4_q && !stable4)begin key4_active<=1;hold4<=1;end
    else if(!stable4 && key4_active)begin if(hold4<LONG && ms_tick)hold4<=hold4+1'b1;end
    else if(stable4 && key4_active)begin
     if(hold4<LONG && state==0 && stable1 && stable2)select_next<=1;
     key4_active<=0;hold4<=0;
    end
   end
  end
 end
endmodule

// key_press_debounce counted in ms ticks: a level must differ from the
// stable one for DEBOUNCE_MS ticks (the first may be partial).
module key_ms_debounce #(parameter integer DEBOUNCE_MS = 20)(
    input wire clk, rst, ms_tick,
    input wire button_in,    // released=1, pressed=0
    output reg press_pulse,
    output wire button_stable_out
);
    reg button_sync0, button_sync1, button_stable;
    reg [$clog2(DEBOUNCE_MS)-1:0] cnt;
    assign button_stable_out = button_stable;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            button_sync0 <= 1'b1; button_sync1 <= 1'b1; button_stable <= 1'b1;
            cnt <= 0; press_pulse <= 1'b0;
        end else begin
            button_sync0 <= button_in;
            button_sync1 <= button_sync0;
            press_pulse <= 1'b0;
            if (button_sync1 == button_stable) cnt <= 0;
            else if (ms_tick) begin
                if (cnt >= DEBOUNCE_MS - 1) begin
                    if (button_stable && !button_sync1) press_pulse <= 1'b1;
                    button_stable <= button_sync1;
                    cnt <= 0;
                end else cnt <= cnt + 1'b1;
            end
        end
    end
endmodule
