// Included in the existing real-data system bench. The stimulus and complete
// SDRAM pixel scoreboard remain unchanged; observe the added production path.
wire osd_auto;
wire [7:0] osd_error;
`ifdef TRANSITION_S1
wire [23:0] osd_base = transition_rgb;
`else
wire [23:0] osd_base = display_valid ? rgb : 24'd0;
`endif
wire [23:0] osd_pixels;
wire status_active;
osd_status_cdc status_crossing(.src_clk(src_clk),.src_rst(rst),
 .src_auto(app.auto_play_indicator),.src_error(app.osd_error_code),
 .dst_clk(pix_clk),.dst_rst(rst),.dst_auto(osd_auto),.dst_error(osd_error));
status_osd_overlay overlay(.clk(pix_clk),.rst(rst),.vs(vs),.de(de),.pixel_x(x),
 .rgb_in(osd_base),.image_index(media_id),.image_valid(media_enable),
 .auto_enabled(osd_auto),.error_code(osd_error),.rgb_out(osd_pixels),.active(status_active));
integer osd_y=0,osd_frames=0,osd_checked=0;
reg osd_de_prev=0;
reg [11:0] osd_frame_snapshot;
always @(negedge pix_clk) if(!rst) begin
 if(!vs)osd_y=0;
 else if(osd_de_prev && !de)osd_y=osd_y+1;
 osd_de_prev=de;
 if(de && x==1 && osd_y==0) begin
  if(overlay.valid_frame!==display_valid || (display_valid && overlay.image_frame!==app.img_idx))
   $fatal(1,"OSD picture commit missed first line: OSD=%0d actual=%0d",overlay.image_frame,app.img_idx);
  if(overlay.auto_frame!==osd_auto || overlay.error_frame!==osd_error)
   $fatal(1,"OSD status snapshot mismatch");
  osd_frame_snapshot={overlay.valid_frame,overlay.image_frame,overlay.auto_frame,overlay.error_frame};
  osd_frames=osd_frames+1;
 end
 if(de && osd_y>=1 && {overlay.valid_frame,overlay.image_frame,overlay.auto_frame,overlay.error_frame}!==osd_frame_snapshot)
  $fatal(1,"OSD status changed within visible frame");
 if(!de || x<8 || x>=280 || osd_y<8 || osd_y>=24) begin
  if(osd_pixels!==osd_base)$fatal(1,"OSD changed original pixel outside text region");
 end else if(osd_pixels!==osd_base && osd_pixels!==(overlay.error_frame==0?24'hffff00:24'hff4444))
  $fatal(1,"OSD unexpected foreground color");
 osd_checked=osd_checked+1;
end
// These are actual existing error states, not synthetic UART event codes.
always @(negedge src_clk) if(!rst) begin
 if(state_code==4'he && app.osd_error_code!==1)$fatal(1,"no-image OSD error");
 if(state_code==4'hf && app.osd_error_code!==2)$fatal(1,"communication OSD error");
 if(state_code==4'hd && app.osd_error_code!==3)$fatal(1,"load OSD error");
end
final $display("OSD system observations: %0d frame snapshots, %0d pixel/blanking checks",osd_frames,osd_checked);

`ifdef OSD_S2
wire [23:0] final_osd_pixels;
wire scroll_active;
`ifdef OSD_UART
`include "cache_uart_subtitle.svh"
localparam integer RUNTIME_TEST=1;
`else
localparam integer RUNTIME_TEST=0;
wire [119:0] runtime_text=0;
wire [3:0] runtime_length=0;
wire runtime_enable=1, runtime_changed=0;
`endif
scroll_text_overlay #(.RUNTIME_ENABLE(RUNTIME_TEST)) scrolling(.clk(pix_clk),.rst(rst),.vs(vs),.de(de),.pixel_x(x),
 .image_valid(media_enable),.rgb_in(osd_pixels),.rgb_out(final_osd_pixels),.active(scroll_active),
 .runtime_text(runtime_text),.runtime_length(runtime_length),.runtime_enable(runtime_enable),.runtime_text_changed(runtime_changed),.font_addr(),.font_data(16'd0),.font_valid(1'b0));

integer expected_scroll=0,scroll_checks=0,scroll_lit=0;
reg motion_started=0,scroll_vs_prev=1;
always @(posedge pix_clk) begin
 if(rst) begin expected_scroll=0;motion_started=0;scroll_vs_prev=1;end
 else begin
  if(RUNTIME_TEST && runtime_changed) expected_scroll=0;
  else if(scroll_vs_prev && !vs && media_enable && runtime_enable) begin
   if(!motion_started)begin motion_started=1;expected_scroll=0;end
   else expected_scroll=(expected_scroll==(RUNTIME_TEST ? 624+runtime_length*16 : 1024))?0:expected_scroll+1;
  end
  scroll_vs_prev=vs;
 end
