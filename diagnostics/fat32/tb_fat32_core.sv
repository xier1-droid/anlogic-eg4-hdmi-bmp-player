`timescale 1ns/1ps
module tb_fat32_core;
    parameter integer CASE_ID=0;
    parameter integer BYTE_GAP=2;
    parameter integer RESET_DURING=0; // 1: directory scan, 2: file read
    reg clk=0;always #5 clk=~clk;
    reg rst=1,scan_start=0,file_start=0,owner=0;
    wire scan_busy,scan_done,file_busy,file_done,file_valid;
    wire [7:0] scan_error,file_error,file_byte,spc;
    wire [31:0] partition_lba,fat_lba,data_lba,max_cluster,file_offset;
    wire [3:0] resource_valid;
    wire [31:0] clusters[0:3],sizes[0:3];
    reg [31:0] selected_cluster=0,selected_size=0;
    wire scan_req,file_req,sector_busy,sector_valid,sector_done;
    wire [31:0] scan_lba,file_lba;
    wire [7:0] sector_byte,sector_error;
    wire [8:0] sector_index;
    wire raw_req;wire [31:0] raw_lba;
    reg raw_valid=0,raw_end=0,raw_failed=0;
    reg [7:0] raw_byte=0;
    reg [31:0] meta[0:31],lbas[0:511],expected_trace[0:2047];
    reg [7:0] media[0:262143],expected[0:32767];
    integer slot=-1,raw_index=0,gap_count=0,requests=0,expected_pos=0,received=0;
    integer active_image=0,pixels=0,commits=0,done_count=0;
    reg serving=0,raw_released=1;
    wire pixel_valid,frame_commit,decode_done;
    wire [23:0] pixel_rgb;
    wire [15:0] pixel_x,pixel_y;
    wire [2:0] decode_error;

    fat32_volume_scanner #(.MAX_VISITED_CLUSTERS(4)) scanner (
        .clk(clk),.rst_n(!rst),.scan_start(scan_start),.scan_busy(scan_busy),.scan_done(scan_done),.fs_error(scan_error),
        .partition_lba(partition_lba),.sectors_per_cluster(spc),.fat_start_lba(fat_lba),.data_start_lba(data_lba),.max_cluster(max_cluster),
        .resource_valid(resource_valid),.audio_slot(3'd4),.snd_found(),.audio_found(),.audio_cluster(),.audio_size(),.resource0_cluster(clusters[0]),.resource1_cluster(clusters[1]),
        .resource2_cluster(clusters[2]),.resource3_cluster(clusters[3]),
        .resource0_size(sizes[0]),.resource1_size(sizes[1]),.resource2_size(sizes[2]),.resource3_size(sizes[3]),
        .sector_req(scan_req),.sector_lba(scan_lba),.sector_busy(sector_busy),
        .sector_valid(!owner && sector_valid),.sector_byte(sector_byte),.sector_byte_index(sector_index),
        .sector_done(!owner && sector_done),.sector_error(sector_error)
    ,.font_found(),.text_found(),.font_big(),.text_big(),.font_cluster(),.text_cluster(),.font_size(),.text_size());
    fat32_file_streamer #(.MAX_VISITED_CLUSTERS(4)) streamer (
        .clk(clk),.rst_n(!rst),.file_start(file_start),.data_permit(1'b1),.first_cluster(selected_cluster),.file_size(selected_size),
        .sectors_per_cluster(spc),.fat_start_lba(fat_lba),.data_start_lba(data_lba),.max_cluster(max_cluster),
        .file_busy(file_busy),.file_done(file_done),.file_valid(file_valid),.file_byte(file_byte),.file_byte_offset(file_offset),.fs_error(file_error),
        .sector_req(file_req),.sector_lba(file_lba),.sector_busy(sector_busy),
        .sector_valid(owner && sector_valid),.sector_byte(sector_byte),.sector_byte_index(sector_index),
        .sector_done(owner && sector_done),.sector_error(sector_error)
    );
    sd_sector_adapter #(.CLK_FREQ_HZ(1000),.TIMEOUT_MS(500)) adapter (
        .clk(clk),.rst(rst),.sector_req(owner ? file_req : scan_req),.sector_lba(owner ? file_lba : scan_lba),
        .sector_busy(sector_busy),.sector_valid(sector_valid),.sector_byte(sector_byte),.sector_byte_index(sector_index),
        .sector_done(sector_done),.sector_error(sector_error),.sd_sec_read(raw_req),.sd_sec_read_addr(raw_lba),
        .sd_sec_read_data_valid(raw_valid),.sd_sec_read_data(raw_byte),.sd_sec_read_end(raw_end),.sd_sec_read_failed(raw_failed)
    );
    bmp24_decoder #(.EXPECTED_WIDTH(3),.EXPECTED_HEIGHT(91),.ALLOW_32(0)) decoder (
        .clk(clk),.rst(rst),.expected_width(16'd3),.expected_height(16'd91),
        .file_start(file_start),.file_size(selected_size),.file_valid(file_valid),.file_byte(file_byte),
        .file_byte_offset(file_offset),.file_end(file_done),.upstream_error(file_error),
        .header_accepted(),.pixel_valid(pixel_valid),.pixel_rgb(pixel_rgb),.pixel_x(pixel_x),.pixel_y(pixel_y),
        .frame_commit(frame_commit),.bmp_done(decode_done),.bmp_error(decode_error)
    );

    integer j,seed,row,col;
    reg [23:0] expected_rgb;
    // Independent sparse block device. Request trace is generated from FAT
    // contents by Python, not from RTL states or internal cluster registers.
    always @(negedge clk) begin
        raw_valid=0;raw_end=0;raw_failed=0;
        if(rst)begin serving=0;raw_released=1;gap_count=0;end
        else if(!serving)begin
            if(!raw_req)raw_released=1;
            if(raw_req && raw_released)begin
                if(requests>=meta[26] || raw_lba!==expected_trace[requests])
                    $fatal(1,"case %0d unexpected read #%0d LBA=%h expected=%h",CASE_ID,requests,raw_lba,expected_trace[requests]);
                slot=-1;
                for(j=0;j<meta[25];j=j+1)if(lbas[j]==raw_lba)slot=j;
                if(slot<0)$fatal(1,"read outside sparse fixture");
                requests=requests+1;raw_index=0;serving=1;raw_released=0;gap_count=3;
            end
        end else if(gap_count>0)gap_count=gap_count-1;
        else if(raw_lba==meta[15] && raw_index==meta[16])begin
            raw_failed=1;serving=0;
        end else if(raw_index<512)begin
            raw_valid=1;raw_byte=media[slot*512+raw_index];raw_index=raw_index+1;gap_count=BYTE_GAP;
        end else begin raw_end=1;serving=0;end
    end
    always @(posedge clk) if(!rst)begin
        if(file_valid)begin
            if(file_offset!==32'(received) || file_byte!==expected[expected_pos])
                $fatal(1,"case %0d image %0d byte %0d: got %h expected %h offset %0d",CASE_ID,active_image,received,file_byte,expected[expected_pos],file_offset);
            received=received+1;expected_pos=expected_pos+1;
            if(received>meta[21+active_image])$fatal(1,"bytes beyond expected file size");
        end
        if(pixel_valid)begin
            if(meta[27+active_image]==0)begin
                row=pixels/3;col=pixels%3;seed=active_image*29+1;
                expected_rgb={8'(row*3+seed),8'(col+17),8'(row+seed)};
                if(pixel_rgb!==expected_rgb || pixel_x!==16'(col) || pixel_y!==16'(90-row))
                    $fatal(1,"pixel mismatch %0d: %h/%h xy=%0d,%0d",pixels,pixel_rgb,expected_rgb,pixel_x,pixel_y);
            end
            pixels=pixels+1;
        end
        if(frame_commit)commits=commits+1;
        if(decode_done)done_count=done_count+1;
        if(scan_req && file_req)$fatal(1,"simultaneous sector owners");
    end
    task load_fixture(input integer id);
        integer length,k;
        string prefix;
        begin
            prefix=$sformatf("diagnostics/output/fat32_core/fixtures/case%0d_",id);
            $readmemh({prefix,"meta.hex"},meta,0,31);
            $readmemh({prefix,"lba.hex"},lbas,0,meta[25]-1);
            $readmemh({prefix,"bytes.hex"},media,0,meta[25]*512-1);
            $readmemh({prefix,"trace.hex"},expected_trace,0,meta[26]-1);
            length=0;for(k=0;k<4;k=k+1)length=length+meta[21+k];
            $readmemh({prefix,"expected.hex"},expected,0,length==0 ? 0 : length-1);
            requests=0;expected_pos=0;
        end
    endtask
    task do_scan;
        integer k;
        begin
            owner=0;scan_start=1;@(negedge clk);scan_start=0;
            wait(scan_done);@(negedge clk);
            if(scan_error!==8'(meta[0]))$fatal(1,"case %0d scan error %h expected %h",CASE_ID,scan_error,meta[0]);
            if(!scan_error)begin
                if(resource_valid!==4'(meta[1]) || partition_lba!==meta[2] || spc!==8'(meta[3]) ||
                    fat_lba!==meta[4] || data_lba!==meta[5] || max_cluster!==meta[6])$fatal(1,"volume geometry/mask mismatch");
                for(k=0;k<4;k=k+1)begin
                    if(resource_valid[k] && (clusters[k]!==meta[7+k] || sizes[k]!==meta[11+k]))$fatal(1,"directory metadata mismatch %0d",k);
                    if(!resource_valid[k] && (clusters[k]!==0 || sizes[k]!==0))$fatal(1,"stale absent metadata");
                end
            end
            while(sector_busy)@(negedge clk);
        end
    endtask
    integer i;
    initial begin
        load_fixture(CASE_ID);
        repeat(4)@(negedge clk);rst=0;@(negedge clk);
        if(RESET_DURING==1)begin
            scan_start=1;@(negedge clk);scan_start=0;
            wait(raw_valid);repeat(20)@(negedge clk);
            rst=1;repeat(3)@(negedge clk);rst=0;
            load_fixture(CASE_ID);@(negedge clk);
            if(scan_busy || scan_done || resource_valid!=0)$fatal(1,"scan reset not clean");
        end
        if(meta[31])begin
            load_fixture(0);do_scan();
            if(resource_valid!==15)$fatal(1,"rescan prerequisite");
            load_fixture(CASE_ID);
        end
        do_scan();
        if(RESET_DURING==2)begin
            owner=1;selected_cluster=clusters[0];selected_size=sizes[0];file_start=1;
            @(negedge clk);file_start=0;
            wait(file_valid);repeat(20)@(negedge clk);
            rst=1;repeat(3)@(negedge clk);rst=0;
            load_fixture(CASE_ID);received=0;pixels=0;commits=0;done_count=0;
            @(negedge clk);
            if(file_busy || file_done || frame_commit)$fatal(1,"file reset not clean");
            do_scan();
        end
        if(scan_error==0)begin
            owner=1;
            for(i=0;i<4;i=i+1)if(resource_valid[i])begin
                active_image=i;received=0;pixels=0;commits=0;done_count=0;
                selected_cluster=clusters[i];selected_size=sizes[i];file_start=1;
                @(negedge clk);file_start=0;selected_size=32'hdeadbeef;
                wait(file_done);repeat(8)@(negedge clk);
                if(file_error!==8'(meta[17+i]) || received!=meta[21+i])
                    $fatal(1,"file %0d result error=%h expected=%h bytes=%0d/%0d",i,file_error,meta[17+i],received,meta[21+i]);
                if(meta[27+i]==0)begin
                    if(decode_error!=0 || pixels!=273 || commits!=1 || done_count!=1)$fatal(1,"complete BMP did not commit exactly once");
                end else if(commits!=0 || done_count!=0 || decode_error==0)$fatal(1,"damaged file committed");
                while(sector_busy)@(negedge clk);
            end
        end
        if(requests!=meta[26])$fatal(1,"incomplete request trace: %0d/%0d",requests,meta[26]);
        repeat(10)@(negedge clk);
        if(scan_busy || file_busy || sector_busy)$fatal(1,"service did not return idle");
        $display("PASS FAT32 core case=%0d requests=%0d bytes=%0d scan_error=%h",CASE_ID,requests,expected_pos,scan_error);
        $finish;
    end
    initial begin #10000000;$fatal(1,"core watchdog");end
endmodule
