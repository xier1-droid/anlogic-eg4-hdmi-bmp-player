// FAT32 scan/preflight/load coordinator. Sector ownership changes only at idle.
module fat32_bmp_reader #(
 parameter integer CLK_FREQ_HZ=100000000, TIMEOUT_MS=500,
 parameter integer SCAN_AUDIO=0, SCALE_ENABLE=0,
 parameter integer MAX_VISITED_CLUSTERS=8192,
 // 1: loads select a found image by index from the scanner table instead of
 // taking load_cluster/load_size; the table only changes during a scan.
 parameter integer LOAD_BY_INDEX=0,
 // 1: after the picture headers the scan also streams FONT.BIN and TEXT.BIN
 // (each up to 4096 bytes) to bin_* and reports scan_done afterwards.
 parameter integer SCAN_TEXT=0
)(
 input clk,rst,sd_init_done,scan_start,load_start,load_cancel,
 // audio_slot picks the audio file reported on audio_*: 0-3 SND1-4.PCM,
 // otherwise BGM.PCM; snd_found marks the stage files found by the scan.
 input [2:0] audio_slot,output [3:0] snd_found,
 output audio_found,output [31:0] audio_cluster,audio_size,
 output [7:0] audio_spc,output [31:0] audio_fat_lba,audio_data_lba,audio_max_cluster,
 input a_req,input [31:0] a_lba,input a_urgent,a_cancel,
 output a_busy,a_valid,a_done,output [7:0] a_error,a_byte,output [8:0] a_index,
 input [31:0] load_cluster,load_size,input [1:0] load_index,
 input [15:0] bmp_width,bmp_height,
 output ready, output reg scan_done,scan_error,scan_found_valid,
 output reg [31:0] scan_found_cluster,scan_found_size,
 output reg [2:0] scan_found_total,
 output reg load_done,load_error, output reg [2:0] bmp_error,
 output reg [7:0] fat_error, output [3:0] state_code,
 output write_req,input write_req_ack,input write_ready,
 output bmp_data_wr_en,output [23:0] bmp_data,
 output sd_sec_read,output [31:0] sd_sec_read_addr,
 input [7:0] sd_sec_read_data,input sd_sec_read_data_valid,sd_sec_read_end,sd_sec_read_failed,
 output [7:0] bmp_alpha,  // alpha (scene T) beside bmp_data; FF for 24bpp
 // Scene kind of the file being loaded, from BMP header bytes 6-7 (hazard,
 // role; tools/make_scene_pack.py format 3): {hazard[2:0],role[2:0]}, 0 when
 // either byte is outside 1..4, as in ordinary BMPs. Valid from the header
 // through load_done.
 output [5:0] bmp_kind,
 // FONT.BIN (bin_sel 0) / TEXT.BIN (1) bytes at their file offset. A flag is
 // cleared when a scan starts and set when its file has been read without
 // error; TEXT.BIN must also start with "TX" and version 1.
 output bin_wr,bin_sel,output [11:0] bin_addr,output [7:0] bin_data,
 output reg font_loaded,text_loaded
);
 localparam IDLE=0,SCAN=1,SELECT=2,HEADER_RESET=3,HEADER_REQ=4,
 HEADER_WAIT=5,HEADER_CHECK=6,SCAN_FINISH=7,WRITE_WAIT=8,
 START_FILE=9,READ_FILE=10,DRAIN=11,RESULT=12,HEADER_SHIFT=13,HEADER_ADD=14,SELECT_CHECK=15;
 reg [3:0] state;
 // FONT/TEXT load: a sub-state of SCAN_FINISH, so the picture paths keep the
 // four-bit state decode.
 localparam BIN_SELECT=0,BIN_CHECK=1,BIN_START=2,BIN_READ=3,BIN_NEXT=4,BIN_DONE=5;
 reg [2:0] bin_state;
 wire bin_phase=(state==SCAN_FINISH);
 wire bin_reading=bin_phase && bin_state==BIN_READ;
 reg scan_go,file_go;
 reg [2:0] candidate;
 reg [31:0] task_cluster,task_size,header_lba;
 reg [7:0] io_error;
 reg stream_finished,decode_finished;
 wire volume_done,volume_busy,stream_busy,stream_done,stream_valid;
 wire [7:0] volume_error,stream_error,stream_byte,spc;
 wire [31:0] fat_lba,data_lba,max_cluster,stream_offset;
 wire [3:0] mask;
 wire [31:0] clusters[0:3],sizes[0:3];
 wire scan_req,file_req;wire [31:0] scan_lba,file_lba;
 wire sector_busy,sector_valid,sector_done;
 wire [7:0] sector_byte,sector_error;wire [8:0] sector_index;
 wire scan_owner=(state==SCAN);
 wire bin_owner=bin_phase && (bin_state==BIN_START || bin_state==BIN_READ);
 wire file_owner=(state==START_FILE || state==READ_FILE || state==DRAIN || bin_owner);
 wire abort_file=(state==DRAIN || state==RESULT || state==IDLE || load_cancel || (bin_phase && !bin_owner));
 wire [2:0] decode_error;wire decode_done;
 wire request_allowed=(state==READ_FILE && decode_error==0 && !load_cancel) || bin_reading;
 reg bin_index,bin_bad,text_magic;
 wire font_found,text_found,font_big,text_big;
 wire [27:0] font_cluster,text_cluster;
 wire [12:0] font_size,text_size;
 wire [27:0] bin_cluster=bin_index ? text_cluster : font_cluster;
 wire [12:0] bin_size=bin_index ? text_size : font_size;
 wire header_match;wire [33:0] required_end;
 wire [31:0] header_file_len;
 reg header_go;
 reg selected_bad;
 reg [1:0] found_slot[0:3];   // scanner slot of each accepted image
 wire [1:0] select_slot=(LOAD_BY_INDEX && state==IDLE) ? found_slot[load_index] : candidate[1:0];
 wire [31:0] selected_cluster=clusters[select_slot];
 wire [31:0] selected_size=sizes[select_slot];
 function [2:0] spc_shift;
 input [7:0] v;
 begin case(v) 2:spc_shift=1;4:spc_shift=2;8:spc_shift=3;16:spc_shift=4;
 32:spc_shift=5;64:spc_shift=6;128:spc_shift=7;default:spc_shift=0;endcase end
 endfunction
 reg [2:0] header_cluster_shift;
