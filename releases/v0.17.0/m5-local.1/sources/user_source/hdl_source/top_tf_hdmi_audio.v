
module top(
    input                       clk,
    input                       rst_n,
    input                       key1,           // 图片模式：上一张
    input                       key2,           // 图片模式：下一张
    input                       key4,           // MAN/AUTO切换
    input                       sw1,            // C8，拨上=1
    input                       sw2,            // C7，拨上=1

    output [5:0]                seg_sel,
    output [7:0]                seg_data,

    // HDMI TMDS
    output                      HDMI_CLK_P,
    output                      HDMI_D2_P,
    output                      HDMI_D1_P,
    output                      HDMI_D0_P,

    // HDMI DDC
    inout                       HDMI_DDC_SCL,
    inout                       HDMI_DDC_SDA,

    // TF card SPI
    output                      sd_ncs,
    output                      sd_dclk,
    output                      sd_mosi,
    input                       sd_miso,
    input                       uart_rx, // F12, asynchronous 115200 8N1
    output                      uart_tx
);

parameter integer OSD_ENABLE = 1;
parameter integer SCROLL_ENABLE = 1;
parameter integer BAND_ENABLE = 1;
parameter integer TIMESTAMP_ENABLE = 1;
parameter integer TRANSITION_ENABLE = 1;
parameter integer AUDIO_VIS_ENABLE = 1;
parameter integer HAZARD_TEST_SOURCE = 0; // 1: M3 test driver (t loops, layer always on) instead of scenario_fsm
parameter integer UART_LOG_ENABLE = 0;      // event log on uart_tx; off holds uart_tx idle high
parameter integer UART_SUBTITLE_ENABLE = 0; // subtitle commands on uart_rx; off keeps the power-on subtitle
parameter MEM_DATA_BITS = 32;
parameter integer UART_CLK_FREQ_HZ = 100_000_000;
parameter integer UART_BAUD_RATE = 115200;
parameter ADDR_BITS     = 21;
parameter BUSRT_BITS    = 10;
parameter [ADDR_BITS-1:0] FRAME_PIXELS = 307200;   // 640*480
parameter [ADDR_BITS-1:0] BUF0_ADDR = 0;
parameter [ADDR_BITS-1:0] BUF1_ADDR = FRAME_PIXELS;
parameter [ADDR_BITS-1:0] BUF2_ADDR = FRAME_PIXELS * 2;
parameter [ADDR_BITS-1:0] BUF3_ADDR = FRAME_PIXELS * 3;

wire Sdr_init_done;
wire Sdr_init_ref_vld;
wire Sdr_busy;

wire sd_card_clk;
wire ext_mem_clk;
wire ext_mem_clk_sft;
wire video_clk;
wire hdmi_5x_clk;

wire hs;
wire vs;
wire de;
wire [9:0] video_x; // Aligned with hs/vs/de/vout_data for the HDMI core.

wire [23:0] vout_data_raw;
wire [23:0] vout_data;
// S1 transition precedes OSD; all RGB channels retain the original latency.
wire [23:0] transition_rgb;
wire [23:0] osd_rgb;
wire [23:0] scroll_rgb;
wire [23:0] timestamp_rgb;
wire [23:0] band_rgb;
wire status_glyph_active, scroll_glyph_active;
wire timestamp_glyph_active;
wire [7:0] osd_error_src, osd_error_pixel;
wire osd_auto_pixel;
wire        display_valid;
wire [1:0] committed_image, audio_image;
wire committed_valid, committed_ready, audio_update, audio_enable;

wire [3:0]  state_code;
wire [63:0] sd_debug;
reg [63:0] sd_debug_panel0, sd_debug_panel1;
reg [63:0] sd_debug_half;
wire [7:0]  combo_event_count;
wire        combo_debug_active;
wire        auto_play_indicator;
wire [57:0] uart_diagnostics;
reg [1:0]   auto_indicator_sync;

wire        video_read_req;
wire        video_read_req_ack;
wire        video_read_en;
wire [31:0] video_read_data;

wire        sd_card_write_en;
wire [31:0] sd_card_write_data;
wire write_cancel_req, write_cancel_ack;
wire        sd_card_write_req;
wire        sd_card_write_req_ack;
wire        frame_write_finish;
wire source_frame_done, source_frame_error;
wire frame_error_toggle;
wire [2:0] frame_memory_error, frame_reader_error;
wire frame_underflow;
wire frame_wr_busy, frame_rd_busy;
reg         frame_write_toggle_mem;

wire [1:0]  write_buf_idx;
wire [1:0]  disp_buf_idx;
wire        display_commit_request, display_commit_ack;
wire transition_active,transition_wipe;
wire preview_request,preview_ack;
wire [17:0] preview_descriptor,pixel_descriptor;
wire preview_pixel=pixel_descriptor[17];
wire [4:0] transition_level;

wire App_rd_en;
wire [ADDR_BITS-1:0] App_rd_addr;
wire Sdr_rd_en;
wire [MEM_DATA_BITS-1:0] Sdr_rd_dout;
wire App_wr_en;
wire [ADDR_BITS-1:0] App_wr_addr;
wire [MEM_DATA_BITS-1:0] App_wr_din;
wire [3:0] App_wr_dm;

wire hs_0;
wire vs_0;
wire de_0;
wire [9:0] video_x_0;

