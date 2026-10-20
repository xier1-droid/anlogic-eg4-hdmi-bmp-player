module bmp_scale_stream_v017 (
 input clk,rst,file_start,input [31:0] file_size,
 input file_valid,input [7:0] file_byte,input [31:0] file_byte_offset,
 input file_end,input [7:0] upstream_error,
 output data_permit,output pixel_valid,input pixel_ready,output [23:0] pixel_rgb,
 output reg done,output [2:0] error,
 output [7:0] pixel_alpha
);
 wire bytes_valid,bytes_ready,bytes_done,header_valid,raw_valid,raw_ready;
 wire [7:0] bytes_data;wire [31:0] bytes_offset;
 wire [15:0] w,h,px,py;wire [23:0] raw_rgb;wire [7:0] raw_alpha;
 wire decoder_done,scaler_done;
 // Two output slots break the coordinator/FIFO-ready path into the scaler.
 // Occupancy alone drives scaler_ready; no combinational downstream ready.
 wire scaler_valid,scaler_ready;
 wire [23:0] scaler_rgb;
 wire [7:0] scaler_alpha;
 reg [31:0] pixel_slot[0:1];
 reg read_slot,write_slot;
 reg [1:0] pixel_count;
 wire push_pixel=scaler_valid && scaler_ready;
 wire pop_pixel=pixel_valid && pixel_ready;
 assign scaler_ready=pixel_count<2;
 assign pixel_valid=pixel_count!=0;
 assign pixel_rgb=pixel_slot[read_slot][31:8];
 assign pixel_alpha=pixel_slot[read_slot][7:0];
 always @(posedge clk or posedge rst)begin
  if(rst)begin read_slot<=0;write_slot<=0;pixel_count<=0;end
  else if(file_start)begin read_slot<=0;write_slot<=0;pixel_count<=0;end
  else begin
   if(push_pixel)begin pixel_slot[write_slot]<={scaler_rgb,scaler_alpha};write_slot<=~write_slot;end
   if(pop_pixel)read_slot<=~read_slot;
   case({push_pixel,pop_pixel})
    2'b10:pixel_count<=pixel_count+1'b1;
    2'b01:pixel_count<=pixel_count-1'b1;
    default:;
   endcase
  end
 end
 reg decode_seen,scale_seen,reported;
 // Registered ready/valid boundary keeps decoder counters and coordinates
 // out of the scaler's row-selection cone.
 reg raw_pipe_valid;
 reg [23:0] raw_pipe_rgb;
 reg [7:0] raw_pipe_alpha;
 reg [15:0] raw_pipe_x,raw_pipe_y;
 wire scaler_in_ready;
 assign raw_ready=!raw_pipe_valid || scaler_in_ready;
 always @(posedge clk or posedge rst)begin
  if(rst)begin raw_pipe_valid<=0;raw_pipe_rgb<=0;raw_pipe_alpha<=8'hFF;raw_pipe_x<=0;raw_pipe_y<=0;end
  else if(file_start)raw_pipe_valid<=0;
  else if(raw_ready)begin
   raw_pipe_valid<=raw_valid;
   if(raw_valid)begin raw_pipe_rgb<=raw_rgb;raw_pipe_alpha<=raw_alpha;raw_pipe_x<=px;raw_pipe_y<=py;end
  end
 end
 bmp_sector_buffer buffer(
  .clk(clk),.rst(rst || file_start),.in_valid(file_valid),.in_byte(file_byte),
  .in_offset(file_byte_offset),.in_done(file_end),.data_permit(data_permit),
  .out_valid(bytes_valid),.out_ready(bytes_ready),.out_byte(bytes_data),
  .out_offset(bytes_offset),.out_done(bytes_done));
 // FETCH registers data one clock before PRESENT. The decoder can capture
 // the header address on that same FETCH edge without delaying consumption.
 bmp24_decoder_v017 #(.ALLOW_32(1),.RANGE_DIMENSIONS(1),.FLOW_CONTROL(1),
                 .HEADER_OFFSET_LOOKAHEAD(1)) decoder(
  .clk(clk),.rst(rst),.expected_width(16'd0),.expected_height(16'd0),
  .file_start(file_start),.file_size(file_size),.file_valid(bytes_valid),
  .file_byte(bytes_data),.file_byte_offset(bytes_offset),.file_end(bytes_done),
  .upstream_error(upstream_error),.header_accepted(header_valid),.pixel_valid(raw_valid),
  .pixel_ready(raw_ready),.pixel_rgb(raw_rgb),.pixel_x(px),.pixel_y(py),
  .frame_commit(),.bmp_done(decoder_done),.bmp_error(error),.file_ready(bytes_ready),
  .image_width(w),.image_height(h),.pixel_alpha(raw_alpha));
 image_scale_nearest scaler(.clk(clk),.rst(rst || file_start),.start(header_valid),
  .image_width(w),.image_height(h),.in_valid(raw_pipe_valid),.in_ready(scaler_in_ready),
  .in_rgb(raw_pipe_rgb),.in_x(raw_pipe_x),.in_y(raw_pipe_y),.out_valid(scaler_valid),.out_ready(scaler_ready),
  .out_rgb(scaler_rgb),.done(scaler_done),.in_alpha(raw_pipe_alpha),.out_alpha(scaler_alpha));
 always @(posedge clk or posedge rst)begin
  if(rst)begin done<=0;decode_seen<=0;scale_seen<=0;reported<=0;end
  else begin
   done<=0;
   if(file_start)begin decode_seen<=0;scale_seen<=0;reported<=0;end
   else begin
    if(decoder_done)decode_seen<=1;
    if(scaler_done)scale_seen<=1;
    if(!reported && error==0 && upstream_error==0 &&
       (decode_seen || decoder_done) && scale_seen && pixel_count==0)begin done<=1;reported<=1;end
   end
  end
 end
endmodule