reg [2:0] header_shift_count;   // header_lba is shifted one bit per cycle
 always @(posedge clk or posedge rst)begin
  if(rst)header_cluster_shift<=0;
  else header_cluster_shift<=spc_shift(spc);
 end
 assign ready=(state==IDLE && sd_init_done);
 assign state_code=(state==IDLE)?4'd1:((state<=SCAN_FINISH || state==SELECT_CHECK)?4'd2:4'd3);

 assign write_req=(state==WRITE_WAIT && !load_cancel);
 wire pixel_valid;
 wire pixel_ready=state==READ_FILE && decode_error==0 && stream_error==0 && !load_cancel && (!SCALE_ENABLE || write_ready);
 assign bmp_data_wr_en=pixel_valid && pixel_ready;
 wire data_permit;
 wire stream_permit=bin_reading || data_permit;
 assign bin_wr=bin_reading && stream_valid;
 assign bin_sel=bin_index;
 assign bin_addr=stream_offset[11:0];
 assign bin_data=stream_byte;
 assign audio_spc=spc;
 assign audio_fat_lba=fat_lba;assign audio_data_lba=data_lba;assign audio_max_cluster=max_cluster;
 assign a_byte=sector_byte;assign a_index=sector_index;
 // Register the scanner response bundle together. This separates the shared
 // owner/state decode from the scanner's byte-field write enables.
 reg scan_sector_valid,scan_sector_done;
 reg [7:0] scan_sector_byte,scan_sector_error;
 reg [8:0] scan_sector_index;
 always @(posedge clk or posedge rst)begin
  if(rst)begin scan_sector_valid<=0;scan_sector_done<=0;scan_sector_byte<=0;scan_sector_error<=0;scan_sector_index<=0;end
  else begin
   scan_sector_valid<=scan_owner && sector_valid;scan_sector_done<=scan_owner && sector_done;
   scan_sector_byte<=sector_byte;scan_sector_error<=sector_error;scan_sector_index<=sector_index;
  end
 end
 fat32_volume_scanner #(.SCAN_AUDIO(SCAN_AUDIO),.SCAN_TEXT(SCAN_TEXT),.MAX_VISITED_CLUSTERS(MAX_VISITED_CLUSTERS)) scanner(
 .font_found(font_found),.text_found(text_found),.font_big(font_big),.text_big(text_big),
 .font_cluster(font_cluster),.text_cluster(text_cluster),.font_size(font_size),.text_size(text_size),
 .clk(clk),.rst_n(!rst),.scan_start(scan_go),.scan_busy(volume_busy),.scan_done(volume_done),.fs_error(volume_error),
 .partition_lba(),.sectors_per_cluster(spc),.fat_start_lba(fat_lba),.data_start_lba(data_lba),.max_cluster(max_cluster),
 .resource_valid(mask),.audio_slot(audio_slot),.snd_found(snd_found),.audio_found(audio_found),.audio_cluster(audio_cluster),.audio_size(audio_size),.resource0_cluster(clusters[0]),.resource1_cluster(clusters[1]),.resource2_cluster(clusters[2]),.resource3_cluster(clusters[3]),
 .resource0_size(sizes[0]),.resource1_size(sizes[1]),.resource2_size(sizes[2]),.resource3_size(sizes[3]),
 .sector_req(scan_req),.sector_lba(scan_lba),.sector_busy(sector_busy),.sector_valid(scan_sector_valid),
 .sector_byte(scan_sector_byte),.sector_byte_index(scan_sector_index),.sector_done(scan_sector_done),.sector_error(scan_sector_error));
 // Keep the file response in one pipeline bundle: the last byte may arrive
 // with done. Cancellation discards the queued response while the service
 // continues draining the physical read under its existing ownership.
 reg file_sector_valid,file_sector_done;
 reg [7:0] file_sector_byte,file_sector_error;
 reg [8:0] file_sector_index;
 always @(posedge clk or posedge rst)begin
  if(rst)begin
   file_sector_valid<=0;file_sector_done<=0;
   file_sector_byte<=0;file_sector_error<=0;file_sector_index<=0;
  end else begin
   file_sector_valid<=file_owner && !abort_file && sector_valid;
   file_sector_done<=file_owner && !abort_file && sector_done;
   file_sector_byte<=sector_byte;file_sector_error<=sector_error;file_sector_index<=sector_index;
  end
 end
 fat32_file_streamer #(.MAX_VISITED_CLUSTERS(SCALE_ENABLE?16384:MAX_VISITED_CLUSTERS),.DATA_GATE_ENABLE(SCALE_ENABLE)) streamer(
 .clk(clk),.rst_n(!rst && !abort_file),.file_start(file_go),.data_permit(stream_permit),.first_cluster(task_cluster),.file_size(task_size),
 .sectors_per_cluster(spc),.fat_start_lba(fat_lba),.data_start_lba(data_lba),.max_cluster(max_cluster),
 .file_busy(stream_busy),.file_done(stream_done),.file_valid(stream_valid),.file_byte(stream_byte),.file_byte_offset(stream_offset),.fs_error(stream_error),
 .sector_req(file_req),.sector_lba(file_lba),.sector_busy(sector_busy),.sector_valid(file_sector_valid),
 .sector_byte(file_sector_byte),.sector_byte_index(file_sector_index),.sector_done(file_sector_done),.sector_error(file_sector_error));
 // Shared service retains per-client ownership through cancellation and drain.
 sd_sector_service #(.CLK_FREQ_HZ(CLK_FREQ_HZ),.TIMEOUT_MS(TIMEOUT_MS)) adapter(
 .clk(clk),.rst(rst),.p_req(scan_owner?scan_req:(file_owner?(file_req && request_allowed):header_go)),
 .p_lba(scan_owner?scan_lba:(file_owner?file_lba:header_lba)),.p_cancel(load_cancel),
 .p_busy(sector_busy),.p_accepted(),.p_valid(sector_valid),.p_done(sector_done),.p_error(sector_error),
 .a_req(SCAN_AUDIO ? a_req : 1'b0),.a_lba(a_lba),.a_cancel(SCAN_AUDIO ? a_cancel : 1'b0),.a_urgent(a_urgent),.a_enable(SCAN_AUDIO!=0),
 .a_busy(a_busy),.a_accepted(),.a_valid(a_valid),.a_done(a_done),.a_error(a_error),
 .sector_byte(sector_byte),.sector_index(sector_index),
 .sd_sec_read(sd_sec_read),.sd_sec_read_addr(sd_sec_read_addr),.sd_sec_read_data(sd_sec_read_data),
 .sd_sec_read_data_valid(sd_sec_read_data_valid),.sd_sec_read_end(sd_sec_read_end),.sd_sec_read_failed(sd_sec_read_failed));
 bmp_header_check #(.ALLOW_32(1),.RANGE_DIMENSIONS(SCALE_ENABLE)) preflight(
 .clk(clk),.rst(rst || state==HEADER_RESET),.file_valid(state==HEADER_WAIT && sector_valid),
 .file_byte(sector_byte),.file_byte_offset({23'd0,sector_index}),.bmp_width(bmp_width),.bmp_height(bmp_height),
 .file_len(header_file_len),.pixel_offset(),.width(),.height(),.required_end(required_end),.header_match(header_match),
 .skip_format(),.header_complete(),.is_32(),.row_stride(),.expected_pixels());
 generate if(SCALE_ENABLE)begin:g_scale
 bmp_scale_stream scaled(
 .clk(clk),.rst(rst || state==WRITE_WAIT || load_cancel),.file_start(file_go),.file_size(task_size),
 .file_valid(stream_valid && state==READ_FILE),.file_byte(stream_byte),.file_byte_offset(stream_offset),
 .file_end(stream_done),.upstream_error(stream_error),.data_permit(data_permit),
 .pixel_valid(pixel_valid),.pixel_ready(pixel_ready),.pixel_rgb(bmp_data),.done(decode_done),.error(decode_error),.pixel_alpha(bmp_alpha));
 end else begin:g_fixed
 assign data_permit=1'b1;
 bmp24_decoder #(.RUNTIME_DIMENSIONS(1),.ALLOW_32(1)) decoder(
 .clk(clk),.rst(rst || state==WRITE_WAIT || load_cancel),.expected_width(bmp_width),.expected_height(bmp_height),
 .file_start(file_go),.file_size(task_size),.file_valid(stream_valid && state==READ_FILE),.file_byte(stream_byte),
 .file_byte_offset(stream_offset),.file_end(stream_done),.upstream_error(stream_error),
 .header_accepted(),.pixel_valid(pixel_valid),.pixel_rgb(bmp_data),.pixel_x(),.pixel_y(),
 .frame_commit(),.bmp_done(decode_done),.bmp_error(decode_error),
 .pixel_ready(1'b1),.file_ready(),.image_width(),.image_height(),.pixel_alpha(bmp_alpha));
 end endgenerate
 reg [7:0] kind_hazard,kind_role;
 always @(posedge clk or posedge rst)begin
  if(rst)begin kind_hazard<=0;kind_role<=0;end
  else if(file_go)begin kind_hazard<=0;kind_role<=0;end
  else if(stream_valid && state==READ_FILE)begin
   if(stream_offset==32'd6)kind_hazard<=stream_byte;
   if(stream_offset==32'd7)kind_role<=stream_byte;
  end
 end
 assign bmp_kind=(kind_hazard>=8'd1 && kind_hazard<=8'd4 && kind_role>=8'd1 && kind_role<=8'd4) ?
  {kind_hazard[2:0],kind_role[2:0]} : 6'd0;
 localparam integer WAIT_CYCLES=(CLK_FREQ_HZ/1000)*TIMEOUT_MS;
 reg [31:0] ack_wait;
 always @(posedge clk or posedge rst)begin
 if(rst)begin
 state<=IDLE;scan_go<=0;file_go<=0;header_go<=0;scan_done<=0;scan_error<=0;
 scan_found_valid<=0;scan_found_cluster<=0;scan_found_size<=0;scan_found_total<=0;
 load_done<=0;load_error<=0;bmp_error<=0;fat_error<=0;candidate<=0;
 task_cluster<=0;task_size<=0;header_lba<=0;header_shift_count<=0;found_slot[0]<=0;found_slot[1]<=0;found_slot[2]<=0;found_slot[3]<=0;io_error<=0;stream_finished<=0;decode_finished<=0;ack_wait<=0;selected_bad<=0;
 bin_index<=0;bin_bad<=0;text_magic<=0;font_loaded<=0;text_loaded<=0;bin_state<=BIN_DONE;
 end else begin
 // TEXT.BIN header bytes 0-2 must read "TX",1.
 if(file_go)text_magic<=1'b1;
 else if(bin_wr && bin_index && stream_offset<3 &&
         stream_byte!=(stream_offset[1] ? 8'd1 : stream_offset[0] ? "X" : "T"))text_magic<=1'b0;
 scan_go<=0;file_go<=0;header_go<=0;scan_found_valid<=0;load_done<=0;load_error<=0;scan_error<=0;
 // Observe file errors with the same response bundle consumed by streamer.
 // This preserves the existing distinction between a retryable stream error
 // and a previously latched physical timeout.
 if((file_owner ? file_sector_done : sector_done) &&
    (file_owner ? file_sector_error : sector_error)!=0)
  io_error<=file_owner ? file_sector_error : sector_error;
 // Cancel only the current file and drain an already issued sector. Scanner
 // geometry stays intact for a retry or the next cached image.
 if(load_cancel) begin
  if(!sector_busy) state<=IDLE;
  else state<=DRAIN;
 end else case(state)
 IDLE:if(sd_init_done)begin
 if(scan_start)begin scan_done<=0;scan_found_total<=0;candidate<=0;fat_error<=0;bmp_error<=0;io_error<=0;scan_go<=1;state<=SCAN;
 bin_index<=0;font_loaded<=0;text_loaded<=0;bin_state<=SCAN_TEXT ? BIN_SELECT : BIN_DONE;end
 else if(load_start)begin task_cluster<=LOAD_BY_INDEX ? selected_cluster : load_cluster;task_size<=LOAD_BY_INDEX ? selected_size : load_size;io_error<=0;fat_error<=0;bmp_error<=0;
 stream_finished<=0;decode_finished<=0;ack_wait<=0;state<=WRITE_WAIT;end
 end
 SCAN:if(volume_done)begin
 if(volume_error!=0)begin fat_error<=(volume_error==8'h10 && io_error!=0)?io_error:volume_error;bmp_error<=2;scan_error<=1;bin_state<=BIN_DONE;state<=SCAN_FINISH;end
 else state<=SELECT;
 end
 SELECT:if(!sector_busy)begin
 if(candidate==4)state<=SCAN_FINISH;
 else begin
 selected_bad<=!mask[candidate[1:0]] || selected_size<54 || selected_cluster<2 || selected_cluster>max_cluster;
 state<=SELECT_CHECK;end
 end
 SELECT_CHECK:begin
 if(selected_bad)begin candidate<=candidate+1'b1;state<=SELECT;end
 else begin task_cluster<=selected_cluster;task_size<=selected_size;
 header_lba<=selected_cluster-2;header_shift_count<=header_cluster_shift;state<=HEADER_SHIFT;end
 end
 HEADER_SHIFT:if(header_shift_count!=0)begin header_lba<={header_lba[30:0],1'b0};header_shift_count<=header_shift_count-1'b1;end
 else state<=HEADER_ADD;
 HEADER_ADD:begin header_lba<=data_lba+header_lba;state<=HEADER_RESET;end
 HEADER_RESET:state<=HEADER_REQ;
 HEADER_REQ:if(!sector_busy)begin header_go<=1;state<=HEADER_WAIT;end
 HEADER_WAIT:if(sector_done)begin
 if(sector_error!=0)begin fat_error<=sector_error;bmp_error<=2;scan_error<=1;bin_state<=BIN_DONE;state<=SCAN_FINISH;end
 else state<=HEADER_CHECK;
 end
 HEADER_CHECK:begin
 if(header_match && required_end<={2'b0,task_size})begin
 scan_found_cluster<=task_cluster;scan_found_size<=task_size;scan_found_valid<=1;scan_found_total<=scan_found_total+1'b1;
 if(!scan_found_total[2])found_slot[scan_found_total[1:0]]<=candidate[1:0];end
 candidate<=candidate+1'b1;state<=SELECT;
 end
 SCAN_FINISH:case(bin_state)
  BIN_SELECT:begin
   bin_bad<=!(bin_index ? text_found : font_found) || (bin_index ? text_big : font_big) ||
    bin_size==0 || bin_size>13'd4096 || (bin_index && bin_size<4) ||
    bin_cluster<2 || {4'd0,bin_cluster}>max_cluster;
   bin_state<=BIN_CHECK;
  end
  BIN_CHECK:if(bin_bad)bin_state<=BIN_NEXT;
  else begin task_cluster<={4'd0,bin_cluster};task_size<={19'd0,bin_size};bin_state<=BIN_START;end
  BIN_START:if(!sector_busy && !stream_busy)begin file_go<=1;bin_state<=BIN_READ;end
  BIN_READ:if(stream_done)begin
   if(stream_error==0)begin
    if(!bin_index)font_loaded<=1'b1;
    else text_loaded<=text_magic;
   end
   bin_state<=BIN_NEXT;
  end
  BIN_NEXT:if(!sector_busy)begin
   if(bin_index)bin_state<=BIN_DONE;
   else begin bin_index<=1'b1;bin_state<=BIN_SELECT;end
  end
  default:if(!sector_busy)begin scan_done<=1;state<=IDLE;end
 endcase


 WRITE_WAIT:if(write_req_ack)state<=START_FILE;
 else if(ack_wait>=WAIT_CYCLES-1)begin bmp_error<=2;fat_error<=8'h11;state<=RESULT;end
 else ack_wait<=ack_wait+1'b1;
 START_FILE:begin file_go<=1;state<=READ_FILE;end
 READ_FILE:begin
 if(stream_done)stream_finished<=1;
 if(decode_done)decode_finished<=1;
 if(stream_error!=0)begin fat_error<=(stream_error==8'h10 && io_error!=0)?io_error:stream_error;
 bmp_error<=(stream_error==8'h10 && (io_error==8'h10 || io_error==8'h11))?3'd2:3'd3;state<=DRAIN;end
 else if(decode_error!=0)begin bmp_error<=decode_error;state<=DRAIN;end
 else if((stream_finished || stream_done) && (decode_finished || decode_done))state<=DRAIN;
 end
 DRAIN:begin
 if(sector_done && (sector_error==8'h10 || sector_error==8'h11))begin bmp_error<=2;fat_error<=sector_error;end
 if(!sector_busy)state<=RESULT;
 end
 RESULT:begin if(bmp_error==0)load_done<=1;else load_error<=1;state<=IDLE;end
 default:state<=IDLE;
 endcase
 end end
endmodule