wire [9:0]  tmds_ch0_data;
wire [9:0]  tmds_ch1_data;
wire [9:0]  tmds_ch2_data;
wire [9:0]  tmds_clk_data;

// Both clock trees must lock. Each consumer releases reset on its own clock.
wire sys_pll_lock;
wire reset_request = ~rst_n | ~sys_pll_lock;
wire rst_panel, rst_sd, rst_mem, rst_video, rst_serial;
// Half-cycle staging gives the observed bus margin at the 50 MHz capture edge.
// This path remains timed; no diagnostic CDC timing exception is introduced.
always @(negedge sd_card_clk or posedge rst_sd) begin
    if(rst_sd) sd_debug_half <= 0;
    else sd_debug_half <= sd_debug;
end
// Debug value settles before F; the panel consumes the retained result.
always @(posedge clk or posedge rst_panel) begin
    if(rst_panel) begin sd_debug_panel0 <= 0; sd_debug_panel1 <= 0; end
    else begin sd_debug_panel0 <= sd_debug_half; sd_debug_panel1 <= sd_debug_panel0; end
end
reset_sync u_reset_panel (.clk(clk), .async_rst(reset_request), .rst(rst_panel));
reset_sync u_reset_sd (.clk(sd_card_clk), .async_rst(reset_request), .rst(rst_sd));
reset_sync u_reset_mem (.clk(ext_mem_clk), .async_rst(reset_request), .rst(rst_mem));
reset_sync u_reset_video (.clk(video_clk), .async_rst(reset_request), .rst(rst_video));
reset_sync u_reset_serial (.clk(hdmi_5x_clk), .async_rst(reset_request), .rst(rst_serial));

// UART command state lives in the SD/control domain; renderer sees frame snapshots.
wire [7:0] sub_rx_data, sub_reply_data;
wire sub_rx_valid, sub_rx_error, sub_reply_valid, sub_reply_last, sub_reply_ready;
wire [119:0] sub_text_src, sub_text_pixel;
wire [3:0] sub_length_src, sub_length_pixel;
wire sub_enable_src, sub_enable_pixel, sub_text_changed, sub_frame_start;
osd_pixel_position u_subtitle_position(.clk(video_clk),.rst(rst_video),.vs(vs),.de(de),
 .line_y(),.frame_start(sub_frame_start),.first_active());
generate if(UART_SUBTITLE_ENABLE) begin:g_uart_subtitle
uart_rx_byte #(.CLKS_PER_BIT((UART_CLK_FREQ_HZ+UART_BAUD_RATE/2)/UART_BAUD_RATE)) u_uart_rx (
 .clk(sd_card_clk),.rst_n(~rst_sd),.rx(uart_rx),.data(sub_rx_data),
 .valid(sub_rx_valid),.framing_error(sub_rx_error));
subtitle_uart_controller u_subtitle_control(
 .clk(sd_card_clk),.rst(rst_sd),.rx_data(sub_rx_data),.rx_valid(sub_rx_valid),
 .rx_framing_error(sub_rx_error),.cfg_text(sub_text_src),.cfg_length(sub_length_src),
 .cfg_enable(sub_enable_src),.cfg_update_valid(),.reply_valid(sub_reply_valid),
 .reply_data(sub_reply_data),.reply_last(sub_reply_last),.reply_ready(sub_reply_ready));
subtitle_frame_commit u_subtitle_commit(
 .src_clk(sd_card_clk),.src_rst(rst_sd),.src_text(sub_text_src),
 .src_length(sub_length_src),.src_enable(sub_enable_src),
 .dst_clk(video_clk),.dst_rst(rst_video),.frame_start(sub_frame_start),
 .dst_text(sub_text_pixel),.dst_length(sub_length_pixel),.dst_enable(sub_enable_pixel),
 .text_changed(sub_text_changed));
end else begin:g_fixed_subtitle
// subtitle_frame_commit's reset payload held forever: the picture of an idle
// UART. Text matches DEFAULT_TEXT in subtitle_frame_commit/subtitle_uart_controller.
assign sub_text_pixel = 120'h0000002041475046208c8b8b8a8389;
assign sub_length_pixel = 4'd12;
assign sub_enable_pixel = 1'b1;
assign sub_text_changed = 1'b0;
assign sub_reply_valid = 1'b0;
assign sub_reply_data = 8'd0;
assign sub_reply_last = 1'b0;
end endgenerate

generate if(UART_LOG_ENABLE) begin:g_uart_log
uart_event_logger #(.CLK_FREQ_HZ(UART_CLK_FREQ_HZ), .BAUD_RATE(UART_BAUD_RATE), .REPLY_ENABLE(UART_SUBTITLE_ENABLE)) u_uart_logger (
    .clk(sd_card_clk), .rst(rst_sd), .events(uart_diagnostics[57:42]),
    .image_index(uart_diagnostics[41:40]), .sector(uart_diagnostics[39:8]),
    .error_code(uart_diagnostics[7:5]), .phase(uart_diagnostics[4:1]),
    .auto_enabled(uart_diagnostics[0]), .sd_debug(sd_debug), .uart_tx(uart_tx),
    .reply_valid(sub_reply_valid), .reply_data(sub_reply_data),
    .reply_last(sub_reply_last), .reply_ready(sub_reply_ready)
);
end else begin:g_uart_idle
// Without the logger, subtitle replies are dropped so commands never stall.
assign uart_tx = 1'b1;
assign sub_reply_ready = 1'b1;
end endgenerate

