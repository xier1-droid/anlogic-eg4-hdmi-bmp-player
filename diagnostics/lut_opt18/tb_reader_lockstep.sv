`timescale 1ns/1ps
// v0.18 S2 batch 5: fat32_bmp_reader with the shared header checker against
// the frozen v0.17.0 reader (own preflight and decoder checkers), clock by
// clock. Same fixtures, sector model and checks as fat32/tb_fat32_reader.sv;
// both readers get identical inputs, the model serves the new reader and
// every reader output must match the reference on every clock.
module tb_reader_lockstep;
    parameter integer CASE_ID=0;
    parameter integer SCALE_TEST=0;
    parameter FIXTURE_DIR="diagnostics/output/fat32_core/fixtures";
    parameter integer BYTE_GAP=2;
    parameter integer TEST_MODE=0; // 1..3: rejected headers; 4: ack timeout; 5: last byte/end together
    // 0: only the lockstep comparison decides (scale-path cases whose result
    // contract assumes the fixed path's 4-cluster walk limit).
    parameter integer CHECK_CONTRACT=1;
    reg clk=0;always #5 clk=~clk;
    reg rst=1,scan_start=0,file_start=0,owner=0;
    wire scan_done;
    reg [31:0] selected_cluster=0,selected_size=0;
    wire raw_req;wire [31:0] raw_lba;
    reg raw_valid=0,raw_end=0,raw_failed=0;
    reg [7:0] raw_byte=0;
    reg [31:0] meta[0:31],lbas[0:511];
    reg [7:0] media[0:262143];
    integer slot=-1,raw_index=0,gap_count=0,requests=0;
    integer active_image=0,pixels=0;
    reg serving=0,raw_released=1;
    wire pixel_valid;
    wire [23:0] pixel_rgb;

    wire ready,scan_fault,found,load_done,load_error,write_req;
    wire [31:0] found_cluster,found_size;
    wire [2:0] found_count,bmp_error;
    wire [7:0] fat_error;
    reg ack=0;
    wire r_ready,r_scan_done,r_scan_fault,r_found,r_load_done,r_load_error,r_write_req,r_pixel_valid,r_raw_req;
    wire [31:0] r_found_cluster,r_found_size,r_raw_lba;wire [2:0] r_found_count,r_bmp_error;wire [7:0] r_fat_error,r_alpha,alpha;
    wire [23:0] r_pixel_rgb;wire [3:0] r_state,state;wire [5:0] r_kind,kind;
    reg [31:0] table_cluster[0:3],table_size[0:3];
    integer found_n=0,delay_ack=0;
    reg write_ready=1;integer ready_cycles=0;
    always @(negedge clk)begin ready_cycles=ready_cycles+1;write_ready=!SCALE_TEST || ready_cycles%23<13;end
    fat32_bmp_reader #(.SCALE_ENABLE(SCALE_TEST),.CLK_FREQ_HZ(1000),.TIMEOUT_MS(500),.MAX_VISITED_CLUSTERS(4)) dut(
      .audio_found(),.audio_cluster(),.audio_size(),.audio_spc(),.audio_fat_lba(),.audio_data_lba(),.audio_max_cluster(),
      .a_req(1'b0),.a_lba(32'd0),.a_cancel(1'b0),.a_urgent(1'b0),
      .a_busy(),.a_valid(),.a_done(),.a_error(),.a_byte(),.a_index(),
      .clk(clk),.rst(rst),.sd_init_done(1'b1),.scan_start(scan_start),.load_cancel(1'b0),.load_start(file_start),
      .load_cluster(selected_cluster),.load_size(selected_size),.load_index(2'd0),.bmp_width(16'd3),.bmp_height(16'd91),
      .ready(ready),.scan_done(scan_done),.scan_error(scan_fault),.scan_found_valid(found),
      .scan_found_cluster(found_cluster),.scan_found_size(found_size),.scan_found_total(found_count),
      .load_done(load_done),.load_error(load_error),.bmp_error(bmp_error),.fat_error(fat_error),.state_code(state),
      .write_req(write_req),.write_req_ack(ack),.write_ready(write_ready),.bmp_data_wr_en(pixel_valid),.bmp_data(pixel_rgb),
      .sd_sec_read(raw_req),.sd_sec_read_addr(raw_lba),.sd_sec_read_data(raw_byte),
      .sd_sec_read_data_valid(raw_valid),.sd_sec_read_end(raw_end),.sd_sec_read_failed(raw_failed),.bmp_alpha(alpha),.bmp_kind(kind),.audio_slot(3'd4),.snd_found(),.bin_wr(),.bin_sel(),.bin_addr(),.bin_data(),.font_loaded(),.text_loaded());
    fat32_bmp_reader_v017 #(.SCALE_ENABLE(SCALE_TEST),.CLK_FREQ_HZ(1000),.TIMEOUT_MS(500),.MAX_VISITED_CLUSTERS(4)) ref_(
      .audio_found(),.audio_cluster(),.audio_size(),.audio_spc(),.audio_fat_lba(),.audio_data_lba(),.audio_max_cluster(),
      .a_req(1'b0),.a_lba(32'd0),.a_cancel(1'b0),.a_urgent(1'b0),
      .a_busy(),.a_valid(),.a_done(),.a_error(),.a_byte(),.a_index(),
      .clk(clk),.rst(rst),.sd_init_done(1'b1),.scan_start(scan_start),.load_cancel(1'b0),.load_start(file_start),
      .load_cluster(selected_cluster),.load_size(selected_size),.load_index(2'd0),.bmp_width(16'd3),.bmp_height(16'd91),
      .ready(r_ready),.scan_done(r_scan_done),.scan_error(r_scan_fault),.scan_found_valid(r_found),
      .scan_found_cluster(r_found_cluster),.scan_found_size(r_found_size),.scan_found_total(r_found_count),
      .load_done(r_load_done),.load_error(r_load_error),.bmp_error(r_bmp_error),.fat_error(r_fat_error),.state_code(r_state),
      .write_req(r_write_req),.write_req_ack(ack),.write_ready(write_ready),.bmp_data_wr_en(r_pixel_valid),.bmp_data(r_pixel_rgb),
      .sd_sec_read(r_raw_req),.sd_sec_read_addr(r_raw_lba),.sd_sec_read_data(raw_byte),
      .sd_sec_read_data_valid(raw_valid),.sd_sec_read_end(raw_end),.sd_sec_read_failed(raw_failed),.bmp_alpha(r_alpha),.bmp_kind(r_kind),.audio_slot(3'd4),.snd_found(),.bin_wr(),.bin_sel(),.bin_addr(),.bin_data(),.font_loaded(),.text_loaded());
    integer compared=0;
    always @(negedge clk)if(!rst)begin
      if({ready,scan_done,scan_fault,found,found_cluster,found_size,found_count,load_done,load_error,bmp_error,fat_error,state,write_req,pixel_valid,raw_req,raw_lba,kind}!==
         {r_ready,r_scan_done,r_scan_fault,r_found,r_found_cluster,r_found_size,r_found_count,r_load_done,r_load_error,r_bmp_error,r_fat_error,r_state,r_write_req,r_pixel_valid,r_raw_req,r_raw_lba,r_kind}
         || (pixel_valid && {pixel_rgb,alpha}!=={r_pixel_rgb,r_alpha}))
        $fatal(1,"reader differs at %0t: state %h/%h req %b/%b lba %h/%h pixel %b/%b %h/%h err %0d/%0d",$time,state,r_state,raw_req,r_raw_req,raw_lba,r_raw_lba,pixel_valid,r_pixel_valid,pixel_rgb,r_pixel_rgb,bmp_error,r_bmp_error);
      compared=compared+1;
    end
    always @(negedge clk)begin
      if(rst || !write_req)begin ack=0;delay_ack=0;end
      else begin delay_ack=delay_ack+1;if(delay_ack==40 && TEST_MODE!=4)ack=1;end
    end
    always @(posedge clk)if(!rst)begin
      if(found)begin table_cluster[found_n]=found_cluster;table_size[found_n]=found_size;found_n=found_n+1;end
      if(pixel_valid && !owner)$fatal(1,"pixels before load");
      if(write_req && raw_req)$fatal(1,"read before SDRAM acknowledgement");
    end
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
            if(TEST_MODE==5 && raw_index==512)begin raw_end=1;serving=0;end
        end else begin raw_end=1;serving=0;end
    end
    always @(posedge clk) if(!rst && pixel_valid)begin
       row=pixels/3;col=pixels%3;seed=active_image*29+1;
       expected_rgb={8'(row*3+seed),8'(col+17),8'(row+seed)};
       if(SCALE_TEST)begin
        col=pixels%640;row=479-pixels/640;expected_rgb=0;
        if(col>=312 && col<327)begin
         col=(col-312)*3/15;row=90-row*91/480;
         expected_rgb={8'(row*3+seed),8'(col+17),8'(row+seed)};
        end
       end
       if(meta[27+active_image]==0 && pixel_rgb!==expected_rgb) if(CHECK_CONTRACT)$fatal(1,"pixel %0d %h expected %h",pixels,pixel_rgb,expected_rgb);
       pixels=pixels+1;
    end
    integer i,k,expected_count,first_slot;
    initial begin
      $readmemh($sformatf("%s/case%0d_meta.hex",FIXTURE_DIR,CASE_ID),meta,0,31);
      $readmemh($sformatf("%s/case%0d_lba.hex",FIXTURE_DIR,CASE_ID),lbas,0,meta[25]-1);
      $readmemh($sformatf("%s/case%0d_bytes.hex",FIXTURE_DIR,CASE_ID),media,0,meta[25]*512-1);
      first_slot=-1;
      for(k=0;k<meta[25];k=k+1)if(lbas[k]==meta[5]+(meta[7]-2)*meta[3])first_slot=k;
      if(TEST_MODE>=1 && TEST_MODE<=3)begin
        if(first_slot<0)$fatal(1,"missing mutation target");
        if(TEST_MODE==1)media[first_slot*512+18]=2;
        // v0.17.0: 32bpp is a supported format (3-wide rows are 12 bytes in
        // both depths, so bitcount=32 would form a valid file). Use 16bpp.
        if(TEST_MODE==2)media[first_slot*512+28]=16;
        if(TEST_MODE==3)media[first_slot*512+2]=1;
      end
      repeat(4)@(negedge clk);rst=0;@(negedge clk);
      if(!ready)$fatal(1,"not ready on boot");
      scan_start=1;@(negedge clk);scan_start=0;
      wait(scan_done);@(negedge clk);
      expected_count=0;
      if(meta[0]==0)for(k=0;k<4;k=k+1)if(meta[1][k] && meta[11+k]>=1146 && meta[7+k]>=2 && meta[7+k]<=meta[6])expected_count=expected_count+1;
      if(TEST_MODE>=1 && TEST_MODE<=3)expected_count=expected_count-1;
      // Media errors during first-sector preflight abort scan; no list claim.
      if(fat_error==0 && found_n!=expected_count) if(CHECK_CONTRACT)$fatal(1,"list count %0d expected %0d",found_n,expected_count);
      if(meta[0]!=0 && fat_error==0) if(CHECK_CONTRACT)$fatal(1,"missing volume error");
      if(fat_error==0)for(i=0;i<found_n;i=i+1)begin
        active_image=0;for(k=0;k<4;k=k+1)if(meta[7+k]==table_cluster[i])active_image=k;
        selected_cluster=table_cluster[i];selected_size=table_size[i];owner=1;pixels=0;
        file_start=1;@(negedge clk);file_start=0;
        wait(load_done || load_error);@(negedge clk);
        if(TEST_MODE==4)begin
          if(!load_error || bmp_error!=2 || pixels!=0) if(CHECK_CONTRACT)$fatal(1,"ack timeout contract");
        end else if(meta[17+active_image]==0)begin
          if(load_error || pixels!=(SCALE_TEST?307200:273)) if(CHECK_CONTRACT)$fatal(1,"good image failed code=%0d fat=%h pixels=%0d",bmp_error,fat_error,pixels);
        end else begin
          if(!load_error || load_done) if(CHECK_CONTRACT)$fatal(1,"bad image succeeded");
          if(meta[17+active_image]==8'h10 && bmp_error!=2) if(CHECK_CONTRACT)$fatal(1,"SD failure classification");
          if(meta[17+active_image]!=8'h10 && bmp_error!=3) if(CHECK_CONTRACT)$fatal(1,"chain failure classification");
        end
        if(!ready) if(CHECK_CONTRACT)$fatal(1,"not ready after result");
        repeat(4)@(negedge clk);
      end
      if(!scan_done) if(CHECK_CONTRACT)$fatal(1,"scan_done not sticky");
      $display("PASS reader lockstep case=%0d scale=%0d found=%0d requests=%0d mode=%0d, %0d clocks equal",CASE_ID,SCALE_TEST,found_n,requests,TEST_MODE,compared);$finish;
    end
    initial begin #(SCALE_TEST?200000000:10000000);$fatal(1,"reader watchdog");end
endmodule
