`timescale 1ns/1ps
// Actual BMP parser and player; only SD sectors, memory completion and display ack modeled.
module tb_bmp_recovery;
    reg clk=0; always #5 clk=~clk;
    reg rst=1;
    wire [7:0] data;
    wire dv, ending, card_busy;
    reg [3:0] bad=0;
    wire [3:0] code;
    wire valid,req,we,commit_req,committed;
    wire [1:0] db,wb,image_id;
    wire [31:0] rgb;
    reg [3:0] ack_pipe=0, commit_pipe=0;
    reg finish=0, hold_finish=0, pending_finish=0;
    integer pixel_count=0, starts=0, commits=0, successes=0, errors=0;
    integer attempt[0:3];
    reg [1:0] order[0:127];
    reg hold_commit=0;
    reg hold_ack=0,inject_old_finish=0;
    integer log_scan=0,log_done=0,log_load=0,log_commit=0,log_retry=0,log_skip=0;
    reg [1:0] expected_log_image;
    reg [31:0] expected_log_sector;
    reg expected_scan, expected_done, scan_seen=0, expected_load;
    reg [2:0] expected_error;
    always @(posedge clk) begin
        if(rst) begin
            log_scan=0;log_done=0;log_load=0;log_commit=0;log_retry=0;log_skip=0;scan_seen=0;
        end else begin
            expected_scan=dut.scan_start_pulse;
            expected_done=dut.scan_done && !scan_seen; scan_seen=dut.scan_done;
            expected_load=dut.load_start_pulse;
            expected_log_image=dut.load_idx;
            expected_log_sector=dut.sd_sec_read_addr;
            expected_error=dut.bmp_load_error ? dut.bmp_error : 0;
            #1;
            if(dut.diagnostics[44]!==expected_scan || dut.diagnostics[45]!==expected_done ||
               dut.diagnostics[46]!==expected_load) $fatal(1,"diagnostic scan/load event misclassified");
            if(dut.diagnostics[49] && (!valid || image_id!==dut.diagnostics[41:40]))
                $fatal(1,"COMMIT logged before actual display acknowledgement");
            if(dut.diagnostics[46] || dut.diagnostics[49] || dut.diagnostics[50]) begin
                if(dut.diagnostics[41:40]!==expected_log_image || dut.diagnostics[39:8]!==expected_log_sector)
                    $fatal(1,"wrong image/sector diagnostic snapshot");
            end
            if(dut.diagnostics[50] && dut.diagnostics[7:5]!==expected_error)
                $fatal(1,"diagnostic error must be parser result, not panel code");
            if(!dut.diagnostics[50] && dut.diagnostics[7:5]!==0) $fatal(1,"spurious diagnostic error");
            if(dut.diagnostics[44]) log_scan=log_scan+1;
            if(dut.diagnostics[45]) log_done=log_done+1;
            if(dut.diagnostics[46]) log_load=log_load+1;
            if(dut.diagnostics[49]) log_commit=log_commit+1;
            if(dut.diagnostics[47]) log_retry=log_retry+1;
            if(dut.diagnostics[48]) log_skip=log_skip+1;
        end
    end
    sd_card_bmp #(.CLK_FREQ_HZ(1000),.SCAN_MAX_SECTOR(3),.AUTO_PLAY_MS(100)) dut(
        .write_cancel_req(),.write_cancel_ack(1'b0),
        .sd_debug(),.diagnostics(),.sdram_ready(1'b1),
        .clk(clk),.rst(rst),.key1(1'b1),.key2(1'b1),.key4(1'b1),.mode(2'd0),
        .state_code(code),.combo_event_count(),.combo_debug_active(),.auto_play_indicator(),
        .bmp_width(16'd4),.bmp_height(16'd1),.display_valid(valid),
        .committed_image(image_id),.committed_valid(committed),.committed_ready(1'b1),
        .write_finish_toggle(finish),.display_commit_ack(commit_pipe[3]),.display_commit_request(commit_req),
        .write_buf_idx(wb),.disp_buf_idx(db),.write_req(req),.write_req_ack(ack_pipe[3]),
        .write_en(we),.write_data(rgb),.SD_nCS(),.SD_DCLK(),.SD_MOSI(),.SD_MISO(1'b1),.warn_mode(),.bin_wr(),.bin_sel(),.bin_addr(),.bin_data(),.font_loaded(),.text_loaded());
    sim_bmp_sectors #(.WIDTH(4),.HEIGHT(1),.FAT32(1)) card(.clk(clk),.rst(rst),
        .request(dut.sd_sec_read),.address(dut.sd_sec_read_addr),.bad_headers(bad),
        .data(data),.valid(dv),.sector_end(ending),.busy(card_busy));
    initial begin
        force dut.sd_init_failed=0; force dut.sd_sec_read_failed=0;
        force dut.sd_init_done=!rst;
        force dut.sd_sec_read_data=data;
        force dut.sd_sec_read_data_valid=dv;
        force dut.sd_sec_read_end=ending;
    end
    reg old_done=0,old_error=0;
    integer j;
    always @(posedge clk) begin
        if(rst) begin
            ack_pipe<=0;commit_pipe<=0;finish<=0;pixel_count<=0;pending_finish<=0;
            starts=0;commits=0;successes=0;errors=0;old_done=0;old_error=0;
            for(j=0;j<4;j=j+1) attempt[j]=0;
        end else begin
            if(!hold_ack) ack_pipe<={ack_pipe[2:0],req};
            if(!hold_commit) commit_pipe<={commit_pipe[2:0],commit_req};
            if(dut.load_start_pulse) begin
                order[starts]=dut.load_idx; starts=starts+1;
                attempt[dut.load_idx]=attempt[dut.load_idx]+1;
            end
            if(we) begin
                if(valid && wb==db && !dut.commit_pending) $fatal(1,"writing displayed bank");
                if(pixel_count==3) begin pixel_count<=0;pending_finish<=1;end
                else pixel_count<=pixel_count+1;
            end
            if(pending_finish && !hold_finish) begin finish<=~finish;pending_finish<=0;end
            if(inject_old_finish) finish<=~finish;
            if(dut.bmp_load_done) successes=successes+1;
            if(dut.bmp_load_error) errors=errors+1;
            if((old_done && dut.bmp_load_done)||(old_error && dut.bmp_load_error)||
                (dut.bmp_load_done && dut.bmp_load_error)) $fatal(1,"result pulse contract");
            old_done=dut.bmp_load_done;old_error=dut.bmp_load_error;
            if(committed) begin
                if(!valid || image_id!==dut.img_idx || commits>=successes) $fatal(1,"false audio/display event");
                commits=commits+1;
            end
        end
    end
    task tick(input integer n); repeat(n) @(negedge clk); endtask
    task boot;
        begin
            wait(!card_busy); rst=1;bad=0;hold_finish=0;hold_commit=0;tick(6);rst=0;
            wait(dut.scan_done); // Set bad mask before first load reads its header.
        end
    endtask
    task next_key;
        @(negedge clk);force dut.media_next_request=1;
        @(negedge clk);release dut.media_next_request;
    endtask
    task auto_key;
        @(negedge clk);force dut.media_auto_toggle_request=1;
        @(negedge clk);release dut.media_auto_toggle_request;
    endtask
    task drain;
        begin
            tick(3);
            wait(!dut.load_busy && !dut.ctrl_next_pending && !dut.ctrl_prev_pending);
            tick(8);
        end
    endtask
    integer before_starts,before_commits;
    reg [1:0] old_idx,old_buf;
    initial begin
        boot(); bad=1;
        wait(errors==1); @(negedge clk);bad=0;
        wait(valid);tick(8);
        if(attempt[0]!=2 || commits!=1 || dut.img_idx!=0 || code!=1) $fatal(1,"retry success attempts=%0d commits=%0d idx=%0d code=%0d errors=%0d",attempt[0],commits,dut.img_idx,code,errors);
        if(log_scan!=1 || log_done!=1 || log_load!=2 || log_commit!=1 || log_retry!=1 || log_skip!=0)
            $fatal(1,"retry diagnostic counts");
        $display("PASS initial header failure retries exactly once and clears sticky E on commit");

        before_starts=starts;before_commits=commits;old_idx=dut.img_idx;old_buf=db;
        bad=2;next_key();drain();tick(2500);
        if(starts!=before_starts+2 || commits!=before_commits || dut.img_idx!=old_idx || db!=old_buf || code!=4'he)
            $fatal(1,"MAN bounded failure/preservation");
        bad=0;hold_commit=1;next_key();wait(dut.commit_pending);tick(10);
        if(code!=4'he || commits!=before_commits || dut.img_idx!=old_idx) $fatal(1,"cleared error before display ack");
        hold_commit=0;drain();
        if(commits!=before_commits+1 || code!=2) $fatal(1,"manual retry after failure");
        $display("PASS MAN stops after two attempts, preserves bank/index/audio, and new manual request recovers");

        // First candidate permanently bad; advance once after its retry.
        boot();bad=1;wait(valid);tick(8);
        if(attempt[0]!=2 || attempt[1]!=1 || dut.img_idx!=1 || commits!=1) $fatal(1,"first-image skip");
        if(log_retry!=1 || log_skip!=1 || log_load!=3 || log_commit!=1) $fatal(1,"skip diagnostic counts");
        $display("PASS first image advances to next candidate only after one retry");

        boot();bad=15;wait(dut.first_load_failed);tick(3000);
        if(starts!=8 || valid || commits!=0 || code!=4'he) $fatal(1,"all first candidates failed");
        for(j=0;j<4;j=j+1) if(attempt[j]!=2) $fatal(1,"candidate retry budget");
        $display("PASS all first candidates fail: exactly eight attempts then stop without a frame");

        boot();wait(valid);tick(8);bad=2;auto_key();
        wait(dut.img_idx==2);auto_key();drain();
        if(attempt[1]!=2 || attempt[2]!=1 || commits!=2) $fatal(1,"AUTO skip");
        $display("PASS AUTO skips rejected candidate and commits next good image");

        before_starts=starts;before_commits=commits;old_idx=dut.img_idx;old_buf=db;
        bad=15;auto_key();wait(dut.auto_blocked);tick(3000);
        if(starts!=before_starts+8 || commits!=before_commits || db!=old_buf || dut.img_idx!=old_idx)
            $fatal(1,"AUTO all-failed stop");
        for(j=0;j<8;j=j+1) if(order[before_starts+j]!==((old_idx+1+j/2)%4)) $fatal(1,"AUTO candidate order");
        bad=0;auto_key();next_key();drain();
        if(commits!=before_commits+1 || dut.auto_blocked) $fatal(1,"manual recovery from AUTO stop");
        $display("PASS AUTO one-table budget and manual recovery with old display preserved");

        before_commits=commits;hold_finish=1;next_key();wait(dut.source_done_seen);tick(15);
        if(commits!=before_commits || !dut.load_busy) $fatal(1,"source success bypassed memory finish");
        hold_finish=0;drain();
        if(commits!=before_commits+1) $fatal(1,"late finish lost");
        $display("PASS explicit success waits for memory finish and display acknowledgement");
        before_commits=commits;hold_ack=1;hold_finish=1;next_key();wait(req);tick(3);
        inject_old_finish=1;tick(1);inject_old_finish=0;tick(8);
        if(dut.write_finish_seen)$fatal(1,"old finish accepted before new write handshake");
        hold_ack=0;wait(dut.source_done_seen);tick(12);
        if(commits!=before_commits || !dut.load_busy)$fatal(1,"stale finish released new frame");
        hold_finish=0;drain();
        if(commits!=before_commits+1)$fatal(1,"fresh write finish not accepted");
        $display("PASS stale finish before new write ack ignored; only current finish commits");
        if(log_scan!=1 || log_done!=1 || log_load!=starts || log_commit!=commits)
            $fatal(1,"normal flips generated spurious scan or lost commit");
        $display("PASS real parser/player diagnostic scan/load/retry/skip/commit counts, numeric errors, image and sector context");
        $finish;
    end
    initial begin #2000000;$fatal(1,"recovery watchdog");end
endmodule