// SDRAM and TF initialization run independently. Only the first scan waits
// for memory readiness; keep the SD controller out of this dependency loop.
(* ASYNC_REG = "TRUE" *) reg [1:0] sdram_ready_sync;
always @(posedge sd_card_clk or posedge rst_sd) begin
    if (rst_sd) sdram_ready_sync <= 2'b00;
    else sdram_ready_sync <= {sdram_ready_sync[0], Sdr_init_done};
end

wire [1:0] switch_mode;
wire [8:0] ring_y;
// Session parameters: SD-domain gestures, atomic mailbox, VS-boundary commit.
wire adjust_decrease,adjust_increase,adjust_restore,adjust_select;
wire [7:0] brightness_src,contrast_src;
wire [3:0] volume_src;
wire [1:0] selected_src;
wire [23:0] adjust_frame;
wire [1:0] adjust_mode=adjust_frame[23:22],adjust_selected=adjust_frame[21:20];
wire [7:0] brightness_frame=adjust_frame[19:12],contrast_frame=adjust_frame[11:4];
wire [3:0] volume_frame=adjust_frame[3:0];
wire scene_mode_sd,warn_sd;
wire [1:0] speed_src;
media_adjust_control u_adjust_control(.clk(sd_card_clk),.rst(rst_sd),.mode(switch_mode),
 .decrease(adjust_decrease),.increase(adjust_increase),.restore(adjust_restore),.select_next(adjust_select),
 .brightness(brightness_src),.contrast(contrast_src),.volume_level(volume_src),.selected(selected_src),
 .scene_mode(scene_mode_sd),.speed(speed_src));
media_adjust_cdc u_adjust_cdc(.src_clk(sd_card_clk),.src_rst(rst_sd),
 .src_state({switch_mode,selected_src,brightness_src,contrast_src,volume_src}),
 .dst_clk(video_clk),.dst_rst(rst_video),.frame_start(sub_frame_start),.frame_state(adjust_frame));

// Mode and key routing share the SD control clock. Synchronize mode for panel display.

// M5: in scene mode the last digit shows the stage 1-4, or A in the warning
// mode; error codes D-F keep their place.
wire [3:0] panel_code=(scene_mode_sd && state_code<4'hd) ?
 (warn_sd ? 4'ha : {2'd0,committed_image}+4'd1) : state_code;
reg [1:0] mode_panel_sync0, mode_panel_sync1, mode_panel_half;

reg auto_panel_half;
reg [3:0] state_panel_half,state_panel_sync;
// Related 100/50 MHz clocks: stage on the falling source edge so the
// destination rising edge has half a source period of hold margin.
always @(negedge sd_card_clk or posedge rst_sd)begin
 if(rst_sd)begin mode_panel_half<=0;auto_panel_half<=0;state_panel_half<=0;end
 else begin mode_panel_half<=switch_mode;auto_panel_half<=auto_play_indicator;state_panel_half<=panel_code;end
end
switch_mode_control #(.CLK_FREQ_HZ(100_000_000)) u_switch_mode_control (
    .clk(sd_card_clk), .rst(rst_sd), .switches({sw2, sw1}), .mode(switch_mode)
);
always @(posedge clk or posedge rst_panel) begin
    if (rst_panel) begin
        state_panel_sync<=0;
        mode_panel_sync0 <= 0;
        mode_panel_sync1 <= 0;
    end else begin
        state_panel_sync<=state_panel_half;
        mode_panel_sync0 <= mode_panel_half;
        mode_panel_sync1 <= mode_panel_sync0;
    end
end

// The mode indicator crosses from SD control to the 50 MHz scan clock.
always @(posedge clk or posedge rst_panel) begin
    if (rst_panel)
        auto_indicator_sync <= 2'b00;
    else
        auto_indicator_sync <= {auto_indicator_sync[0], auto_panel_half};
end

// 保持你原来的 TF / SDRAM / video 时钟
sys_pll_s3 sys_pll_m0(
    .refclk     (clk),
    .clk0_out   (sd_card_clk),
    .clk1_out   (ext_mem_clk),
    .clk2_out   (ext_mem_clk_sft),
    .clk3_out   (video_clk),
    .clk4_out   (hdmi_5x_clk),
    .extlock    (sys_pll_lock),
    .reset      (~rst_n) // External button only; never feed lock-derived reset back to PLL.
);


// mem_clk 域把 write_finish 单拍转成 toggle，供 sd_card_clk 域可靠同步
always @(posedge ext_mem_clk or posedge rst_mem) begin
    if (rst_mem)
        frame_write_toggle_mem <= 1'b0;
    else if (frame_write_finish)
        frame_write_toggle_mem <= ~frame_write_toggle_mem;
end

