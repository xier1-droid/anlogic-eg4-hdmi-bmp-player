module video_delay
#(
	parameter DATA_WIDTH = 24,                      // Video data one clock data width
	parameter SYNC_EXTRA = 0                        // Extra sync delay for a pixel pipeline after vout_data
)
(
	input                       video_clk,          // Video pixel clock
	input                       rst,
	output                      read_en,            // Read data enable
	input[DATA_WIDTH - 1:0]     read_data,          // Read data
	input                      hs,                 // horizontal synchronization
	input                      vs,                 // vertical synchronization
	input                      de,                 // video valid
	input [9:0]                video_x,

	output                      hs_r,                 // horizontal synchronization
	output                      vs_r,                 // vertical synchronization
	output                      de_r,                 // video valid
	output[DATA_WIDTH - 1:0]    vout_data,          // video data
	output [9:0]               video_x_r

);
localparam [4:0] READ_LAG = 20 + SYNC_EXTRA;   // ring slots between write and read
reg [20+SYNC_EXTRA:0] de_d;
reg[DATA_WIDTH - 1:0]  vout_data_r;
// x/hs/vs share one 32-entry BRAM ring. The read slot trails the write slot by
// 20 entries, keeping the original 21-clock delay; outputs stay zero until 20
// clocks after reset, as the reset shift chain did. SYNC_EXTRA lengthens the
// x/hs/vs/de delay only, so a SYNC_EXTRA-clock pipeline on vout_data lines up.
reg [11:0] delay_ram [0:31]; /* fehdl force_ram=1, ram_style="bram" */
reg [11:0] delay_q;
reg [4:0] write_slot;
reg [4:0] fill_count;
reg primed;

assign read_en = de_d[18];
assign de_r = de_d[20+SYNC_EXTRA];
assign vout_data = vout_data_r;
assign {video_x_r,hs_r,vs_r} = primed ? delay_q : 12'd0;
always @(posedge video_clk) begin
	delay_ram[write_slot] <= {video_x,hs,vs};
	delay_q <= delay_ram[write_slot - READ_LAG];
end
always @(posedge video_clk or posedge rst) begin
	if(rst) begin
		write_slot <= 5'd0;
		fill_count <= 5'd0;
		primed <= 1'b0;
	end else begin
		write_slot <= write_slot + 1'b1;
		if(fill_count != READ_LAG) fill_count <= fill_count + 1'b1;
		primed <= fill_count == READ_LAG;
	end
end
always@(posedge video_clk or posedge rst)
begin
	if(rst == 1'b1)
		vout_data_r <= {DATA_WIDTH{1'b0}};
	else if(de_d[19])
		vout_data_r <= read_data;
	else
		vout_data_r <= {DATA_WIDTH{1'b0}};
end
always @(posedge video_clk or posedge rst)begin
	if(rst)
		de_d <= 0;
	else
		de_d <= {de_d[19+SYNC_EXTRA:0],de};
end
endmodule
