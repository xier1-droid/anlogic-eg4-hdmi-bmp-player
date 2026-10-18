`timescale 1ns/1ps
// Actual BMP parser and player; only SD sectors, memory completion and display ack modeled.
module tb_timeout_control;
    reg clk=0; always #5 clk=~clk;
    reg rst=1;
    reg stall=0,hide_end=0;
    integer scan_errors=0;
    always @(posedge clk) if(rst)scan_errors=0;else if(dut.bmp_scan_error)scan_errors=scan_errors+1;
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
    sd_card_bmp #(.CLK_FREQ_HZ(1000),.SCAN_MAX_SECTOR(3),.AUTO_PLAY_MS(100),.LOAD_TIMEOUT_MS(32)) dut(
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
        force dut.sd_sec_read_data_valid=dv && !stall;
        force dut.sd_sec_read_end=ending && !stall && !hide_end;
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
    task tick(input integer n);repeat(n)@(negedge clk);endtask
    task reset_all;
      begin
        wait(!card_busy);rst=1;stall=0;hide_end=0;hold_ack=0;hold_finish=0;
        hold_commit=0;inject_old_finish=0;tick(6);rst=0;
      end
    endtask
    task next_key;
      begin force dut.media_next_request=1;tick(1);release dut.media_next_request;end
    endtask
    task boot;begin reset_all();wait(valid);tick(8);end endtask
    integer old_commits,old_starts;
    reg [1:0] old_idx,old_buf;
    task save_display;
      begin old_commits=commits;old_starts=starts;old_idx=dut.img_idx;old_buf=db;end
    endtask
    task check_stopped;
      begin
        wait(dut.timeout_stopped);tick(4);
        if(code!=4'hf||!valid||commits!=old_commits||dut.img_idx!=old_idx||db!=old_buf||starts!=old_starts+1)
          $fatal(1,"timeout changed old display or retried");
        stall=0;hide_end=0;hold_ack=0;inject_old_finish=1;tick(1);inject_old_finish=0;
        next_key();force dut.media_auto_toggle_request=1;tick(1);release dut.media_auto_toggle_request;
        tick(1400);
        if(code!=4'hf||commits!=old_commits||dut.img_idx!=old_idx||db!=old_buf||
           starts!=old_starts+1||dut.display_commit_request!==commit_pipe[3]||dut.sd_sec_read||req)
          $fatal(1,"late data/finish or user request revived timeout");
      end
    endtask
    initial begin
      reset_all();stall=1;wait(dut.timeout_stopped);tick(6);
      if(code!=4'hf||valid||commits||starts||errors||scan_errors!=1||dut.img_found_count!=0)
        $fatal(1,"scan timeout must not create first-load event");
      stall=0;tick(1200);
      if(valid||commits||starts||code!=4'hf)$fatal(1,"late scan data committed");
      $display("PASS scan timeout displays F without first frame, load failure, or audio event");
      boot();save_display();stall=1;next_key();check_stopped();
      $display("PASS loaded header timeout keeps old bank/index/audio; no retry or new MAN/AUTO load");
      boot();save_display();hold_ack=1;next_key();check_stopped();
      $display("PASS write-ack timeout keeps old display; late ack and completion cannot submit");
      boot();save_display();next_key();wait(dut.bmp_read_m0.decoder.pixel_count==2);@(negedge clk);stall=1;
      check_stopped();
      $display("PASS partial-pixel timeout retains old display and masks late SD data");
      boot();save_display();next_key();wait(req);hide_end=1;
      wait(dut.bmp_read_m0.decoder.pixel_count==4);wait(ending);@(negedge clk);stall=1;check_stopped();
      $display("PASS memory can finish all pixels but missing SD end times out without display/audio");
      boot();if(code!=1||!valid||commits!=1||dut.timeout_stopped)$fatal(1,"reset did not recover");
      $display("PASS reset clears F and normal first-frame commit works again");
      $finish;
    end
    initial begin #3000000;$fatal(1,"timeout control watchdog");end
endmodule
