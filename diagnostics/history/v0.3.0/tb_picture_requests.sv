`timescale 1ns/1ps
// Actual controller + BMP reader; SD sectors and SDRAM acknowledgement are modeled.
module tb_picture_requests;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst = 1, key1 = 1, key2 = 1, key4 = 1, finish_toggle = 0;
    reg [1:0] mode = 0;
    reg ack = 0, init_done = 0, data_valid = 0, sector_end = 0;
    reg [3:0] ack_pipe = 0;
    reg [7:0] sector_data = 0;
    wire [3:0] code;
    wire valid, req, we;
    wire auto_indicator;
    wire commit_request;
    reg [3:0] commit_ack_pipe=0;
    reg hold_commit_ack=0;
    wire [31:0] pixel;
    wire [1:0] wb, db;
    integer pixels = 0, commits = 0;
    integer next_events = 0, prev_events = 0, toggle_events = 0;
    integer starts = 0;
    reg [1:0] started_idx [0:255];
    always @(posedge clk) if (!rst) begin
        if (dut.load_start_pulse) begin
            started_idx[starts] = dut.load_idx;
            starts = starts + 1;
        end
        if (dut.media_next_request) next_events = next_events + 1;
        if (dut.media_previous_request) prev_events = prev_events + 1;
        if (dut.media_auto_toggle_request) toggle_events = toggle_events + 1;
    end
    reg pixel_clk=0;
    always #19 pixel_clk=~pixel_clk;
    wire [1:0] committed_image, media_id;
    wire committed_valid, committed_ready, media_update, media_enable;
    integer sent=0, received=0, cues=0;
    reg [1:0] expected [0:255];
    media_commit_cdc cdc(.src_clk(clk),.dst_clk(pixel_clk),.src_rst(rst),.dst_rst(rst),
      .src_image(committed_image),.src_valid(committed_valid),.src_ready(committed_ready),
      .media_id(media_id),.media_update(media_update),.media_enable(media_enable));
    pcm_media_tone #(.CLOCK_HZ(480000)) audio_source(.clk(pixel_clk),.rst_n(!rst),
      .enable(media_enable),.media_update(media_update),.media_id(media_id),.volume(8'd128),
      .sample_valid(),.sample_ready(1'b1),.sample_left(),.sample_right(),.overflow(),.blip_active());
    always @(posedge clk) if (!rst && committed_valid && committed_ready) begin
      if (!valid || committed_image !== dut.img_idx || sent >= commits)
        $fatal(1,"audio event before actual display commit");
      expected[sent]=committed_image; sent=sent+1;
    end
    always @(posedge pixel_clk) if (!rst && media_update) begin
      if (received>=sent || media_id!==expected[received]) $fatal(1,"CDC lost/repeated/wrong image");
      received=received+1;
      #1;
      if (audio_source.blip_countdown!=4800) $fatal(1,"missing commit cue");
      cues=cues+1;
    end
    reg old_busy = 0;
    reg bad_header = 0;
    reg hold_finish = 0, finish_pending = 0;
    sd_card_bmp #(.CLK_FREQ_HZ(1000), .SCAN_MAX_SECTOR(4),
                  .SCAN_TARGET_COUNT(4), .AUTO_PLAY_MS(3000)) dut (
        .sdram_ready(1'b1),
        .clk(clk), .rst(rst), .key1(key1), .key2(key2), .key4(key4), .mode(mode),
        .state_code(code), .bmp_width(16'd4), .bmp_height(16'd1),
        .combo_event_count(), .combo_debug_active(),
        .auto_play_indicator(auto_indicator),
        .committed_image(committed_image),.committed_valid(committed_valid),.committed_ready(committed_ready),
        .display_valid(valid), .write_finish_toggle(finish_toggle),
        .display_commit_request(commit_request), .display_commit_ack(commit_ack_pipe[3]),
        .write_buf_idx(wb), .disp_buf_idx(db), .write_req(req),
        .write_req_ack(ack), .write_en(we), .write_data(pixel),
        .SD_nCS(), .SD_DCLK(), .SD_MOSI(), .SD_MISO(1'b1)
    ,.warn_mode(),.bin_wr(),.bin_sel(),.bin_addr(),.bin_data(),.font_loaded(),.text_loaded());
    initial begin
        force dut.sd_init_done = init_done;
        force dut.sd_sec_read_data = sector_data;
        force dut.sd_sec_read_data_valid = data_valid;
        force dut.sd_sec_read_end = sector_end;
    end
    function [7:0] bmp_byte(input integer pos);
        case (pos)
            0: bmp_byte = bad_header ? 0 : 8'h42;
            1: bmp_byte = 8'h4d;
            2: bmp_byte = 66; // 54-byte header + four RGB pixels
            10: bmp_byte = 54;
            14: bmp_byte = 40;
            18: bmp_byte = 4;
            22: bmp_byte = 1;
            26: bmp_byte = 1;
            28: bmp_byte = 24;
            default: bmp_byte = pos >= 54 && pos < 66 ? (8'h55 + dut.sd_sec_read_addr[3:0]) : 0;
        endcase
    endfunction
    // Model a sector transfer with gaps between bytes.
    integer b;
    initial forever begin
        @(negedge clk);
        if (!rst && dut.sd_sec_read) begin
            for (b = 0; b < 512; b = b + 1) begin
                sector_data = bmp_byte(b);
                data_valid = 1;
                @(negedge clk);
                data_valid = 0;
                @(negedge clk);
            end
            sector_end = 1;
            @(negedge clk);
            sector_end = 0;
            @(negedge clk);
        end
    end
    always @(posedge clk) begin
        if (rst) commit_ack_pipe <= 0;
        else if (!hold_commit_ack) commit_ack_pipe <= {commit_ack_pipe[2:0],commit_request};
            ack_pipe <= {ack_pipe[2:0], req};
            ack <= ack_pipe[3];
        if (rst) begin
            pixels <= 0;
            finish_toggle <= 0;
            old_busy <= 0;
            commits <= 0;
            finish_pending <= 0;
            ack_pipe <= 0;
        end else begin
            if (we) begin
                if (pixels == 3) begin
                    pixels <= 0;
                    finish_pending <= 1;
                end else pixels <= pixels + 1;
            end
            old_busy <= dut.load_busy;
            if (finish_pending && !hold_finish) begin
                finish_toggle <= ~finish_toggle;
                finish_pending <= 0;
            end
            if (dut.commit_pending && dut.commit_ack_sync[1] == commit_request && (!committed_valid || committed_ready))
                commits <= commits + 1;
        end
    end
    task tick(input integer n);
        repeat(n) @(negedge clk);
    endtask
    task next_key;
        key2 = 0; tick(25); key2 = 1; tick(25);
    endtask
    task drain;
        integer n;
        begin
            n = 0;
            while ((dut.load_busy || dut.u_media_player_control.next_pending || dut.u_media_player_control.previous_pending) && n < 15000) begin
                tick(1); n = n + 1;
            end
            if (n == 15000) $fatal(1, "requests did not drain");
            tick(2);
        end
    endtask
    task previous_key;
        key1 = 0; tick(25); key1 = 1; tick(25);
    endtask
    task toggle_key;
        key4 = 0; tick(25); key4 = 1; tick(25);
    endtask
    integer i, before_count, ne, pe, te, start_base;
    reg [1:0] saved_idx, saved_buf;
    initial begin
        tick(5); rst = 0; init_done = 1;
        wait(dut.scan_done);
        bad_header = 1; tick(1200);
        if (valid || dut.first_image_committed) $fatal(1, "bad first image was displayed");
        bad_header = 0;
        wait(valid); tick(3);
        if (auto_indicator !== 0) $fatal(1, "reset should select MAN");
        $display("PASS first image retries after header rejection and commits only on success");

        before_count = commits;
        next_key(); repeat(8) next_key(); drain();
        if (commits - before_count != 2) $fatal(1, "same direction did not coalesce");
        $display("PASS rapid KEY2 requests coalesce into current plus one pending load");

        before_count = commits; start_base = starts; saved_idx = dut.img_idx;
        next_key(); previous_key(); next_key();
        if (!dut.ctrl_prev_pending || !dut.ctrl_next_pending) $fatal(1, "opposite pending lost");
        drain();
        if (commits != before_count + 3 || starts != start_base + 3 ||
            started_idx[start_base] != ((saved_idx + 1) % 4) ||
            started_idx[start_base+1] != ((saved_idx + 2) % 4) ||
            started_idx[start_base+2] != ((saved_idx + 1) % 4) || dut.ctrl_auto_play_en)
            $fatal(1, "four-image next/next/previous priority failed");
        $display("PASS independent KEY1/KEY2 requests use committed index and next priority");

        // Four steps in each direction must return to the same displayed image.
        saved_idx = dut.img_idx;
        repeat(4) begin next_key(); drain(); end
        if (dut.img_idx != saved_idx) $fatal(1, "next wrap failed");
        repeat(4) begin previous_key(); drain(); end
        if (dut.img_idx != saved_idx) $fatal(1, "previous wrap failed");
        for (i=0; i<20; i=i+1) begin next_key(); next_key(); drain(); end
        $display("PASS four-image wrap and 20 rounds of back-to-back loads");

        saved_idx = dut.img_idx; saved_buf = db; before_count = commits;
        bad_header = 1; next_key(); tick(2500);
        if (dut.load_busy || !dut.bmp_ready || !valid || dut.img_idx != saved_idx ||
            db != saved_buf || commits != before_count)
            $fatal(1, "header rejection failed to preserve displayed image");
        repeat(3) next_key(); drain();
        if (commits != before_count || db != saved_buf) $fatal(1, "failed load committed");
        bad_header = 0; next_key(); drain();
        if (commits != before_count+1) $fatal(1, "recovery after rejection failed");
        before_count = commits;
        bad_header = 1; next_key(); next_key();
        // Wait for the failed request and its retry to be observed before
        // restoring valid header data; otherwise the test races the parser
        // and may accidentally turn both requests into successful loads.
        wait (dut.bmp_load_error);
        @(negedge clk);
        wait (dut.bmp_load_error);
        bad_header = 0;
        drain();
        // The first request retries once and the queued request is then
        // serviced, so this scenario produces two successful commits.
        if (commits != before_count+2 || db == saved_buf) $fatal(1, "pending request lost on failure");
        $display("PASS rejected headers preserve image and pending requests, then recover");

        before_count = commits; saved_buf = db;
        hold_finish = 1; next_key(); tick(2500);
        if (!dut.load_busy || !dut.source_done_seen || !dut.write_started_seen ||
            commits != before_count || db != saved_buf) $fatal(1, "write released early");
        hold_finish = 0; drain();
        if (commits != before_count+1) $fatal(1, "delayed write did not commit");
        $display("PASS real writes wait for SDRAM completion");

        ne = next_events; before_count = commits;
        key2 = 0; tick(2000); key2 = 1; tick(25); drain();
        if (next_events != ne+1 || commits != before_count+1) $fatal(1, "held KEY2 repeated");
        next_key(); drain();
        if (next_events != ne+2) $fatal(1, "KEY2 failed to rearm");
        pe = prev_events; te = toggle_events; before_count = commits;
        hold_finish = 1; next_key();
        key1 = 0; tick(2100); key1 = 1; tick(25);
        if (!dut.ctrl_prev_pending || prev_events != pe+1 || toggle_events != te)
            $fatal(1, "busy held KEY1 lost or repeated");
        hold_finish = 0; drain();
        if (commits != before_count+2) $fatal(1, "busy previous execution count");
        $display("PASS held direction keys fire once, rearm and queue while busy");

        // Mode changes gate new events, not requests already queued.
        before_count = commits; hold_finish = 1;
        next_key(); next_key(); previous_key(); mode = 1; tick(2);
        ne = next_events; pe = prev_events;
        next_key(); previous_key();
        if (next_events != ne || prev_events != pe || !dut.ctrl_next_pending || !dut.ctrl_prev_pending)
            $fatal(1, "mode change dropped queued requests or accepted new ones");
        hold_finish = 0; drain();
        if (commits != before_count+3) $fatal(1, "mode change prevented queued drain");
        for (i=1; i<4; i=i+1) begin
            mode = i; tick(2); before_count = starts;
            previous_key(); next_key(); tick(100);
            if (starts != before_count) $fatal(1, "non-picture mode generated direction load");
            te = toggle_events;
            key4 = 0; tick(2000); key4 = 1; tick(25);
            if (toggle_events != te+1 || !dut.ctrl_auto_play_en || !auto_indicator)
                $fatal(1, "KEY4 held toggle failed");
            toggle_key();
            if (toggle_events != te+2 || dut.ctrl_auto_play_en || auto_indicator)
                $fatal(1, "KEY4 release/repress failed");
        end
        mode=0; tick(2);
        $display("PASS all reserved modes gate new direction loads and KEY4 toggles once");

        // Toggle back to MAN while loading: do not cancel in-flight/queued requests.
        before_count = commits; hold_finish=1;
        next_key(); next_key(); toggle_key(); toggle_key();
        if (dut.ctrl_auto_play_en || !dut.load_busy || !dut.ctrl_next_pending)
            $fatal(1, "MAN transition cancelled requests");
        hold_finish=0; drain();
        if (commits != before_count+2) $fatal(1, "MAN transition load count");
        $display("PASS switching back to MAN preserves current and pending manual loads");

        // Align expiry with a REAL debounced KEY2 event; only the timer is positioned.
        toggle_key(); key2=0;
        wait(dut.media_next_request); @(negedge clk);
        dut.u_media_player_control.auto_count=2999;
        @(posedge clk); #1;
        if (dut.load_start_pulse || !dut.ctrl_next_pending)
            $fatal(1, "AUTO stole manual event cycle");
        @(negedge clk); key2=1; tick(25); drain(); toggle_key();
        if (dut.ctrl_auto_play_en) $fatal(1, "AUTO shutdown failed");
        $display("PASS AUTO expiry yields to real debounced direction press");

        // Arbitration-only collision: consume an old request and capture a new one.
        @(negedge clk); dut.u_media_player_control.next_pending=1;
        force dut.media_next_request=1;
        @(posedge clk); #1;
        if (!dut.load_start_pulse || !dut.ctrl_next_pending) $fatal(1, "same-cycle next lost");
        @(negedge clk); release dut.media_next_request; drain();
        @(negedge clk); dut.u_media_player_control.previous_pending=1;
        force dut.media_previous_request=1;
        @(posedge clk); #1;
        if (!dut.load_start_pulse || !dut.ctrl_prev_pending) $fatal(1, "same-cycle previous lost");
        @(negedge clk); release dut.media_previous_request; tick(2); drain();
        $display("PASS simultaneous pending consumption and new event capture");

        toggle_key(); key4=0;
        wait(dut.media_auto_toggle_request); @(negedge clk);
        dut.u_media_player_control.auto_count=2999;
        @(posedge clk); #1;
        if (dut.load_start_pulse || dut.ctrl_auto_play_en || dut.u_media_player_control.auto_count != 0)
            $fatal(1, "KEY4 at expiry did not cancel AUTO");
        @(negedge clk); key4=1; tick(25);
        $display("PASS KEY4 wins over AUTO expiry and returns to MAN");

        // Natural expiry, with mode changed before the edge accepting the request.
        toggle_key(); before_count=starts;
        wait(dut.u_media_player_control.auto_count==2999); @(negedge clk);
        mode=1; #1;
        if (dut.ctrl_request_accept) $fatal(1, "mode change still offered expired AUTO load");
        @(posedge clk); #1;
        if (dut.load_start_pulse || dut.u_media_player_control.auto_count != 0 || !dut.ctrl_auto_play_en)
            $fatal(1, "mode/expiry collision started a load or disabled AUTO");
        @(negedge clk); tick(2998);
        if (starts != before_count || dut.load_busy) $fatal(1, "AUTO restarted too early after mode change");
        wait(dut.load_start_pulse); tick(2);
        if (starts != before_count+1) $fatal(1, "AUTO did not resume in reserved mode");
        toggle_key(); drain(); mode=0; tick(2);
        $display("PASS mode change cancels coincident expiry and AUTO resumes after full interval");

        before_count=commits; start_base=starts; saved_idx=dut.img_idx;
        hold_commit_ack=1;
        next_key(); wait(dut.commit_pending); next_key(); tick(200);
        if (!dut.load_busy || dut.img_idx !== saved_idx || commits !== before_count ||
            starts !== start_base+1 || !dut.ctrl_next_pending)
            $fatal(1, "display wait released ownership or index");
        hold_commit_ack=0; drain();
        if (commits !== before_count+2 || starts !== start_base+2 ||
            started_idx[start_base] !== ((saved_idx+1)%4) ||
            started_idx[start_base+1] !== ((saved_idx+2)%4))
            $fatal(1, "display ack failed to release queued request at new index");
        $display("PASS delayed display ack preserves old image and drains pending after adoption");
        tick(100);
        if (sent!=commits || received!=commits || cues!=commits) $fatal(1,"commit/event/cue count mismatch");
        $display("PASS S8 %0d display commits delivered once with matching picture and cue",commits);
        $finish;
    end
    initial begin #3000000; $fatal(1, "simulation watchdog"); end
endmodule
