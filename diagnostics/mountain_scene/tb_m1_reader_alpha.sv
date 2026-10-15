`timescale 1ns/1ps
// M1: fat32_bmp_reader scan preflight accepts a 32bpp PIC1 and loads it with
// bmp_alpha equal to the file's alpha bytes; 24bpp PIC2-4 report alpha FF.
// Sparse block device as in diagnostics/fat32/tb_fat32_reader.sv.
module tb_m1_reader_alpha;
    parameter integer CASE_ID=0;
    parameter integer SCALE_TEST=0;
    parameter FIXTURE_DIR="diagnostics/output/m1_reader/fixtures";
    parameter integer BYTE_GAP=0;
    reg clk=0;always #5 clk=~clk;
    reg rst=1,scan_start=0,file_start=0,owner=0;
    wire scan_done;
    wire raw_req;wire [31:0] raw_lba;
    reg raw_valid=0,raw_end=0,raw_failed=0;
    reg [7:0] raw_byte=0;
    reg [31:0] meta[0:31],lbas[0:511];
    reg [7:0] media[0:262143];
    integer slot=-1,raw_index=0,gap_count=0;
    integer active_image=0,pixels=0,alpha_varied=0;
    reg serving=0,raw_released=1;
    wire pixel_valid;wire [23:0] pixel_rgb;wire [7:0] pixel_alpha;
    wire ready,scan_fault,found,load_done,load_error,write_req;
    wire [31:0] found_cluster,found_size;
    wire [2:0] found_count,bmp_error;
    wire [7:0] fat_error;
    reg ack=0;
    reg [31:0] table_cluster[0:3],table_size[0:3];
    integer found_n=0,delay_ack=0;
    reg write_ready=1;integer ready_cycles=0;
    always @(negedge clk)begin ready_cycles=ready_cycles+1;write_ready=!SCALE_TEST || ready_cycles%23<13;end
    fat32_bmp_reader #(.SCALE_ENABLE(SCALE_TEST),.CLK_FREQ_HZ(1000),.TIMEOUT_MS(500),.MAX_VISITED_CLUSTERS(4)) dut(
      .audio_found(),.audio_cluster(),.audio_size(),.audio_spc(),.audio_fat_lba(),.audio_data_lba(),.audio_max_cluster(),
      .a_req(1'b0),.a_lba(32'd0),.a_cancel(1'b0),.a_urgent(1'b0),
      .a_busy(),.a_valid(),.a_done(),.a_error(),.a_byte(),.a_index(),
      .clk(clk),.rst(rst),.sd_init_done(1'b1),.scan_start(scan_start),.load_cancel(1'b0),.load_start(file_start),
      .load_cluster(table_cluster[0]),.load_size(table_size[0]),.load_index(2'd0),.bmp_width(16'd3),.bmp_height(16'd91),
      .ready(ready),.scan_done(scan_done),.scan_error(scan_fault),.scan_found_valid(found),
      .scan_found_cluster(found_cluster),.scan_found_size(found_size),.scan_found_total(found_count),
      .load_done(load_done),.load_error(load_error),.bmp_error(bmp_error),.fat_error(fat_error),.state_code(),
      .write_req(write_req),.write_req_ack(ack),.write_ready(write_ready),.bmp_data_wr_en(pixel_valid),.bmp_data(pixel_rgb),
      .sd_sec_read(raw_req),.sd_sec_read_addr(raw_lba),.sd_sec_read_data(raw_byte),
      .sd_sec_read_data_valid(raw_valid),.sd_sec_read_end(raw_end),.sd_sec_read_failed(raw_failed),
      .bmp_alpha(pixel_alpha));
    // SDRAM word as assembled by sd_card_bmp: {R,G,B,T}.
    wire [31:0] write_word={pixel_rgb,pixel_alpha};
    always @(negedge clk)begin
      if(rst || !write_req)begin ack=0;delay_ack=0;end
      else begin delay_ack=delay_ack+1;if(delay_ack==40)ack=1;end
    end
    always @(posedge clk)if(!rst)begin
      if(found)begin table_cluster[found_n]=found_cluster;table_size[found_n]=found_size;found_n=found_n+1;end
      if(pixel_valid && !owner)$fatal(1,"pixels before load");
    end
    integer j,seed,row,col;
    reg [23:0] expected_rgb;reg [7:0] expected_alpha;
    always @(negedge clk) begin
        raw_valid=0;raw_end=0;raw_failed=0;
        if(rst)begin serving=0;raw_released=1;gap_count=0;end
        else if(!serving)begin
            if(!raw_req)raw_released=1;
            if(raw_req && raw_released)begin
                slot=-1;
                for(j=0;j<meta[25];j=j+1)if(lbas[j]==raw_lba)slot=j;
                if(slot<0)$fatal(1,"read outside sparse fixture");
                raw_index=0;serving=1;raw_released=0;gap_count=3;
            end
        end else if(gap_count>0)gap_count=gap_count-1;
        else if(raw_index<512)begin
            raw_valid=1;raw_byte=media[slot*512+raw_index];raw_index=raw_index+1;gap_count=BYTE_GAP;
        end else begin raw_end=1;serving=0;end
    end
    always @(posedge clk) if(!rst && pixel_valid)begin
       row=pixels/3;col=pixels%3;seed=active_image*29+1;
       expected_rgb={8'(row*3+seed),8'(col+17),8'(row+seed)};
       expected_alpha=active_image==0 ? 8'(row*7+col*50+5) : 8'hFF;
       if(SCALE_TEST)begin
        col=pixels%640;row=479-pixels/640;expected_rgb=0;expected_alpha=8'hFF;
        if(col>=312 && col<327)begin
         col=(col-312)*3/15;row=90-row*91/480;
         expected_rgb={8'(row*3+seed),8'(col+17),8'(row+seed)};
         if(active_image==0)expected_alpha=8'(row*7+col*50+5);
        end
       end
       if(write_word!=={expected_rgb,expected_alpha})
        $fatal(1,"image %0d pixel %0d word %h expected %h",active_image,pixels,write_word,{expected_rgb,expected_alpha});
       if(pixel_alpha!=8'hFF)alpha_varied=alpha_varied+1;
       pixels=pixels+1;
    end
    integer i,k,image_alpha;
    initial begin
      $readmemh($sformatf("%s/case%0d_meta.hex",FIXTURE_DIR,CASE_ID),meta,0,31);
      $readmemh($sformatf("%s/case%0d_lba.hex",FIXTURE_DIR,CASE_ID),lbas,0,meta[25]-1);
      $readmemh($sformatf("%s/case%0d_bytes.hex",FIXTURE_DIR,CASE_ID),media,0,meta[25]*512-1);
      repeat(4)@(negedge clk);rst=0;@(negedge clk);
      if(!ready)$fatal(1,"not ready on boot");
      scan_start=1;@(negedge clk);scan_start=0;
      wait(scan_done);@(negedge clk);
      if(fat_error!=0 || scan_fault || found_n!=4)$fatal(1,"scan found %0d fat=%h (32bpp PIC1 must pass preflight)",found_n,fat_error);
      for(i=0;i<found_n;i=i+1)begin
        active_image=0;for(k=0;k<4;k=k+1)if(meta[7+k]==table_cluster[i])active_image=k;
        table_cluster[0]=table_cluster[i];table_size[0]=table_size[i];
        owner=1;pixels=0;alpha_varied=0;
        file_start=1;@(negedge clk);file_start=0;
        wait(load_done || load_error);@(negedge clk);
        if(load_error || pixels!=(SCALE_TEST?307200:273))$fatal(1,"image %0d failed code=%0d fat=%h pixels=%0d",active_image,bmp_error,fat_error,pixels);
        if((active_image==0) != (alpha_varied!=0))$fatal(1,"image %0d alpha variation %0d",active_image,alpha_varied);
        $display("PASS M1 reader image=%0d depth=%0d pixels=%0d alpha!=FF=%0d",active_image,active_image==0?32:24,pixels,alpha_varied);
        repeat(4)@(negedge clk);
      end
      $display("PASS M1 reader alpha case=%0d scale=%0d found=%0d",CASE_ID,SCALE_TEST,found_n);$finish;
    end
    initial begin #(SCALE_TEST?200000000:10000000);$fatal(1,"reader watchdog");end
endmodule