// ===================== TF 多图扫描与缓存（双缓冲） =====================
wire bgm_valid,bgm_ready,bgm_active;
wire frame_write_ready,frame_refill_priority;
wire signed [15:0] bgm_left,bgm_right;
wire [23:0] scene_kinds_sd,scene_kinds;
wire scene_stage_done;
wire bin_wr,bin_sel,font_loaded_sd,text_loaded_sd;
wire [11:0] bin_addr;wire [7:0] bin_data;
sd_card_bmp #(
    .CLK_FREQ_HZ       (100_000_000),
    .SCAN_START_SECTOR (32'd0),
    .SCAN_MAX_SECTOR   (32'd131071),
    .SCAN_TARGET_COUNT (3'd4), .SCALE_ENABLE(1), .PREVIEW_ENABLE(1), .AUDIO_ENABLE(1), .USE_FRAME_RESULT(1), .TRANSITION_ENABLE(TRANSITION_ENABLE),
    .TEXT_ENABLE(1)
) sd_card_bmp_m0(
    .warn_mode(warn_sd),.bin_wr(bin_wr),.bin_sel(bin_sel),.bin_addr(bin_addr),.bin_data(bin_data),
    .font_loaded(font_loaded_sd),.text_loaded(text_loaded_sd),
    .bgm_valid(bgm_valid),.bgm_ready(bgm_ready),.bgm_active(bgm_active),
    .bgm_left(bgm_left),.bgm_right(bgm_right),
    .clk               (sd_card_clk),
    .rst               (rst_sd),
    .sdram_ready       (sdram_ready_sync[1]),
    .key1              (key1),
    .key2              (key2),
    .key4              (key4),
    .mode              (switch_mode),
    .scene_mode(scene_mode_sd),.scene_stage_done(scene_stage_done),
    .adjust_decrease(adjust_decrease),.adjust_increase(adjust_increase),
    .adjust_restore(adjust_restore),.adjust_select(adjust_select),
    .state_code        (state_code),
    .sd_debug(sd_debug), .diagnostics(uart_diagnostics),
    .combo_event_count (combo_event_count),
    .combo_debug_active(combo_debug_active),
    .auto_play_indicator(auto_play_indicator),
    .osd_error_code(osd_error_src),
    .bmp_width         (16'd640),
    .bmp_height        (16'd480),
    .display_valid     (display_valid),
    .committed_image(committed_image), .committed_valid(committed_valid),
    .committed_ready(committed_ready),

    .source_frame_done(source_frame_done), .source_frame_error(source_frame_error),
    .frame_error_toggle(frame_error_toggle), .frame_memory_error(frame_memory_error),
    .reader_error(frame_reader_error), .reader_underflow(frame_underflow),
    .write_finish_toggle(frame_write_toggle_mem),
    .display_commit_request(display_commit_request),
    .transition_pix_clk(video_clk), .transition_pix_rst(rst_video),
    .transition_frame_start(sub_frame_start), .transition_commit_done(audio_update),
    .transition_active(transition_active), .transition_level(transition_level),
    .transition_wipe(transition_wipe),
    .display_commit_ack(display_commit_ack),
    .preview_request(preview_request),.preview_ack(preview_ack),.preview_descriptor(preview_descriptor),
    .write_buf_idx     (write_buf_idx),
    .disp_buf_idx      (disp_buf_idx),

    .write_cancel_req(write_cancel_req), .write_cancel_ack(write_cancel_ack),
    .write_req         (sd_card_write_req),
    .write_req_ack     (sd_card_write_req_ack),
    .write_ready       (frame_write_ready),
    .write_en          (sd_card_write_en),
    .write_data        (sd_card_write_data),
    .SD_nCS            (sd_ncs),
    .SD_DCLK           (sd_dclk),
    .SD_MOSI           (sd_mosi),
    .SD_MISO           (sd_miso),
    .scene_kinds       (scene_kinds_sd)
);

seg7_panel seg7_panel_m0(
    .sd_debug(sd_debug_panel1),
    .clk               (clk),
    .rst_n             (~rst_panel),
    .mode              (mode_panel_sync1),
    .state_code        (state_panel_sync),
    .combo_event_count (combo_event_count),
    .combo_debug_active(combo_debug_active),
    .auto_play_indicator(auto_indicator_sync[1]),
    .seg_sel            (seg_sel),
    .seg_data           (seg_data)
);

// ===================== 原图像时序与帧缓存 =====================
video_timing_data video_timing_data_m0(
    .video_clk         (video_clk),
    .rst               (rst_video),
    .read_req          (video_read_req),
    .read_req_ack      (video_read_req_ack),
    .hs                (hs_0),
    .vs                (vs_0),
    .de                (de_0),
    .video_x           (video_x_0)
);

// The pixel keeps the original read timing and passes the 10-clock hazard
// layer; SYNC_EXTRA=10 delays x/hs/vs/de to meet it at vout_data_raw.
wire [31:0] scene_pixel;wire scene_de;
video_delay #(.DATA_WIDTH(32),.SYNC_EXTRA(10)) video_delay_m0(
    .video_clk         (video_clk),
    .rst               (rst_video),
    .read_en           (video_read_en),
    .read_data         (video_read_data),
    .hs                (hs_0),
    .vs                (vs_0),
    .de                (de_0),
    .video_x           (video_x_0),
    .hs_r              (hs),
    .vs_r              (vs),
    .de_r              (de),
    .vout_data         (scene_pixel),
    .video_x_r         (video_x)
);

// M3: hazard layer before brightness/contrast, bypassed for thumbnails.
// scene_de marks scene_pixel: video_delay registers the word read two clocks
// after read_en, so de for the pixel is read_en delayed by two.
reg [1:0] scene_de_d;
always @(posedge video_clk or posedge rst_video)
 if(rst_video)scene_de_d<=2'b00;else scene_de_d<={scene_de_d[0],video_read_en};
assign scene_de=scene_de_d[1];
// Scene kind ({hazard,role} per image, from BMP header bytes 6-7) crosses
// to the pixel domain; the kind of the committed image applies from the
// first frame after the commit, with t restarting.
scene_kind_cdc u_scene_kind_cdc(.src_clk(sd_card_clk),.src_rst(rst_sd),.src_kinds(scene_kinds_sd),
 .dst_clk(video_clk),.dst_rst(rst_video),.dst_kinds(scene_kinds));
wire [9:0] hazard_frame_cnt;wire [7:0] hazard_t_now;wire [2:0] hazard_kind_hazard,hazard_kind_role;
wire hazard_enable,fade_mute;
wire [1:0] scene_stage;wire scene_on,warn_on;
// Speed (scene parameter item) is a quasi-static SD level: two-stage
// synchronizer, taken at frame_start.
(* ASYNC_REG = "TRUE" *) reg [1:0] speed_sync0,speed_sync1;
reg [1:0] speed_frame;
always @(posedge video_clk or posedge rst_video)
 if(rst_video)begin speed_sync0<=0;speed_sync1<=0;speed_frame<=0;end
 else begin speed_sync0<=speed_src;speed_sync1<=speed_sync0;if(sub_frame_start)speed_frame<=speed_sync1;end
generate if(HAZARD_TEST_SOURCE) begin:g_hazard_test
 hazard_test_source u_hazard_test_source(.clk(video_clk),.rst(rst_video),.frame_start(sub_frame_start),.media_update(audio_update),
  .image_index(audio_image),.kinds(scene_kinds),.frame_cnt(hazard_frame_cnt),.t_now(hazard_t_now),
  .hazard(hazard_kind_hazard),.role(hazard_kind_role));
 assign hazard_enable=1'b1;
 assign fade_mute=1'b0;
 assign scene_stage_done=1'b0;
 assign scene_stage=2'd0;assign scene_on=1'b0;assign warn_on=1'b0;
end else begin:g_scenario
 // M4: the stage follows the displayed image; t follows the SD audio file's
 // accepted samples at the parameter-item speed (M5).
 scenario_fsm u_scenario_fsm(.clk(video_clk),.rst(rst_video),.scene_mode_async(scene_mode_sd),
  .frame_start(sub_frame_start),.media_update(audio_update),.image_index(audio_image),.image_valid(audio_enable),
  .kinds(scene_kinds),.sample_tick(bgm_valid && bgm_ready),.audio_running(bgm_active),
  .transition_active(transition_active),.speed(speed_frame),.warn_async(warn_sd),
  .frame_cnt(hazard_frame_cnt),.t_now(hazard_t_now),.stage(scene_stage),.hazard(hazard_kind_hazard),.role(hazard_kind_role),
  .layer_enable(hazard_enable),.fade_mute(fade_mute),.stage_done(scene_stage_done),
  .scene_on(scene_on),.warn_on(warn_on));
end endgenerate
hazard_layer u_hazard_layer(.clk(video_clk),.rst(rst_video),.rgb_in(scene_pixel[31:8]),.t_in(scene_pixel[7:0]),
 .de(scene_de),.frame_start(sub_frame_start),
 .t_now(hazard_t_now),.hazard(hazard_kind_hazard),.role(hazard_kind_role),.enable(hazard_enable),
 .thumbnail(preview_pixel),.frame_cnt(hazard_frame_cnt),.rgb_out(vout_data_raw));

// 首图提交前黑屏；提交后一直显示当前显示缓冲区内容
assign vout_data = display_valid ? vout_data_raw : 24'd0;

wire adjust_hs,adjust_vs,adjust_de,adjust_wipe,adjust_valid,adjust_audio;
wire [9:0] adjust_x;wire [8:0] adjust_y;wire [17:0] adjust_descriptor;
wire [4:0] adjust_level;wire [23:0] adjusted_rgb_raw;
wire [47:0] adjust_side;
assign {adjust_hs,adjust_vs,adjust_de,adjust_x,adjust_y,adjust_descriptor,adjust_level,adjust_wipe,adjust_valid,adjust_audio}=adjust_side;
wire adjust_preview=adjust_descriptor[17];
wire [23:0] adjusted_rgb=(adjust_valid && adjust_de)?adjusted_rgb_raw:24'd0;
brightness_contrast_adjust #(.SIDE_WIDTH(48)) u_picture_adjust(
 .clk(video_clk),.rst(rst_video),.rgb_in(vout_data),.brightness(brightness_frame),.contrast(contrast_frame),
 .side_in({hs,vs,de,video_x,ring_y,pixel_descriptor,transition_level,transition_wipe,display_valid,audio_enable}),
 .rgb_out(adjusted_rgb_raw),.side_out(adjust_side));
video_transition_pixels u_video_transition_pixels(
    .level(adjust_level), .wipe_active(adjust_wipe), .de(adjust_de), .pixel_x(adjust_x), .rgb_in(adjusted_rgb), .rgb_out(transition_rgb)
);

// S1 separates ownership of each FIFO; the established burst interlock stays.
media_thumbnail_loader #(.WRITE_V_FLIP(1),.FRAME_WIDTH(640),.FRAME_HEIGHT(480)) u_frame_loader(
    .rst(rst_mem),.mem_clk(ext_mem_clk),.write_clk(sd_card_clk),.write_rst(rst_sd),
    .Sdr_init_done(Sdr_init_done),.Sdr_init_ref_vld(Sdr_init_ref_vld),.Sdr_busy(Sdr_busy),
    .App_rd_busy(frame_rd_busy || frame_refill_priority),.O_wr_busy(frame_wr_busy),
    .App_wr_en(App_wr_en),.App_wr_addr(App_wr_addr),.App_wr_din(App_wr_din),.App_wr_dm(App_wr_dm),
    .write_req(sd_card_write_req),.write_req_ack(sd_card_write_req_ack),
    .write_cancel_req(write_cancel_req),.write_cancel_ack(write_cancel_ack),
    .write_finish(frame_write_finish),.source_done(source_frame_done),.source_error(source_frame_error),
    .error_toggle(frame_error_toggle),.memory_error(frame_memory_error),
    .write_addr_0(BUF0_ADDR),.write_addr_1(BUF1_ADDR),.write_addr_2(BUF2_ADDR),.write_addr_3(BUF3_ADDR),
    .write_addr_index(write_buf_idx),.write_len(FRAME_PIXELS),
    .write_en(sd_card_write_en),.write_data(sd_card_write_data),.write_ready(frame_write_ready)
);
media_frame_reader #(.PREVIEW_ENABLE(1)) u_frame_reader(
    .pixel_descriptor(pixel_descriptor),
    .rst(rst_mem),.mem_clk(ext_mem_clk),.read_clk(video_clk),.read_rst(rst_video),
    .Sdr_init_done(Sdr_init_done),.Sdr_init_ref_vld(Sdr_init_ref_vld),.Sdr_busy(Sdr_busy),
    .App_wr_busy(frame_wr_busy),.O_rd_busy(frame_rd_busy),.refill_priority(frame_refill_priority),
    .App_rd_en(App_rd_en),.App_rd_addr(App_rd_addr),.Sdr_rd_en(Sdr_rd_en),.Sdr_rd_dout(Sdr_rd_dout),
    .read_req(video_read_req),.read_req_ack(video_read_req_ack),.read_finish(),
    .display_commit_request(display_commit_request),.display_commit_ack(display_commit_ack),
    .preview_request(preview_request),.preview_ack(preview_ack),.preview_descriptor(preview_descriptor),
    .read_addr_0(BUF0_ADDR),.read_addr_1(BUF1_ADDR),.read_addr_2(BUF2_ADDR),.read_addr_3(BUF3_ADDR),
    .read_addr_index(disp_buf_idx),.read_len(FRAME_PIXELS),
    .read_en(video_read_en),.display_valid(display_valid),.read_data(video_read_data),
    .underflow(frame_underflow),.reader_error(frame_reader_error)
);

