`timescale 1ns/1ps
// M5: FONT.BIN and TEXT.BIN bytes, streamed by the scan in the SD domain, into
// one BRAM32k each, read in the pixel domain (one clock of read latency).
// FONT: 128 glyphs x 16 rows; row r of glyph g is the word at {g,r},
// {byte 2r, byte 2r+1} with the MSB the leftmost pixel. TEXT: 4096 bytes.
// The readers use the contents only while the loaded flags say so; there is
// no reset on the arrays.
module bin_to_bram_loader(
 input wr_clk,
 input bin_wr,bin_sel,              // bin_sel 0: FONT.BIN, 1: TEXT.BIN
 input [11:0] bin_addr,
 input [7:0] bin_data,
 input rd_clk,
 input [10:0] font_addr,
 output reg [15:0] font_data,
 input [11:0] text_addr,
 output reg [7:0] text_data
);
 (* ram_style = "bram_32k" *) reg [15:0] font_mem[0:2047];
 (* ram_style = "bram_32k" *) reg [7:0] text_mem[0:4095];
 reg [7:0] font_left;
 always @(posedge wr_clk) begin
  if(bin_wr && !bin_sel && !bin_addr[0]) font_left<=bin_data;
  if(bin_wr && !bin_sel && bin_addr[0]) font_mem[bin_addr[11:1]]<={font_left,bin_data};
  if(bin_wr && bin_sel) text_mem[bin_addr]<=bin_data;
 end
 always @(posedge rd_clk) begin
  font_data<=font_mem[font_addr];
  text_data<=text_mem[text_addr];
 end
endmodule
