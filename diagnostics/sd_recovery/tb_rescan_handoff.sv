`timescale 1ns/1ps
// Real BMP parser, application and frame read/write controllers. Behavioral SD
// sectors, dual-clock FIFOs and SDRAM data port replace vendor/SPI implementations.
module tb_rescan_handoff;
    parameter integer PIX_HALF = 17;
    parameter integer SOURCE_GAP = 2;
    reg clk=0, mem_clk=0, pix_clk=0, rst=1;
    always #5 clk=~clk;
    always #7 mem_clk=~mem_clk;
    initial begin #3; forever #(PIX_HALF) pix_clk=~pix_clk; end
    wire valid, req, we, ack, wr_finish;
    wire cancel_req,cancel_ack;
    reg key2=1;
    reg [1:0] mode=0;
    reg no_card=0,no_images=0;
    integer card_generation=0;
    wire [31:0] data;
    wire [1:0] wb, db;
    wire commit_request, commit_ack;
    wire [3:0] code;
    reg finish_toggle=0;
    always @(posedge mem_clk) if(rst) finish_toggle<=0; else if(wr_finish) finish_toggle<=~finish_toggle;
    sd_card_bmp #(.CLK_FREQ_HZ(1000), .AUTO_PLAY_MS(3000), .SCAN_MAX_SECTOR(27)) dut (
        .write_cancel_req(cancel_req),.write_cancel_ack(cancel_ack),
        .sd_debug(),.diagnostics(),.sdram_ready(1'b1),
        .clk(clk),.rst(rst),.key1(1'b1),.key2(key2),.key4(1'b1),.mode(mode),
        .state_code(code),.combo_event_count(),.combo_debug_active(),.auto_play_indicator(),
        .bmp_width(16'd32),.bmp_height(16'd32),.display_valid(valid),.committed_image(),.committed_valid(),.committed_ready(1'b1),
        .write_finish_toggle(finish_toggle),.write_buf_idx(wb),.disp_buf_idx(db),
        .display_commit_request(commit_request),.display_commit_ack(commit_ack),
        .write_req(req),.write_req_ack(ack),.write_en(we),.write_data(data),
        .SD_nCS(),.SD_DCLK(),.SD_MOSI(),.SD_MISO(1'b1)
    ,.warn_mode(),.bin_wr(),.bin_sel(),.bin_addr(),.bin_data(),.font_loaded(),.text_loaded());
    reg [7:0] sector_data=0;
    reg sector_valid=0,sector_end=0,sector_failed=0;
    reg fail_final_crc=0;
    integer short_attempts=0,short_sector=2,short_bytes=100;
    integer image,base,b,gap,limit_bytes;
    reg truncate_now;
    integer attempts=0,errors=0,commits=0;
    integer diag_rescans=0,diag_inits=0,diag_fails=0,diag_recovered=0;
    reg expected_rescan,expected_init,expected_fail,seen_init=0,seen_fail=0;
    always @(posedge clk) begin
        if(rst) begin
            diag_rescans=0;diag_inits=0;diag_fails=0;diag_recovered=0;seen_init=0;seen_fail=0;
        end else begin
            expected_rescan=dut.rescan_event && !dut.recovery_active;
            expected_init=dut.sd_init_done && !seen_init;
            expected_fail=dut.sd_init_failed && !seen_fail;
            seen_init=dut.sd_init_done;seen_fail=dut.sd_init_failed;
            #1;
            if(dut.diagnostics[51]!==expected_rescan || dut.diagnostics[42]!==expected_init ||
               dut.diagnostics[43]!==expected_fail) $fatal(1,"rescan/init diagnostic not actual event");
            if(dut.diagnostics[51]) diag_rescans=diag_rescans+1;
            if(dut.diagnostics[42]) diag_inits=diag_inits+1;
            if(dut.diagnostics[43]) begin
                diag_fails=diag_fails+1;
                if(dut.diagnostics[7:5]!=2) $fatal(1,"init error code");
            end
            if(dut.diagnostics[56]) diag_recovered=diag_recovered+1;
        end
    end
    initial begin
        force dut.sd_init_failed=no_card && !dut.sd_local_rst;
        force dut.sd_init_done=!dut.sd_local_rst && !no_card;
        force dut.sd_sec_read_data=sector_data;
        force dut.sd_sec_read_data_valid=sector_valid;
        force dut.sd_sec_read_end=sector_end;
        force dut.sd_sec_read_failed=sector_failed;
    end
    `include "diagnostics/fat32/sim_fat32_layout.vh"
    function [7:0] byte_at(input integer pos,input integer id);
        begin
            byte_at=0;
            case(pos)
                0:byte_at=no_images ? 0 : "B";1:byte_at="M";
                2,3,4,5:byte_at=32'd3126>>(8*(pos-2));
                10:byte_at=54;14:byte_at=40;18:byte_at=32;22:byte_at=32;26:byte_at=1;28:byte_at=24;
                default:if(pos>=54 && pos<3126)byte_at=id+1+card_generation*16;
            endcase
        end
    endfunction
    integer reset_epoch=0,transaction_epoch;
    always @(posedge dut.parser_rst) reset_epoch=reset_epoch+1;
    initial forever begin
        @(negedge clk);
        if(!rst && dut.sd_sec_read) begin
            transaction_epoch=reset_epoch;
            image=(dut.sd_sec_read_addr-1026)/7;base=((dut.sd_sec_read_addr-1026)%7)*512;
            truncate_now=(dut.bmp_read_m0.state==10 && base==short_sector*512 && short_attempts>0);
            limit_bytes=truncate_now ? short_bytes : 512;
            if(truncate_now)short_attempts=short_attempts-1;
            for(b=0;b<limit_bytes && !dut.parser_rst && transaction_epoch==reset_epoch;b=b+1)begin
                sector_data=(dut.sd_sec_read_addr<=1025)?fat32_metadata(dut.sd_sec_read_addr,b,3126,4):byte_at(base+b,image);sector_valid=1;@(negedge clk);sector_valid=0;
                for(gap=1;gap<SOURCE_GAP;gap=gap+1)@(negedge clk);
            end
            sector_failed=fail_final_crc && base==3072 && dut.bmp_read_m0.state==10;
            sector_end=!dut.parser_rst && transaction_epoch==reset_epoch && !sector_failed;
            @(negedge clk);sector_end=0;sector_failed=0;@(negedge clk);
        end
    end
    always @(posedge clk)if(!rst)begin
        if(dut.load_start_pulse)attempts=attempts+1;
        if(dut.bmp_load_error)begin
            errors=errors+1;
            
        end
        if(dut.committed_valid)commits=commits+1;
    end
    reg read_req=0, read_en=0;
    wire read_ack, read_finish, rd_en, wr_en;
    wire [20:0] rd_addr, wr_addr;
    wire [31:0] wr_data, read_data;
    reg [2:0] rd_pipe=0;
    reg [31:0] rd_data_pipe[0:2];
    reg [31:0] memory[0:2047];
    frame_read_write #(.BURST_SIZE(64),.FRAME_WIDTH(32),.FRAME_HEIGHT(32)) frame (
        .rst(rst),.mem_clk(mem_clk),.Sdr_init_done(!rst),.Sdr_init_ref_vld(1'b0),.Sdr_busy(1'b0),
        .App_rd_en(rd_en),.App_rd_addr(rd_addr),.Sdr_rd_en(rd_pipe[2]),.Sdr_rd_dout(rd_data_pipe[2]),
        .read_clk(pix_clk),.read_req(read_req),.read_req_ack(read_ack),.read_finish(read_finish),
        .read_addr_0(21'd0),.read_addr_1(21'd1024),.read_addr_2(21'd0),.read_addr_3(21'd0),
        .read_addr_index(db),.read_len(21'd1024),.read_en(read_en),.read_data(read_data),
        .display_commit_request(commit_request),.display_commit_ack(commit_ack),
        .App_wr_en(wr_en),.App_wr_addr(wr_addr),.App_wr_din(wr_data),.App_wr_dm(),
        .write_cancel_req(cancel_req),.write_cancel_ack(cancel_ack),.write_clk(clk),.write_req(req),.write_req_ack(ack),.write_finish(wr_finish),
        .write_addr_0(21'd0),.write_addr_1(21'd1024),.write_addr_2(21'd0),.write_addr_3(21'd0),
        .write_addr_index(wb),.write_len(21'd1024),.write_en(we),.write_data(data)
    );
    integer i, frame_reads=0, loaded=0, collision_count=0, torn_frames=0;
    reg read_in_progress=0, active_bank=0, ack_d=0;
    always @(posedge mem_clk) begin
        if(rst) begin
            rd_pipe<=0; read_in_progress<=0; ack_d<=0;
        end else begin
            rd_pipe <= {rd_pipe[1:0],rd_en};
            if(rd_en) rd_data_pipe[0]<=memory[rd_addr];
            rd_data_pipe[1]<=rd_data_pipe[0]; rd_data_pipe[2]<=rd_data_pipe[1];
            if(wr_en) begin
                if(cancel_ack || frame.write_fifo_aclr) $fatal(1,"write continued after cancel clear/ack");
                memory[wr_addr]<=wr_data;
                if(valid && read_in_progress && (wr_addr>=1024)==active_bank)
                    collision_count=collision_count+1;
            end
            ack_d<=read_ack;
            if(ack_d && !read_ack) begin
                read_in_progress<=1;
                active_bank <= rd_addr>=1024;
                frame_reads=frame_reads+1;
            end
            if(read_finish) read_in_progress<=0;
            if(wr_finish) loaded=loaded+1;
        end
    end
    // Pixel domain: periodic vertical blank, actual FIFO consumption.
    reg [1:0] ack_sync=0;
    always @(posedge pix_clk) ack_sync <= rst ? 0 : {ack_sync[0],read_ack};
    integer x;
    reg [31:0] first_pixel;
    reg changed, frame_visible;
    initial begin
        read_req=0; read_en=0;
        wait(!rst);
        forever begin
            @(negedge pix_clk); read_req=1;
            wait(ack_sync[1]); @(negedge pix_clk); read_req=0;
            repeat(60) @(negedge pix_clk);
            changed=0; frame_visible=valid;
            for(x=0;x<1024;x=x+1) begin
                read_en=1;
                @(posedge pix_clk); #1;
                if(x==0) first_pixel=read_data;
                else if(frame_visible && read_data!==first_pixel) changed=1;
                @(negedge pix_clk);
            end
            read_en=0;
            if(frame_visible && changed) torn_frames=torn_frames+1;
            repeat(120) @(negedge pix_clk);
        end
    end
    task next_request;
        @(negedge clk); force dut.media_next_request=1;
        @(negedge clk); release dut.media_next_request;
    endtask
    integer before_commits,before_attempts,before_errors;
    reg [1:0] saved_idx,saved_bank;
    task drain;
        begin
            repeat(4)@(negedge clk);
            wait(!dut.load_busy && !dut.ctrl_next_pending);
            repeat(8)@(negedge clk);
        end
    endtask
    task rescan;
        begin
            @(negedge clk); force dut.rescan_event=1;
            @(negedge clk); release dut.rescan_event;
            wait(dut.recovery_active);
        end
    endtask
    task recovered(input integer expected_commits);
        begin
            wait(!dut.recovery_active); repeat(12) @(negedge clk);
            if(!valid || dut.img_idx!=0 || commits!=expected_commits || dut.ctrl_auto_play_en ||
               dut.ctrl_next_pending || dut.ctrl_prev_pending)
                $fatal(1,"recovery first image/MAN/audio contract");
            if(collision_count || torn_frames) $fatal(1,"old display was modified");
        end
    endtask
    initial begin
        for(i=0;i<2048;i=i+1)memory[i]=0;
        no_card=1; mode=3;
        repeat(5)@(negedge clk);rst=0;
        repeat(30)@(negedge clk);
        if(valid || code!=15) $fatal(1,"no-card boot must stay black with F");
        no_card=0; key2=0;
        wait(dut.recovery_active); repeat(2100)@(negedge clk);
        key2=1; repeat(30)@(negedge clk); mode=0;
        wait(valid);repeat(8)@(negedge clk);
        if(commits!=1 || dut.ctrl_next_pending) $fatal(1,"long hold/release created extra load");
        $display("PASS no-old-image black boot and real KEY2 recovery in reserved mode");
        before_commits=commits;
        rescan(); recovered(before_commits+1);
        $display("PASS same-card rescan with old display");
        next_request();wait(wr_en);before_commits=commits;card_generation=1;
        rescan(); recovered(before_commits+1);
        if(memory[db*1024]!==32'h11111100) $fatal(1,"new card first pixels missing");
        $display("PASS cancel during pixel write, new card first frame and single audio");
        // A second request during active recovery must be discarded.
        before_commits=commits;rescan();
        wait(dut.recovery_phase==4 && dut.bmp_read_m0.state==1);
        @(negedge clk);force dut.rescan_event=1;
        @(negedge clk);release dut.rescan_event;
        recovered(before_commits+1);
        $display("PASS scan recovery ignores duplicate without queue");
        // Start a request while the display ownership transfer is outstanding.
        next_request();wait(dut.commit_pending);before_commits=commits;
        rescan(); recovered(before_commits+1);
        $display("PASS pending display handshake settles before reuse");
        before_commits=commits;saved_bank=db;no_card=1;rescan();
        wait(!dut.recovery_active);repeat(15)@(negedge clk);
        if(!valid || db!=saved_bank || code!=15 || commits!=before_commits)
            $fatal(1,"no card must preserve old image and show F valid=%b bank=%d saved=%d code=%h commits=%d prior=%d",valid,db,saved_bank,code,commits,before_commits);
        no_card=0;rescan(); recovered(before_commits+1);
        $display("PASS no-card failure and retry preserve display");
        before_commits=commits;no_images=1;saved_bank=db;rescan();
        wait(!dut.recovery_active);repeat(15)@(negedge clk);
        if(!valid || db!=saved_bank || code!=14 || commits!=before_commits)
            $fatal(1,"no images must preserve old image and show E");
        no_images=0;rescan();recovered(before_commits+1);
        before_commits=commits;saved_bank=db;fail_final_crc=1;
        next_request();wait(dut.timeout_stopped);repeat(20)@(negedge clk);
        if(db!=saved_bank || commits!=before_commits || !valid || code!=15)
            $fatal(1,"CRC error after all pixels written committed an invalid image");
        fail_final_crc=0;rescan();recovered(before_commits+1);
        $display("PASS final-sector failure after pixels cannot commit; explicit rescan recovers");
        repeat(2600)@(negedge pix_clk);
        if(collision_count || torn_frames) $fatal(1,"buffer ownership or mixed frame");
        $display("PASS rescan real BMP and asynchronous memory: commits=%0d collisions=%0d torn=%0d",commits,collision_count,torn_frames);
        if(diag_rescans<5 || diag_inits<5 || diag_fails<1 || diag_recovered<5)
            $fatal(1,"missing real rescan/init/recovery logs");
        $display("PASS real KEY2/duplicate rescan/init failure/recovered event diagnostics");
        $finish;
    end
    initial begin #100000000; $fatal(1,"handoff watchdog phase=%0d state=%0d err=%0d fat=%h count=%0d load=%0d commits=%0d",dut.recovery_phase,dut.bmp_read_m0.state,dut.bmp_error,dut.bmp_read_m0.fat_error,dut.img_found_count,dut.load_busy,commits); end
endmodule

// Simulation-only 512-word asynchronous FIFOs with two-stage pointer visibility.
module sim_frame_fifo(input clkr,clkw,rst,we,re,input [31:0] di,
    output empty_flag,full_flag,output [8:0] wrusedw,rdusedw,output reg [31:0] dout);
    reg [31:0] storage[0:511];
    reg [9:0] wp=0,rp=0,rs0=0,rs1=0,ws0=0,ws1=0;
    wire [9:0] wc=wp-rs1,rc=ws1-rp;
    assign wrusedw=wc[8:0]; assign rdusedw=rc[8:0];
    assign empty_flag=rc==0; assign full_flag=wc==512;
    always @(posedge clkw or posedge rst) begin
        if(rst) begin wp<=0;rs0<=0;rs1<=0; end
        else begin
            rs0<=rp;rs1<=rs0;
            if(we) begin
                if(full_flag) $fatal(1,"FIFO overflow");
                storage[wp[8:0]]<=di;wp<=wp+1'b1;
            end
        end
    end
    always @(posedge clkr or posedge rst) begin
        if(rst) begin rp<=0;ws0<=0;ws1<=0;dout<=0; end
        else begin
            ws0<=wp;ws1<=ws0;
            if(re) begin
                if(empty_flag) $fatal(1,"FIFO underflow");
                dout<=storage[rp[8:0]];rp<=rp+1'b1;
            end
        end
    end
endmodule
module rfifo_32_32_512(input clkr,clkw,rst,we,re,input [31:0] di,
    output empty_flag,full_flag,output [8:0] wrusedw,rdusedw,output [31:0] dout);
    sim_frame_fifo f(.*);
endmodule
module wfifo_32_32_512(input clkr,clkw,rst,we,re,input [31:0] di,
    output empty_flag,full_flag,output [8:0] wrusedw,rdusedw,output [31:0] dout);
    wire [31:0] unused_dout;
    sim_frame_fifo f(.dout(unused_dout),.*);
    // Write-side memory controller consumes the current head on App_wr_en.
    assign dout=f.storage[f.rp[8:0]];
endmodule

module sd_card_top #(parameter CLK_FREQ_HZ=100_000_000)(input clk,rst,output SD_nCS,SD_DCLK,SD_MOSI,input SD_MISO,
    output [63:0] sd_debug,
    output sd_init_failed,sd_sec_read_failed,
    output sd_init_done,input sd_sec_read,input [31:0] sd_sec_read_addr,
    output [7:0] sd_sec_read_data,output sd_sec_read_data_valid,sd_sec_read_end,
    input sd_sec_write,input [31:0] sd_sec_write_addr,output [7:0] sd_sec_write_data,
    output sd_sec_write_data_req,sd_sec_write_end);
    assign sd_debug=0;assign sd_init_failed=0;assign sd_sec_read_failed=0;assign sd_init_done=!rst;assign SD_nCS=1;assign SD_DCLK=0;assign SD_MOSI=0;
    assign sd_sec_read_data=0;assign sd_sec_read_data_valid=0;assign sd_sec_read_end=0;
    assign sd_sec_write_data=0;assign sd_sec_write_data_req=0;assign sd_sec_write_end=0;
endmodule