sdram U3(
    .Clk               (ext_mem_clk),
    .Clk_sft           (ext_mem_clk_sft),
    .Rst               (rst_mem),
    .Sdr_init_done     (Sdr_init_done),
    .Sdr_init_ref_vld  (Sdr_init_ref_vld),
    .Sdr_busy          (Sdr_busy),
    .App_wr_en         (App_wr_en),
    .App_wr_addr       (App_wr_addr),
    .App_wr_dm         (App_wr_dm),
    .App_wr_din        (App_wr_din),
    .App_rd_en         (App_rd_en),
    .App_rd_addr       (App_rd_addr),
    .Sdr_rd_en         (Sdr_rd_en),
    .Sdr_rd_dout       (Sdr_rd_dout)
);

// S8: melody changes only after the display handoff has completed.
media_commit_cdc u_media_commit_cdc (
 .src_clk(sd_card_clk), .dst_clk(video_clk), .src_rst(rst_sd), .dst_rst(rst_video),
 .src_image(committed_image), .src_valid(committed_valid), .src_ready(committed_ready),
 .media_id(audio_image), .media_update(audio_update), .media_enable(audio_enable)
);

wire ring_frame_start, ring_tap_valid;
wire signed [15:0] ring_tap_left,ring_tap_right;
wire [6:0] ring_bar_index;
wire [4:0] ring_bar_height;
wire ring_hs,ring_vs,ring_de;
wire [9:0] ring_x;
wire [23:0] ring_rgb;
wire thumb_valid,thumb_border;
wire [23:0] preview_rgb=adjust_preview ? (thumb_border ? 24'hffff00 : thumb_valid ? adjusted_rgb : 24'd0) : transition_rgb;
thumbnail_layout u_thumbnail_layout(.in_de(adjust_de),.pixel_x(adjust_x),.pixel_y(adjust_y),
 .focus_index(adjust_descriptor[16:15]),.image_count(adjust_descriptor[14:12]),.image_complete(adjust_descriptor[11:8]),
 .thumb_de(thumb_valid),.source_index(),.source_x(),.source_y(),.focus_border(thumb_border));
