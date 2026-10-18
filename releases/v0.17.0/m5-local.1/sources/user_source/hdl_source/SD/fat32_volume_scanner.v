// Read-only FAT32 root directory scanner. Derived from the lesson's resource
// contract; fields are captured as bytes arrive, without a 512-byte mux array.
// With SCAN_AUDIO the scanner also records BGM.PCM and the stage files
// SND1-4.PCM; audio_found/cluster/size report the file chosen by audio_slot
// (0-3 SND1-4, otherwise BGM). With SCAN_TEXT it also records FONT.BIN and
// TEXT.BIN; their size is kept as 13 bits plus a flag for 8192 and above.
module fat32_volume_scanner #(
    parameter integer MAX_VISITED_CLUSTERS = 8192,
    parameter integer SCAN_AUDIO = 0,
    parameter integer SCAN_TEXT = 0
)(
    input wire clk, input wire rst_n, input wire scan_start,
    output wire scan_busy, output reg scan_done, output reg [7:0] fs_error,
    output reg [31:0] partition_lba,
    output reg [7:0] sectors_per_cluster,
    output reg [31:0] fat_start_lba, data_start_lba, max_cluster,
    output reg [3:0] resource_valid,
    output reg [31:0] resource0_cluster, resource1_cluster, resource2_cluster, resource3_cluster,
    output reg [31:0] resource0_size, resource1_size, resource2_size, resource3_size,
    input wire [2:0] audio_slot, output reg [3:0] snd_found,
    output wire audio_found, output wire [31:0] audio_cluster, audio_size,
    output reg font_found, text_found, font_big, text_big,
    output reg [27:0] font_cluster, text_cluster,
    output reg [12:0] font_size, text_size,
    output reg sector_req, output reg [31:0] sector_lba,
    input wire sector_busy, sector_valid, input wire [7:0] sector_byte,
    input wire [8:0] sector_byte_index,
    input wire sector_done, input wire [7:0] sector_error
);
    localparam IDLE=0, ZERO_REQ=1, ZERO_WAIT=2, ZERO_PARSE=3,
        BOOT_REQ=4, BOOT_WAIT=5, BOOT_PARSE=6, LAYOUT=7, ROOT=8,
        DIR_REQ=9, DIR_WAIT=10, DIR_NEXT=11, FAT_REQ=12, FAT_WAIT=13,
        FAT_PARSE=14, FINISH=15, LAYOUT_SUB=16, LAYOUT_SHIFT=17, LAYOUT_MAX=18, LAYOUT_CHECK=19, ROOT_SHIFT=20, ROOT_ADD=21,
        LAYOUT_ACCEPT=22,FAT_CHECK=23,LAYOUT_LOAD=24;
    localparam ERR_SECTOR=8'h10, ERR_SIGNATURE=8'h20, ERR_BPB=8'h21,
        ERR_LOOP=8'h23, ERR_RANGE=8'h24, ERR_LIMIT=8'h26;
    localparam COUNT_BITS=$clog2(MAX_VISITED_CLUSTERS+1);
    reg [4:0] state;
    reg [15:0] bytes_per_sector, reserved, root_entries, fat16, flags, signature;
    reg [7:0] spc, fat_count;
    reg [31:0] total_sectors, fat_sectors, root_cluster;
    reg [31:0] mbr_lba[0:3];
    reg [3:0] mbr_match;
    reg [2:0] cluster_shift;
    reg [31:0] fat_span, current_cluster;
    reg [7:0] dir_sector;
    reg [COUNT_BITS-1:0] visited;
    reg dir_end, name_match;
    reg audio_match, snd_match, font_match, text_match;
    reg bgm_found;
    reg [31:0] bgm_cluster, bgm_size;
    reg [31:0] snd_cluster[0:3], snd_size[0:3];
    assign audio_found=audio_slot[2] ? bgm_found : snd_found[audio_slot[1:0]];
    assign audio_cluster=audio_slot[2] ? bgm_cluster : snd_cluster[audio_slot[1:0]];
    assign audio_size=audio_slot[2] ? bgm_size : snd_size[audio_slot[1:0]];
    reg [1:0] resource_index;
    reg [31:0] entry_cluster, entry_size, fat_entry;
    wire [31:0] next_cluster={4'b0,fat_entry[27:0]};
    wire [8:0] fat_offset={current_cluster[6:0],2'b00};
    reg [31:0] overhead,data_sectors,cluster_count,partition_reserved,cluster_offset;
    reg data_borrow;   // total_sectors<overhead, from the LAYOUT_SUB subtraction
    reg [2:0] shift_count;   // layout and root shifts move one bit per cycle
    reg layout_bad,fat_end,fat_bad,fat_loop,fat_limit;
    wire bpb_fields_ok=(bytes_per_sector==512) && spc!=0 && ((spc & (spc-1'b1))==0) &&
        reserved!=0 && (fat_count==1 || fat_count==2) && root_entries==0 && fat16==0 &&
        total_sectors!=0 && fat_sectors!=0 && root_cluster>=2 &&
        (!flags[7] || {4'd0,flags[3:0]}<fat_count);
    // BPB fields finish at byte 47, well before the sector-end parse states.
    // Register their joint test so it is not in the MBR address enable cone.
    // Signature (bytes 510/511) and sector_error retain their original checks.
    reg bpb_ok;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n)bpb_ok<=0;
        else bpb_ok<=bpb_fields_ok;
    end
    assign scan_busy=(state!=IDLE);

    function [2:0] spc_shift;
        input [7:0] value;
        begin
            case(value)
                2:spc_shift=1;4:spc_shift=2;8:spc_shift=3;16:spc_shift=4;
                32:spc_shift=5;64:spc_shift=6;128:spc_shift=7;
                default:spc_shift=0;
            endcase
        end
    endfunction
    task fail;
        input [7:0] code;
        begin fs_error<=code;state<=FINISH;end
    endtask
    // Names, attributes and duplicate status are settled before byte 30.
    // Register per-destination enables there; commit at byte 31 as before.
    // Hold the enables across byte gaps and clear them after the commit.
    (* keep = "true" *) reg [10:0] entry_accept;
    integer k;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) entry_accept<=0;
        else if(state!=DIR_WAIT) entry_accept<=0;
        else if(sector_valid) begin
            if(sector_byte_index[4:0]==30) begin
                entry_accept[0]<=!dir_end && name_match && resource_index==0 && !resource_valid[0];
                entry_accept[1]<=!dir_end && name_match && resource_index==1 && !resource_valid[1];
                entry_accept[2]<=!dir_end && name_match && resource_index==2 && !resource_valid[2];
                entry_accept[3]<=!dir_end && name_match && resource_index==3 && !resource_valid[3];
                entry_accept[4]<=!dir_end && audio_match && !bgm_found;
                for(k=0;k<4;k=k+1)
                    entry_accept[5+k]<=!dir_end && snd_match && resource_index==k && !snd_found[k];
                entry_accept[9]<=!dir_end && font_match && !font_found;
                entry_accept[10]<=!dir_end && text_match && !text_found;
            end else if(sector_byte_index[4:0]==31) entry_accept<=0;
        end
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            resource_valid<=0;bgm_found<=0;bgm_cluster<=0;bgm_size<=0;snd_found<=0;
            resource0_cluster<=0;resource1_cluster<=0;resource2_cluster<=0;resource3_cluster<=0;
            resource0_size<=0;resource1_size<=0;resource2_size<=0;resource3_size<=0;
            for(k=0;k<4;k=k+1)begin snd_cluster[k]<=0;snd_size[k]<=0;end
            font_found<=0;text_found<=0;font_big<=0;text_big<=0;font_cluster<=0;text_cluster<=0;font_size<=0;text_size<=0;
        end else if(state==IDLE && scan_start) begin
            resource_valid<=0;bgm_found<=0;bgm_cluster<=0;bgm_size<=0;snd_found<=0;
            resource0_cluster<=0;resource1_cluster<=0;resource2_cluster<=0;resource3_cluster<=0;
            resource0_size<=0;resource1_size<=0;resource2_size<=0;resource3_size<=0;
            for(k=0;k<4;k=k+1)begin snd_cluster[k]<=0;snd_size[k]<=0;end
            font_found<=0;text_found<=0;
        end else if(sector_valid && sector_byte_index[4:0]==31) begin
            if(entry_accept[9])begin font_found<=1;font_cluster<=entry_cluster[27:0];font_size<=entry_size[12:0];
                font_big<=sector_byte!=0 || entry_size[23:13]!=0;end
            if(entry_accept[10])begin text_found<=1;text_cluster<=entry_cluster[27:0];text_size<=entry_size[12:0];
                text_big<=sector_byte!=0 || entry_size[23:13]!=0;end
            if(entry_accept[0])begin resource_valid[0]<=1;resource0_cluster<=entry_cluster;resource0_size<={sector_byte,entry_size[23:0]};end
            if(entry_accept[1])begin resource_valid[1]<=1;resource1_cluster<=entry_cluster;resource1_size<={sector_byte,entry_size[23:0]};end
            if(entry_accept[2])begin resource_valid[2]<=1;resource2_cluster<=entry_cluster;resource2_size<={sector_byte,entry_size[23:0]};end
            if(entry_accept[3])begin resource_valid[3]<=1;resource3_cluster<=entry_cluster;resource3_size<={sector_byte,entry_size[23:0]};end
            if(entry_accept[4])begin bgm_found<=1;bgm_cluster<=entry_cluster;bgm_size<={sector_byte,entry_size[23:0]};end
            for(k=0;k<4;k=k+1)
                if(entry_accept[5+k])begin snd_found[k]<=1;snd_cluster[k]<=entry_cluster;snd_size[k]<={sector_byte,entry_size[23:0]};end
        end
    end
    integer j;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=IDLE;scan_done<=0;fs_error<=0;sector_req<=0;sector_lba<=0;
            layout_bad<=0;fat_end<=0;fat_bad<=0;fat_loop<=0;fat_limit<=0;
            partition_lba<=0;sectors_per_cluster<=0;fat_start_lba<=0;data_start_lba<=0;max_cluster<=0;
            bytes_per_sector<=0;reserved<=0;root_entries<=0;fat16<=0;flags<=0;signature<=0;
            spc<=0;fat_count<=0;total_sectors<=0;fat_sectors<=0;root_cluster<=0;
            mbr_match<=0;for(j=0;j<4;j=j+1)mbr_lba[j]<=0;
            overhead<=0;data_sectors<=0;data_borrow<=0;shift_count<=0;cluster_count<=0;partition_reserved<=0;cluster_offset<=0;cluster_shift<=0;fat_span<=0;current_cluster<=0;dir_sector<=0;visited<=0;
            dir_end<=0;name_match<=0;resource_index<=0;entry_cluster<=0;entry_size<=0;fat_entry<=0;
            audio_match<=0;snd_match<=0;font_match<=0;text_match<=0;
        end else begin
            scan_done<=0;sector_req<=0;
            if(sector_valid && (state==ZERO_WAIT || state==BOOT_WAIT)) begin
                case(sector_byte_index)
                    11:bytes_per_sector[7:0]<=sector_byte;12:bytes_per_sector[15:8]<=sector_byte;
                    13:spc<=sector_byte;
                    14:reserved[7:0]<=sector_byte;15:reserved[15:8]<=sector_byte;
                    16:fat_count<=sector_byte;
                    17:root_entries[7:0]<=sector_byte;18:root_entries[15:8]<=sector_byte;
                    22:fat16[7:0]<=sector_byte;23:fat16[15:8]<=sector_byte;
                    32:total_sectors[7:0]<=sector_byte;33:total_sectors[15:8]<=sector_byte;
                    34:total_sectors[23:16]<=sector_byte;35:total_sectors[31:24]<=sector_byte;
                    36:fat_sectors[7:0]<=sector_byte;37:fat_sectors[15:8]<=sector_byte;
                    38:fat_sectors[23:16]<=sector_byte;39:fat_sectors[31:24]<=sector_byte;
                    40:flags[7:0]<=sector_byte;41:flags[15:8]<=sector_byte;
                    44:root_cluster[7:0]<=sector_byte;45:root_cluster[15:8]<=sector_byte;
                    46:root_cluster[23:16]<=sector_byte;47:root_cluster[31:24]<={4'b0,sector_byte[3:0]};
                    510:signature[7:0]<=sector_byte;511:signature[15:8]<=sector_byte;
                    default:;
                endcase
                if(state==ZERO_WAIT) begin
                    for(j=0;j<4;j=j+1) begin
                        if(sector_byte_index==450+16*j) mbr_match[j]<=(sector_byte==8'h0b || sector_byte==8'h0c);
                        if(sector_byte_index==454+16*j)mbr_lba[j][7:0]<=sector_byte;
                        if(sector_byte_index==455+16*j)mbr_lba[j][15:8]<=sector_byte;
                        if(sector_byte_index==456+16*j)mbr_lba[j][23:16]<=sector_byte;
                        if(sector_byte_index==457+16*j)mbr_lba[j][31:24]<=sector_byte;
                    end
                end
            end
            if(state==DIR_WAIT && sector_valid && !dir_end) begin
                case(sector_byte_index[4:0])
                    0:begin name_match<=(sector_byte=="P");audio_match<=SCAN_AUDIO && (sector_byte=="B");snd_match<=SCAN_AUDIO && (sector_byte=="S");if(sector_byte==0)dir_end<=1;
                        font_match<=SCAN_TEXT && (sector_byte=="F");text_match<=SCAN_TEXT && (sector_byte=="T");end
                    1:begin name_match<=name_match && sector_byte=="I";audio_match<=audio_match && sector_byte=="G";snd_match<=snd_match && sector_byte=="N";
                        font_match<=font_match && sector_byte=="O";text_match<=text_match && sector_byte=="E";end
                    2:begin name_match<=name_match && sector_byte=="C";audio_match<=audio_match && sector_byte=="M";snd_match<=snd_match && sector_byte=="D";
                        font_match<=font_match && sector_byte=="N";text_match<=text_match && sector_byte=="X";end
                    3:begin name_match<=name_match && sector_byte>="1" && sector_byte<="4";audio_match<=audio_match && sector_byte==" ";
                        snd_match<=snd_match && sector_byte>="1" && sector_byte<="4";
                        font_match<=font_match && sector_byte=="T";text_match<=text_match && sector_byte=="T";
                        resource_index<=sector_byte[1:0]-2'd1;end
                    4,5,6,7:begin name_match<=name_match && sector_byte==" ";audio_match<=audio_match && sector_byte==" ";snd_match<=snd_match && sector_byte==" ";
                        font_match<=font_match && sector_byte==" ";text_match<=text_match && sector_byte==" ";end
                    8:begin name_match<=name_match && sector_byte=="B";audio_match<=audio_match && sector_byte=="P";snd_match<=snd_match && sector_byte=="P";
                        font_match<=font_match && sector_byte=="B";text_match<=text_match && sector_byte=="B";end
                    9:begin name_match<=name_match && sector_byte=="M";audio_match<=audio_match && sector_byte=="C";snd_match<=snd_match && sector_byte=="C";
                        font_match<=font_match && sector_byte=="I";text_match<=text_match && sector_byte=="I";end
                    10:begin name_match<=name_match && sector_byte=="P";audio_match<=audio_match && sector_byte=="M";snd_match<=snd_match && sector_byte=="M";
                        font_match<=font_match && sector_byte=="N";text_match<=text_match && sector_byte=="N";end
                    // Accept read-only/hidden/system/archive files; exclude LFN,
                    // volume labels and subdirectories by their attribute bits.
                    11:begin name_match<=name_match && (sector_byte & 8'h18)==0;audio_match<=audio_match && (sector_byte & 8'h18)==0;
                        snd_match<=snd_match && (sector_byte & 8'h18)==0;
                        font_match<=font_match && (sector_byte & 8'h18)==0;text_match<=text_match && (sector_byte & 8'h18)==0;end
                    20:entry_cluster[23:16]<=sector_byte;
                    21:entry_cluster[31:24]<={4'b0,sector_byte[3:0]};
                    26:entry_cluster[7:0]<=sector_byte;27:entry_cluster[15:8]<=sector_byte;
                    28:entry_size[7:0]<=sector_byte;29:entry_size[15:8]<=sector_byte;30:entry_size[23:16]<=sector_byte;
                    default:;
                endcase
            end
            if(state==FAT_WAIT && sector_valid) begin
                if(sector_byte_index==fat_offset)fat_entry[7:0]<=sector_byte;
                if(sector_byte_index==fat_offset+9'd1)fat_entry[15:8]<=sector_byte;
                if(sector_byte_index==fat_offset+9'd2)fat_entry[23:16]<=sector_byte;
                if(sector_byte_index==fat_offset+9'd3)fat_entry[31:24]<=sector_byte;
            end
            case(state)
                IDLE:if(scan_start) begin
                    fs_error<=0;partition_lba<=0;mbr_match<=0;dir_end<=0;
                    sector_lba<=0;state<=ZERO_REQ;
                end
                ZERO_REQ:if(!sector_busy)begin sector_req<=1;state<=ZERO_WAIT;end
                ZERO_WAIT:if(sector_done)begin if(sector_error!=0)fail(ERR_SECTOR);else state<=ZERO_PARSE;end
                ZERO_PARSE:begin
                    if(signature!=16'haa55)fail(ERR_SIGNATURE);
                    // An MBR can also begin EB/E9; recognize actual BPB fields.
                    else if(bpb_ok)state<=BOOT_PARSE;
                    else if(mbr_match!=0)begin
                        if(mbr_match[0])begin partition_lba<=mbr_lba[0];sector_lba<=mbr_lba[0];end
                        else if(mbr_match[1])begin partition_lba<=mbr_lba[1];sector_lba<=mbr_lba[1];end
                        else if(mbr_match[2])begin partition_lba<=mbr_lba[2];sector_lba<=mbr_lba[2];end
                        else begin partition_lba<=mbr_lba[3];sector_lba<=mbr_lba[3];end
                        state<=BOOT_REQ;
                    end else fail(ERR_BPB);
                end
                BOOT_REQ:if(!sector_busy)begin sector_req<=1;state<=BOOT_WAIT;end
                BOOT_WAIT:if(sector_done)begin if(sector_error!=0)fail(ERR_SECTOR);else state<=BOOT_PARSE;end
                BOOT_PARSE:begin
                    if(signature!=16'haa55)fail(ERR_SIGNATURE);
                    else if(!bpb_ok)fail(ERR_BPB);
                    else begin
                        sectors_per_cluster<=spc;cluster_shift<=spc_shift(spc);
                        fat_span<=fat_count==2 ? fat_sectors<<1 : fat_sectors;
                        partition_reserved<=partition_lba+{16'd0,reserved};
                        state<=LAYOUT;
                    end
                end
                LAYOUT:begin
                    overhead<={16'd0,reserved}+fat_span;
                    fat_start_lba<=partition_reserved+((flags[7] && flags[0])?fat_sectors:32'd0);
                    state<=LAYOUT_SUB;
                end
                LAYOUT_SUB:begin
                    {data_borrow,data_sectors}<={1'b0,total_sectors}-{1'b0,overhead};
                    data_start_lba<=partition_lba+overhead;
                    state<=LAYOUT_LOAD;
                end
                LAYOUT_LOAD:begin cluster_count<=data_sectors;shift_count<=cluster_shift;state<=LAYOUT_SHIFT;end
                LAYOUT_SHIFT:if(shift_count!=0)begin cluster_count<={1'b0,cluster_count[31:1]};shift_count<=shift_count-1'b1;end
                else state<=LAYOUT_MAX;
                LAYOUT_MAX:begin max_cluster<=cluster_count+1;state<=LAYOUT_CHECK;end
                LAYOUT_CHECK:begin
                    layout_bad<=data_borrow || data_sectors==0 || cluster_count==0 ||
                       root_cluster>max_cluster || cluster_count>32'h0fffffee ||
                       (max_cluster>>7)>=fat_sectors;
                    state<=LAYOUT_ACCEPT;
                end
                LAYOUT_ACCEPT:begin
                    if(layout_bad)fail(ERR_BPB);
                    else begin current_cluster<=root_cluster;visited<=1;dir_sector<=0;state<=ROOT;end
                end
                ROOT:begin cluster_offset<=current_cluster-2;shift_count<=cluster_shift;state<=ROOT_SHIFT;end
                ROOT_SHIFT:if(shift_count!=0)begin cluster_offset<={cluster_offset[30:0],1'b0};shift_count<=shift_count-1'b1;end
                else state<=ROOT_ADD;
                ROOT_ADD:begin sector_lba<=data_start_lba+cluster_offset;state<=DIR_REQ;end
                DIR_REQ:if(!sector_busy)begin sector_req<=1;name_match<=0;state<=DIR_WAIT;end
                DIR_WAIT:if(sector_done)begin if(sector_error!=0)fail(ERR_SECTOR);else state<=DIR_NEXT;end
                DIR_NEXT:begin
                    // Without every audio or text file the scan runs to the directory end.
                    if(dir_end || (resource_valid==4'hf && (!SCAN_AUDIO || (bgm_found && snd_found==4'hf)) &&
                                   (!SCAN_TEXT || (font_found && text_found))))state<=FINISH;

                    else if(dir_sector+1'b1<sectors_per_cluster)begin
                        dir_sector<=dir_sector+1'b1;sector_lba<=sector_lba+1'b1;state<=DIR_REQ;
                    end else begin sector_lba<=fat_start_lba+(current_cluster>>7);state<=FAT_REQ;end
                end
                FAT_REQ:if(!sector_busy)begin sector_req<=1;state<=FAT_WAIT;end
                FAT_WAIT:if(sector_done)begin if(sector_error!=0)fail(ERR_SECTOR);else state<=FAT_PARSE;end
                FAT_PARSE:begin
                    fat_end<=next_cluster>=32'h0ffffff8;
                    fat_bad<=next_cluster<2 || next_cluster>max_cluster;
                    fat_loop<=next_cluster==current_cluster;
                    fat_limit<=visited>=MAX_VISITED_CLUSTERS;
                    state<=FAT_CHECK;
                end
                FAT_CHECK:begin
                    if(fat_end)state<=FINISH;
                    else if(fat_bad)fail(ERR_RANGE);
                    else if(fat_loop)fail(ERR_LOOP);
                    else if(fat_limit)fail(ERR_LIMIT);
                    else begin current_cluster<=next_cluster;visited<=visited+1'b1;dir_sector<=0;state<=ROOT;end
                end
                FINISH:begin scan_done<=1;state<=IDLE;end
                default:state<=IDLE;
            endcase
        end
    end
endmodule
