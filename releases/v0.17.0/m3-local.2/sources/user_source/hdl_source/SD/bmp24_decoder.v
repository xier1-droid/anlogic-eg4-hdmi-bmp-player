module bmp24_decoder #(
    parameter integer EXPECTED_WIDTH = 640,
    parameter integer EXPECTED_HEIGHT = 480,
    parameter integer RUNTIME_DIMENSIONS = 0,
    parameter integer ALLOW_32 = 1,
    parameter integer RANGE_DIMENSIONS = 0,
    parameter integer FLOW_CONTROL = 0,
    // Enable only when offset is stable at least one clock before file_valid.
    // bmp_sector_buffer's FETCH/PRESENT interface provides that lookahead.
    parameter integer HEADER_OFFSET_LOOKAHEAD = 0
) (
    input wire clk, input wire rst,
    input wire [15:0] expected_width, expected_height,
    input wire file_start, input wire [31:0] file_size,
    input wire file_valid, input wire [7:0] file_byte,
    input wire [31:0] file_byte_offset, input wire file_end,
    input wire [7:0] upstream_error,
    output reg header_accepted, output reg pixel_valid,
    output reg [23:0] pixel_rgb, output reg [15:0] pixel_x, pixel_y,
    output reg frame_commit, output reg bmp_done, output reg [2:0] bmp_error,
    input wire pixel_ready, output wire file_ready,
    output wire [15:0] image_width, image_height,
    // 32bpp: BMP alpha byte (scene T). 24bpp: constant FF.
    output reg [7:0] pixel_alpha
);
 wire [15:0] tw=RUNTIME_DIMENSIONS?expected_width:EXPECTED_WIDTH;
 wire [15:0] th=RUNTIME_DIMENSIONS?expected_height:EXPECTED_HEIGHT;
 wire [31:0] declared_size,pixel_offset,width,height,row_stride,expected_pixels;
 wire [33:0] pixel_end;
 wire header_ok,header_complete,is_32;
 reg active,checked,end_pending;
 reg end_count_ok,end_row_ok;
 localparam ROW_BITS=RANGE_DIMENSIONS?11:32;
 localparam BYTE_BITS=RANGE_DIMENSIONS?13:32;
 localparam COUNT_BITS=RANGE_DIMENSIONS?22:32;
 reg [31:0] size_reg;
 reg [BYTE_BITS-1:0] row_byte;
 reg [ROW_BITS-1:0] row,col;
 reg [COUNT_BITS-1:0] pixel_count;
 reg [31:0] row_payload,row_last;
 reg header_good;
 reg pixels_started;
 reg [1:0] phase;
 reg [7:0] blue,green,red;
 wire take_byte = file_valid && file_ready;
 // The header uses offsets 0..53 only. Capture its small address during the
 // upstream FETCH cycle; 63 is an inert address for all non-header bytes.
 // Generic callers may supply consecutive bytes and retain the direct path.
 reg [5:0] header_offset;
 always @(posedge clk)
  header_offset <= (file_byte_offset[31:6]==0) ? file_byte_offset[5:0] : 6'd63;
 wire [31:0] header_byte_offset = HEADER_OFFSET_LOOKAHEAD ?
    {26'd0,header_offset} : file_byte_offset;
 // The range-mode sector buffer delivers every byte in order. Once the
 // payload starts, row completion bounds it without a wide offset comparator
 // on every pixel/row write-enable path. Fixed legacy mode retains its check.
 wire in_pixel_region=RANGE_DIMENSIONS ?
    ((pixels_started || file_byte_offset==pixel_offset) && row<height[ROW_BITS-1:0]) :
    (file_byte_offset>=pixel_offset && {2'b0,file_byte_offset}<pixel_end);
 assign file_ready = !FLOW_CONTROL || !pixel_valid || pixel_ready;
 assign image_width = width[15:0];
 assign image_height = height[15:0];
 wire [15:0] actual_width = RANGE_DIMENSIONS ? width[15:0] : tw;
 always @(posedge clk) begin
  row_payload <= is_32 ? {16'd0,actual_width}*4 : {16'd0,actual_width}*3;
  row_last <= row_stride-1'b1;
 end
 bmp_header_check #(.ALLOW_32(ALLOW_32),.RANGE_DIMENSIONS(RANGE_DIMENSIONS)) u_header (
  .clk(clk),.rst(rst || file_start),.file_valid(active && take_byte),
  .file_byte(file_byte),.file_byte_offset(header_byte_offset),.bmp_width(tw),.bmp_height(th),
  .file_len(declared_size),.pixel_offset(pixel_offset),.width(width),.height(height),
  .required_end(pixel_end),.header_match(header_ok),.skip_format(),
  .expected_pixels(expected_pixels),.header_complete(header_complete),.is_32(is_32),.row_stride(row_stride)
 );
 wire accepted_header=header_ok && {2'b0,size_reg}>=pixel_end;
 always @(posedge clk or posedge rst) begin
  if(rst) begin
   active<=0;checked<=0;end_pending<=0;end_count_ok<=0;end_row_ok<=0;size_reg<=0;header_good<=0;pixels_started<=0;
   header_accepted<=0;pixel_valid<=0;frame_commit<=0;bmp_done<=0;bmp_error<=0;
   pixel_rgb<=0;pixel_x<=0;pixel_y<=0;row_byte<=0;row<=0;col<=0;pixel_count<=0;phase<=0;
   blue<=0;green<=0;red<=0;pixel_alpha<=8'hFF;
  end else begin
   header_accepted<=0;frame_commit<=0;bmp_done<=0;
   if(!FLOW_CONTROL || pixel_ready) pixel_valid<=0;
   if(file_start) begin
    active<=1;checked<=0;end_pending<=0;end_count_ok<=0;end_row_ok<=0;size_reg<=file_size;bmp_error<=0;header_good<=0;pixels_started<=0;
    row_byte<=0;row<=0;col<=0;pixel_count<=0;phase<=0;pixel_valid<=0;
   end else if(active) begin
    if(header_complete && !checked) begin
     checked<=1;
     if(accepted_header)begin header_accepted<=1;header_good<=1;end
     else begin bmp_error<=1;active<=0;end
    end
    if(take_byte && (FLOW_CONTROL?header_good:accepted_header) && in_pixel_region) begin
     pixels_started<=1;
     if(row_byte < row_payload) begin
      if(phase==0)blue<=file_byte;
      if(phase==1)green<=file_byte;
      if(phase==2)red<=file_byte;
      if((!is_32 && phase==2)||(is_32 && phase==3))begin
       pixel_rgb<={is_32?red:file_byte,green,blue};pixel_alpha<=is_32?file_byte:8'hFF;pixel_valid<=1;
       pixel_x<=col;pixel_y<=height-1-row;pixel_count<=pixel_count+1;col<=col+1;
      end
      if((!is_32 && phase==2)||(is_32 && phase==3))phase<=0;else phase<=phase+1;
     end
     if(row_byte==row_last)begin row_byte<=0;row<=row+1;col<=0;phase<=0;end
     else row_byte<=row_byte+1;
    end
    if(file_end)begin
     end_pending<=1;
     end_count_ok<=checked && pixel_count==expected_pixels;
     end_row_ok<=row==height && row_byte==0;
    end
    if(end_pending && (!FLOW_CONTROL || !pixel_valid || pixel_ready))begin
     active<=0;end_pending<=0;
     if(end_count_ok && end_row_ok)begin
      frame_commit<=1;bmp_done<=1;bmp_error<=0;
     end else bmp_error<=3;
    end
    if(upstream_error!=0)begin active<=0;bmp_error<=2;pixel_valid<=0;end
   end
  end
 end
endmodule