osd_pixel_position u_ring_position(.clk(video_clk),.rst(rst_video),.vs(vs),.de(de),
 .line_y(ring_y),.frame_start(ring_frame_start),.first_active());
generate if(AUDIO_VIS_ENABLE) begin:g_audio_vis
 audio_ring_levels u_levels(.clk(video_clk),.rst(rst_video),.frame_start(ring_frame_start),
  .pcm_valid(ring_tap_valid),.pcm_left(ring_tap_left),.pcm_right(ring_tap_right),
  .bar_index(ring_bar_index),.bar_height(ring_bar_height));
end else begin:g_no_audio_vis
 assign ring_bar_height=5'd0;
end endgenerate
audio_ring_overlay #(.ENABLE(AUDIO_VIS_ENABLE)) u_audio_ring(
 .clk(video_clk),.rst(rst_video),.hs(adjust_hs),.vs(adjust_vs),.de(adjust_de),.enable(adjust_audio && !adjust_preview && !scene_on),
 .pixel_x(adjust_x),.pixel_y(adjust_y),.rgb_in(preview_rgb),.bar_height(ring_bar_height),
 .bar_index(ring_bar_index),.hs_out(ring_hs),.vs_out(ring_vs),.de_out(ring_de),.x_out(ring_x),.rgb_out(ring_rgb));

