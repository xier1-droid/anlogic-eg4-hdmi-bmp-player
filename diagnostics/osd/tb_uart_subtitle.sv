`timescale 1ns/1ps
module tb_uart_subtitle;
 reg clk=0,pix=0,rst=1,rx=1,vs=1,de=0;
 reg [9:0] x=0;
 reg [15:0] events=0;
 always #5 clk=~clk;
 always #7 pix=~pix;
 wire [7:0] data,reply_data;
 wire valid,error,reply_valid,reply_last,reply_ready,tx;
 wire [119:0] src_text,dst_text;
 wire [3:0] src_len,dst_len;
 wire src_en,dst_en,change,frame_start,update;
 wire [23:0] text_rgb,final_rgb;
 wire hit,band;
 uart_rx_byte #(.CLKS_PER_BIT(16)) receiver(.clk(clk),.rst_n(!rst),.rx(rx),
  .data(data),.valid(valid),.framing_error(error));
 subtitle_uart_controller control(.clk(clk),.rst(rst),.rx_data(data),.rx_valid(valid),
  .rx_framing_error(error),.cfg_text(src_text),.cfg_length(src_len),.cfg_enable(src_en),
  .cfg_update_valid(update),.reply_valid(reply_valid),.reply_data(reply_data),
  .reply_last(reply_last),.reply_ready(reply_ready));
 uart_event_logger #(.CLK_FREQ_HZ(160000),.BAUD_RATE(10000),.REPLY_ENABLE(1)) logger(
  .clk(clk),.rst(rst),.events(events),.image_index(2'd0),.sector(32'd0),
  .error_code(3'd0),.phase(4'd0),.auto_enabled(1'b0),.sd_debug(64'd0),.uart_tx(tx),
  .reply_valid(reply_valid),.reply_data(reply_data),.reply_last(reply_last),.reply_ready(reply_ready));
 osd_pixel_position pos(.clk(pix),.rst(rst),.vs(vs),.de(de),.line_y(),
  .frame_start(frame_start),.first_active());
 subtitle_frame_commit mailbox(.src_clk(clk),.src_rst(rst),.src_text(src_text),
  .src_length(src_len),.src_enable(src_en),.dst_clk(pix),.dst_rst(rst),
  .frame_start(frame_start),.dst_text(dst_text),.dst_length(dst_len),.dst_enable(dst_en),.text_changed(change));
 scroll_text_overlay #(.RUNTIME_ENABLE(1)) overlay(.clk(pix),.rst(rst),.vs(vs),.de(de),
  .pixel_x(x),.image_valid(1'b1),.rgb_in(24'hffffff),.rgb_out(text_rgb),.active(hit),
  .runtime_text(dst_text),.runtime_length(dst_len),.runtime_enable(dst_en),.runtime_text_changed(change),.font_addr(),.font_data(16'd0),.font_valid(1'b0));
 osd_alpha_band #(.RUNTIME_ENABLE(1)) bands(.clk(pix),.rst(rst),.vs(vs),.de(de),.pixel_x(x),
  .rgb_in(text_rgb),.glyph_active(hit),.subtitle_enable(dst_en && dst_len!=0),.rgb_out(final_rgb),.active(band));
 string lines[0:127];integer line_count=0,rx_errors=0,updates=0;
 string partial="";reg [7:0] decoded;integer b;
 // Independent serial decoder checks complete non-interleaved output lines.
 initial forever begin
  @(negedge tx);#80;if(tx!==0)$fatal(1,"TX start");
  for(b=0;b<8;b=b+1)begin #160;decoded[b]=tx;end
  #160;if(tx!==1)$fatal(1,"TX stop");
  if(decoded==10)begin lines[line_count]=partial;line_count=line_count+1;partial="";end
  else if(decoded!=13 && decoded!=0)partial={partial,decoded};
 end
 always @(posedge clk)begin if(error)rx_errors=rx_errors+1;if(update)updates=updates+1;end
 reg [124:0] old_dst;reg sampled_frame;
 always @(posedge pix)begin
  old_dst={dst_en,dst_len,dst_text};sampled_frame=frame_start;
  #1;if(!rst && !sampled_frame && old_dst!=={dst_en,dst_len,dst_text})$fatal(1,"frame tearing");
 end
 reg [124:0] prev_held;reg busy_prev=0;
 always @(negedge clk)begin
  if(!rst && busy_prev && mailbox.held!==prev_held)$fatal(1,"mailbox payload changed before ack");
  prev_held=mailbox.held;busy_prev=!rst && mailbox.request!=mailbox.ack_sync[1];
 end
 task byte_in(input [7:0] value,input bit bad_stop=0);
  integer j;
  begin @(negedge clk);rx=0;repeat(16)@(negedge clk);
   for(j=0;j<8;j=j+1)begin rx=value[j];repeat(16)@(negedge clk);end
   rx=!bad_stop;repeat(16)@(negedge clk);rx=1;repeat(20)@(negedge clk);
  end
 endtask
 task send(input string command);
  integer j;begin for(j=0;j<command.len();j=j+1)byte_in(command[j]);end
 endtask
 task expect_line(input integer n,input string value);
  begin wait(line_count>n);if(lines[n]!=value)$fatal(1,"line %0d got <%s> want <%s>",n,lines[n],value);end
 endtask
 task frame;
  begin @(negedge pix);vs=0;de=0;repeat(4)@(negedge pix);vs=1;repeat(8)@(negedge pix);end
 endtask
 integer n,j,base_errors;
 initial begin
  #101;rst=0;expect_line(0,"BOOT v0.5.4-s3-local.2");
  if(dst_len!=12 || dst_text!=120'h0000002041475046208c8b8b8a8389 || !dst_en)$fatal(1,"default changed");
  send("SUB=ab");byte_in(13);byte_in(10);expect_line(1,"OK");
  if(dst_len!=12)$fatal(1,"updated without frame");frame();
  if(dst_len!=2 || dst_text[15:0]!=16'h4241)$fatal(1,"ASCII commit dst=%h/%d src=%h/%d held=%h",dst_text,dst_len,src_text,src_len,mailbox.held);
  send("SUB?\n");expect_line(2,"SUB=1,02,4142");
  send("SUB=OFF\n");expect_line(3,"OK");frame();if(dst_en)$fatal(1,"OFF");
  send("SUB=ON");byte_in(13);expect_line(4,"OK");frame();if(!dst_en)$fatal(1,"ON");
  send("SUB=CN\n");expect_line(5,"OK");frame();if(dst_len!=6 || dst_text[47:0]!=48'h8c8b8b8a8389)$fatal(1,"CN");
  send("SUB?\n");expect_line(6,"SUB=1,06,89838A8B8B8C");
  send("SUB=123456789012\n");expect_line(7,"OK");
  send("SUB=1234567890123\n");expect_line(8,"ERR");if(src_len!=12)$fatal(1,"overflow modified state");
  send("SUB=");byte_in(8'h8d);byte_in(10);expect_line(9,"ERR");
  send("BAD\n");expect_line(10,"ERR");
  send("SUB=");byte_in(8'h80);byte_in("a");byte_in(10);expect_line(11,"OK");
  frame();frame();if(dst_len!=2 || dst_text[15:0]!=16'h4180)$fatal(1,"mixed/latest commit");
  // In-flight accepted updates coalesce; ACK only on frame application.
  send("SUB=X\n");expect_line(12,"OK");
  send("SUB=Y\n");expect_line(13,"OK");
  send("SUB=Z\n");expect_line(14,"OK");frame();frame();
  if(dst_text[7:0]!="Z")$fatal(1,"latest mailbox lost");
  base_errors=rx_errors;send("SUB=");byte_in("A",1);byte_in(10);expect_line(15,"ERR");
  if(rx_errors<=base_errors || src_text[7:0]!="Z")$fatal(1,"framing error");
  // Both log and query must remain full lines, even while bytes compete.
  @(negedge clk);events=1;@(negedge clk);events=0;
  send("SUB?\n");wait(line_count>=18);
  if(lines[16].substr(0,6)!="INIT_OK" || lines[17]!="SUB=1,01,5A")$fatal(1,"log/reply interleaving");
  send("SUB=\n");expect_line(18,"OK");frame();if(dst_len!=0)$fatal(1,"empty");
  @(negedge clk);rst=1;repeat(4)@(negedge clk);rst=0;
  repeat(6)@(negedge pix);if(dst_len!=12 || dst_text!=120'h0000002041475046208c8b8b8a8389 || !dst_en)$fatal(1,"reset default");
  $display("PASS UART subtitle: real RX/TX 8N1, CR/LF, ASCII/CN/mixed, 12/13 boundary, query, log arbitration, bad stop, atomic/latest frame commit, reset; updates=%0d",updates);
  $finish;
 end
 initial begin #10000000;$fatal(1,"UART subtitle watchdog lines=%0d",line_count);end
endmodule

