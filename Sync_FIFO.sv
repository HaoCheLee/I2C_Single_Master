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

logic [DSIZE-1:0] memory [(2**ASIZE)-1:0];
logic [ASIZE-1:0] wr_ptr, rd_ptr;
logic is_empty;//To indicate full or empty when wr_ptr = rd_ptr

assign wr_full = (wr_ptr == rd_ptr) && !is_empty;
assign rd_data = memory[rd_ptr];
assign rd_empty = (wr_ptr == rd_ptr) && is_empty;

always_ff @(posedge clk or negedge rst_n) begin
	if(~rst_n) begin
		for (int i = 0; i < (2**ASIZE)-1; i++) begin
			memory[i] <= 0;
		end
		wr_ptr <= 0;
		rd_ptr <= 0;
		is_empty <= 1;
	end else begin
		if(wr_en && !wr_full) begin
			memory[wr_ptr] <= wr_data;
			wr_ptr <= wr_ptr + 1;
			if(rd_en && !rd_empty) begin
				rd_ptr <= rd_ptr + 1;
				is_empty <= is_empty;
			end
			else
				is_empty <= 0;
		end
		else
			if(rd_en && !rd_empty) begin
				rd_ptr <= rd_ptr + 1;
				is_empty <= 1;
			end
			else
				is_empty <= is_empty;
	end
end

endmodule