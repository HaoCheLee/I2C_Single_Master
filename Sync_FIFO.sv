module Sync_FIFO #(parameter DSIZE = 8, parameter ASIZE = 4)
(
	input clk,
	input rst_n,
	input wr_en,
	input [DSIZE-1:0] wr_data,
	output wr_full,
	input rd_en,
	output [DSIZE-1:0] rd_data,
	output rd_empty
);

logic [(2**ASIZE)-1:0][DSIZE-1:0] memory;
logic [ASIZE-1:0] wr_ptr, rd_ptr;
logic is_empty;//To indicate full or empty when wr_ptr = rd_ptr

assign wr_full = (wr_ptr == rd_ptr) && !is_empty;
assign rd_data = memory[rd_ptr];
assign rd_empty = (wr_ptr == rd_ptr) && is_empty;

always_ff @(posedge clk or negedge rst_n) begin
	if(~rst_n) begin
		memory <= #1 0;
		wr_ptr <= #1 0;
		rd_ptr <= #1 0;
	end else begin
		if(wr_en && !wr_full) begin
			memory[wr_ptr] <= #1 wr_data;
			wr_ptr <= #1 wr_ptr + 1;
		end
		if(rd_en && !rd_empty) begin
			rd_ptr <= #1 rd_ptr + 1;
		end
	end
end

always_ff @(posedge clk or negedge rst_n) begin : proc_is_empty
	if(~rst_n) begin
		is_empty <= #1 1;
	end else begin
		if(wr_en && !wr_full)
			if(rd_en && !rd_empty)
				is_empty <= #1 is_empty;
			else
				is_empty <= #1 0;
		else
			if(rd_en && !rd_empty)
				is_empty <= #1 1;
			else
				is_empty <= #1 is_empty;
	end
end

endmodule