reg [1:0] preview_after_ring;
always @(posedge video_clk or posedge rst_video)
 if(rst_video)preview_after_ring<=0;else preview_after_ring<={preview_after_ring[0],adjust_preview};
// M5 scene mode (not in the thumbnail view): status text off, scene OSD on.
wire scene_vis=scene_on && !preview_after_ring[1];
wire [23:0] parameter_rgb;
wire parameter_glyph_active;
adjust_osd_overlay #(.ENABLE(OSD_ENABLE)) u_parameter_osd(
 .clk(video_clk),.rst(rst_video),.vs(ring_vs),.de(ring_de),.pixel_x(ring_x),.rgb_in(scene_vis ? ring_rgb : osd_rgb),
 .mode(adjust_mode),.selected(adjust_selected),.brightness(brightness_frame),.contrast(contrast_frame),
 .volume_level(volume_frame),.rgb_out(parameter_rgb),.active(parameter_glyph_active),
 .speed(speed_frame),.speed_visible(scene_on));

osd_status_cdc u_osd_status_cdc (
    .src_clk(sd_card_clk), .src_rst(rst_sd),
    .src_auto(auto_play_indicator), .src_error(osd_error_src),
    .dst_clk(video_clk), .dst_rst(rst_video),
    .dst_auto(osd_auto_pixel), .dst_error(osd_error_pixel)
);
// AUTO/error: acknowledged SD-domain mailbox. Image ID/valid: existing pixel
// domain media commit. Status snapshots at first active pixel after blanking.
// OSD uses the ring's two-cycle-delayed video bundle throughout.
status_osd_overlay #(.OSD_ENABLE(OSD_ENABLE)) u_status_osd (
    .clk(video_clk), .rst(rst_video), .vs(ring_vs), .de(ring_de), .pixel_x(ring_x),
    .rgb_in(ring_rgb), .image_index(audio_image), .image_valid(audio_enable),
    .auto_enabled(osd_auto_pixel), .error_code(osd_error_pixel), .rgb_out(osd_rgb),
    .active(status_glyph_active)
);
// FONT.BIN/TEXT.BIN BRAMs: written by the scan, read by the subtitle (outside
// scene mode) and the scene OSD.
(* ASYNC_REG = "TRUE" *) reg [1:0] font_ok_sync,text_ok_sync;
always @(posedge video_clk or posedge rst_video)
 if(rst_video)begin font_ok_sync<=0;text_ok_sync<=0;end
 else begin font_ok_sync<={font_ok_sync[0],font_loaded_sd};text_ok_sync<={text_ok_sync[0],text_loaded_sd};end
wire font_ok=font_ok_sync[1],text_ok=text_ok_sync[1];
wire [10:0] scroll_font_addr,scene_font_addr;wire [11:0] scene_text_addr;
wire [15:0] font_data;wire [7:0] text_data;
bin_to_bram_loader u_bin_loader(.wr_clk(sd_card_clk),.bin_wr(bin_wr),.bin_sel(bin_sel),.bin_addr(bin_addr),.bin_data(bin_data),
 .rd_clk(video_clk),.font_addr(scene_on ? scene_font_addr : scroll_font_addr),.font_data(font_data),
 .text_addr(scene_text_addr),.text_data(text_data));
scroll_text_overlay #(.ENABLE(OSD_ENABLE && SCROLL_ENABLE), .CN_ENABLE(1), .RUNTIME_ENABLE(1), .BRAM_FONT(1)) u_scroll_osd (
 .clk(video_clk),.rst(rst_video),.vs(ring_vs),.de(ring_de),.pixel_x(ring_x),.image_valid(audio_enable),
 .rgb_in(parameter_rgb),.rgb_out(scroll_rgb),.active(scroll_glyph_active),
 .runtime_text(sub_text_pixel),.runtime_length(sub_length_pixel),
 .runtime_enable(sub_enable_pixel && !preview_after_ring[1] && !scene_on),.runtime_text_changed(sub_text_changed),
 .font_addr(scroll_font_addr),.font_data(font_data),.font_valid(font_ok)
);
timestamp_osd #(.ENABLE(OSD_ENABLE && TIMESTAMP_ENABLE)) u_timestamp_osd(
 .clk(video_clk),.rst(rst_video),.vs(ring_vs),.de(ring_de),.pixel_x(ring_x),
 .rgb_in(scroll_rgb),.rgb_out(timestamp_rgb),.active(timestamp_glyph_active));