end
always @(negedge pix_clk) if(!rst) begin
 if(scrolling.scroll!==expected_scroll || scrolling.started!==motion_started)
  $fatal(1,"scroll restarted/stalled across visible commit or rescan");
 if(!de || x<8 || x>=632 || osd_y<444 || osd_y>=460 || !motion_started || !runtime_enable)begin
  if(final_osd_pixels!==osd_pixels || scroll_active)$fatal(1,"scroll changed outside window or before first image");
 end else if(final_osd_pixels!==(scroll_active?24'hffffff:osd_pixels))
  $fatal(1,"scroll composite color");
 scroll_checks=scroll_checks+1;
 if(scroll_active)scroll_lit=scroll_lit+1;
end
final $display("Scroll system observations: %0d output checks, %0d foreground pixels",scroll_checks,scroll_lit);
`endif

`ifdef OSD_S3
wire [23:0] band_pixels;
wire band_active;
wire [23:0] timestamp_pixels;
wire timestamp_active;
`ifdef OSD_TIMESTAMP
timestamp_osd timer(.clk(pix_clk),.rst(rst),.vs(vs),.de(de),.pixel_x(x),
 .rgb_in(final_osd_pixels),.rgb_out(timestamp_pixels),.active(timestamp_active));
integer time_frames=0,time_checks=0,time_lit=0,time_seconds;
reg time_vs_prev=1;
always @(posedge pix_clk) begin
 if(rst)begin time_frames=0;time_vs_prev=1;end
 else begin
  if(time_vs_prev && !vs)time_frames=time_frames+1;
  time_vs_prev=vs;
 end
end
always @(negedge pix_clk) if(!rst)begin
 time_seconds=(time_frames/60)%6000;
 if(timer.enabled.minute_tens!==time_seconds/600 ||
    timer.enabled.minute_ones!==(time_seconds/60)%10 ||
    timer.enabled.second_tens!==(time_seconds%60)/10 ||
    timer.enabled.second_ones!==time_seconds%10)$fatal(1,"system timestamp count");
 if(!de || x<500 || x>=580 || osd_y<8 || osd_y>=24)begin
  if(timestamp_active || timestamp_pixels!==final_osd_pixels)$fatal(1,"timestamp outside area");
 end else if(timestamp_pixels!==(timestamp_active?24'hffffff:final_osd_pixels))$fatal(1,"timestamp color");
 time_checks=time_checks+1;if(timestamp_active)time_lit=time_lit+1;
end
final begin
 if(time_lit==0)$error("timestamp never rendered");
 $display("Timestamp system observations: %0d frame edges, %0d pixel/blanking checks, %0d foreground pixels",time_frames,time_checks,time_lit);
end
`else
assign timestamp_pixels=final_osd_pixels;
assign timestamp_active=1'b0;
`endif
osd_alpha_band #(.RUNTIME_ENABLE(RUNTIME_TEST)) bands(.clk(pix_clk),.rst(rst),.vs(vs),.de(de),.pixel_x(x),
 .rgb_in(timestamp_pixels),.glyph_active(status_active || scroll_active || timestamp_active),
 .rgb_out(band_pixels),.active(band_active),.subtitle_enable(runtime_enable && runtime_length!=0));
integer band_checks=0,band_lit=0;
reg expected_band;
reg [23:0] expected_band_rgb;
always @(negedge pix_clk) if(!rst) begin
 expected_band=de && ((x>=4 && x<284 && osd_y>=4 && osd_y<28) ||
                      (x>=8 && x<632 && osd_y>=440 && osd_y<464 && (!RUNTIME_TEST || (runtime_enable && runtime_length!=0)))) &&
               !(status_active || scroll_active || timestamp_active);
 expected_band_rgb=expected_band ?
  {1'b0,timestamp_pixels[23:17],1'b0,timestamp_pixels[15:9],1'b0,timestamp_pixels[7:1]} : timestamp_pixels;
 if(band_pixels!==expected_band_rgb || band_active!==expected_band)
  $fatal(1,"OSD final composite differs at x=%0d y=%0d",x,osd_y);
 band_checks=band_checks+1;
 if(band_active)band_lit=band_lit+1;
end
final $display("Band system observations: %0d output checks, %0d dimmed pixels",band_checks,band_lit);
`endif
