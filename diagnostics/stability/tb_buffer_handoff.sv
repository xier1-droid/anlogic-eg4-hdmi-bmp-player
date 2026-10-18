`timescale 1ns/1ps
// Real application, frame read/write controllers. Behavioral source, dual-clock
// FIFOs and SDRAM data port replace encrypted/vendor and SPI implementations.
module tb_buffer_handoff;
    parameter integer PIX_HALF = 17;
    parameter integer SOURCE_GAP = 2;
    reg clk=0, mem_clk=0, pix_clk=0, rst=1;
    always #5 clk=~clk;
    always #7 mem_clk=~mem_clk;
    initial begin #3; forever #(PIX_HALF) pix_clk=~pix_clk; end
    wire valid, req, we, ack, wr_finish;
    wire [31:0] data;
    wire [1:0] wb, db;
    wire commit_request, commit_ack;
    reg finish_toggle=0;
    always @(posedge mem_clk) if(rst) finish_toggle<=0; else if(wr_finish) finish_toggle<=~finish_toggle;
    sd_card_bmp #(.CLK_FREQ_HZ(1000), .AUTO_PLAY_MS(3000)) dut (
        .write_cancel_req(),.write_cancel_ack(1'b0),
        .sd_debug(),.diagnostics(),.sdram_ready(1'b1),
        .clk(clk),.rst(rst),.key1(1'b1),.key2(1'b1),.key4(1'b1),.mode(2'b00),
        .state_code(),.combo_event_count(),.combo_debug_active(),.auto_play_indicator(),
        .bmp_width(16'd32),.bmp_height(16'd32),.display_valid(valid),.committed_image(),.committed_valid(),.committed_ready(1'b1),
        .write_finish_toggle(finish_toggle),.write_buf_idx(wb),.disp_buf_idx(db),
        .display_commit_request(commit_request),.display_commit_ack(commit_ack),
        .write_req(req),.write_req_ack(ack),.write_en(we),.write_data(data),
        .SD_nCS(),.SD_DCLK(),.SD_MOSI(),.SD_MISO(1'b1)
    ,.warn_mode(),.bin_wr(),.bin_sel(),.bin_addr(),.bin_data(),.font_loaded(),.text_loaded());
    defparam dut.bmp_read_m0.PIXEL_GAP = SOURCE_GAP;
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
        .write_cancel_req(1'b0),.write_cancel_ack(),.write_clk(clk),.write_req(req),.write_req_ack(ack),.write_finish(wr_finish),
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
    initial begin
        for(i=0;i<2048;i=i+1) memory[i]=0;
        repeat(5) @(negedge clk); rst=0;
        wait(valid);
        // Keep one request pending while each image is loading.
        for(i=0;i<16;i=i+1) begin
            next_request();
            wait(dut.load_busy);
            next_request();
            wait(!dut.load_busy);
        end
        wait(!dut.load_busy && !dut.u_media_player_control.next_pending);
        repeat(2600) @(negedge pix_clk);
        $display("RESULT loaded=%0d read_frames=%0d old_buffer_writes=%0d mixed_frames=%0d",
            loaded,frame_reads,collision_count,torn_frames);
        if(collision_count || torn_frames) $fatal(1,"buffer reused before reader released it");
        if(loaded<16 || frame_reads<5) $fatal(1,"insufficient handoff coverage");
        $display("PASS asynchronous buffer ownership and uniform displayed frames");
        $finish;
    end
    initial begin #50000000; $fatal(1,"handoff watchdog"); end
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

// Source model: enumerate four images, honor write request/ack, stream a solid
// color image. Real BMP/SPI parsing remains covered by tb_picture_requests.
module fat32_bmp_reader #(parameter integer PIXEL_GAP=2, CLK_FREQ_HZ=100_000_000, TIMEOUT_MS=500, ENABLE_SCAN_PAUSE=0)(input clk,rst,output reg ready,
    input scan_start,
    output wire scan_error, output reg scan_done,scan_found_valid,output reg [31:0] scan_found_cluster,output reg [2:0] scan_found_total,
    output reg load_done, output load_error, output [2:0] bmp_error,
    output [7:0] fat_error,output [31:0] scan_found_size,input [31:0] load_size,
    input load_start,input [31:0] load_cluster,input sd_init_done,output [3:0] state_code,
    input [15:0] bmp_width,bmp_height,output reg write_req,input write_req_ack,
    output sd_sec_read,output [31:0] sd_sec_read_addr,input [7:0] sd_sec_read_data,
    input sd_sec_read_failed,sd_sec_read_data_valid,sd_sec_read_end,output reg bmp_data_wr_en,output reg [23:0] bmp_data);
    assign scan_error = 1'b0;assign fat_error=0;assign scan_found_size=3126;
    integer state=0,count=0,pace=0;
    assign load_error=0; assign bmp_error=0;
    assign state_code=0;assign sd_sec_read=0;assign sd_sec_read_addr=0;
    always @(posedge clk) begin
        if(rst) begin
            load_done<=0;ready<=1;scan_done<=0;scan_found_valid<=0;scan_found_total<=0;
            scan_found_cluster<=0;write_req<=0;bmp_data_wr_en<=0;bmp_data<=0;state<=0;count<=0;pace<=0;
        end else begin
            load_done<=0;scan_found_valid<=0;bmp_data_wr_en<=0;
            case(state)
                0: if(scan_start) begin state<=1;ready<=0;count<=0;end
                   else if(load_start) begin
                       state<=2;ready<=0;write_req<=1;count<=0;pace<=0;
                       bmp_data<=load_cluster+1;
                   end
                1: if(count<4) begin
                       scan_found_valid<=1;scan_found_cluster<=count;scan_found_total<=count+1;count<=count+1;
                   end else begin scan_done<=1;ready<=1;state<=0;end
                2: if(write_req_ack) begin write_req<=0;state<=3;end
                3: if(!write_req_ack) state<=4;
                4: begin
                    if(pace==PIXEL_GAP-1) begin
                        pace<=0;
                        bmp_data_wr_en<=1;count<=count+1;
                        if(count==1023) state<=5;
                    end else pace<=pace+1;
                end
                5: begin load_done<=1;ready<=1;state<=0;end
            endcase
        end
    end
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