osd_alpha_band #(.ENABLE(OSD_ENABLE && BAND_ENABLE), .RUNTIME_ENABLE(1)) u_osd_band(
 .clk(video_clk),.rst(rst_video),.vs(ring_vs),.de(ring_de),.pixel_x(ring_x),
 .rgb_in(timestamp_rgb),.glyph_active(parameter_glyph_active || (status_glyph_active && !scene_vis) || scroll_glyph_active || timestamp_glyph_active),
 .rgb_out(band_rgb),.active(),.subtitle_enable(sub_enable_pixel && !preview_after_ring[1] && !scene_on && sub_length_pixel!=0)
);
wire [23:0] scene_rgb;
scene_osd u_scene_osd(.clk(video_clk),.rst(rst_video),.vs(ring_vs),.de(ring_de),.pixel_x(ring_x),.lead_x(adjust_x),
 .rgb_in(band_rgb),.rgb_plain(timestamp_rgb),.scene(scene_vis),.warn(warn_on),.stage(scene_stage),
 .t_now(hazard_t_now),.frame_cnt(hazard_frame_cnt),.font_ok(font_ok),.text_ok(text_ok),
 .font_addr(scene_font_addr),.font_data(font_data),.text_addr(scene_text_addr),.text_data(text_data),.rgb_out(scene_rgb));
wire pcm_valid, pcm_ready, pcm_overflow, hdmi_sequence_error;
wire signed [15:0] pcm_left, pcm_right;
pcm_media_tone #(.FIXED_VOLUME(128)) u_pcm_clock (
    .clk(video_clk), .rst_n(~rst_video), .enable(audio_enable),
    .media_id(audio_image), .media_update(audio_update), .volume(8'd128),
    .sample_valid(pcm_valid), .sample_ready(pcm_ready),
    .sample_left(pcm_left), .sample_right(pcm_right), .blip_active(), .overflow(pcm_overflow)
);
wire mixed_valid,mixed_ready;
wire signed [15:0] mixed_left,mixed_right;
audio_source_mux u_audio_source_mux(
 .clk(video_clk),.rst_n(!rst_video),
 .wav_valid(bgm_valid),.wav_ready(bgm_ready),.wav_left(bgm_left),.wav_right(bgm_right),.wav_active(bgm_active),
 .arp_valid(pcm_valid),.arp_ready(pcm_ready),.arp_left(pcm_left),.arp_right(pcm_right),
 .out_ready(mixed_ready),.out_valid(mixed_valid),.out_left(mixed_left),.out_right(mixed_right));
wire volume_valid,volume_ready;
wire signed [15:0] volume_left,volume_right;
pcm_master_volume u_master_volume(.clk(video_clk),.rst(rst_video),.volume_level(volume_frame),.fade_mute(fade_mute),
 .in_valid(mixed_valid),.in_ready(mixed_ready),.in_left(mixed_left),.in_right(mixed_right),
 .out_valid(volume_valid),.out_ready(volume_ready),.out_left(volume_left),.out_right(volume_right));
media_hdmi_audio_bridge u_media_hdmi_audio_bridge (
    .pixel_clk(video_clk), .pixel_rst_n(~rst_video),
    .video_hsync(ring_hs), .video_vsync(ring_vs), .video_de(ring_de),
    .video_x(ring_x), .video_rgb(scene_rgb),

    .select_media(1'b1), .test_valid(1'b0), .test_ready(),
    .test_left(16'sd0), .test_right(16'sd0),
    .media_valid(volume_valid), .media_ready(volume_ready),
    .media_left(volume_left), .media_right(volume_right),
    .channel0_symbol(tmds_ch0_data), .channel1_symbol(tmds_ch1_data),
    .channel2_symbol(tmds_ch2_data), .sequence_error(hdmi_sequence_error),
    .pcm_tap_valid(ring_tap_valid), .pcm_tap_left(ring_tap_left), .pcm_tap_right(ring_tap_right)
);
assign tmds_clk_data = 10'b1111100000; // Serialized bit 0 first by existing PHY.
assign HDMI_DDC_SCL = 1'bz;
assign HDMI_DDC_SDA = 1'bz;

hdmi_phy_wrapper #(
    .DEVICE ( "EG" )
) u_hdmi2phy_wrapper(
    .I_pixel_clk        (video_clk),
    .I_serial_clk       (hdmi_5x_clk),
    .I_rst              (rst_video),
    .I_serial_rst       (rst_serial),
    .I_tmds_channel_0   (tmds_ch0_data),
    .I_tmds_channel_1   (tmds_ch1_data),
    .I_tmds_channel_2   (tmds_ch2_data),
    .I_tmds_channel_clk (tmds_clk_data),
    .O_tmds_ch0_p       (HDMI_D0_P),
    .O_tmds_ch1_p       (HDMI_D1_P),
    .O_tmds_ch2_p       (HDMI_D2_P),
    .O_tmds_clk_p       (HDMI_CLK_P)
);

endmodule
