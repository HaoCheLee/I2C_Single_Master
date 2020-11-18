`include "I2C_slave.sv"
module slave_1 (
	input rst_n,
	inout SDA,
	input SCL
	`ifdef DEBUG_OUT
	, output req
	, output read
	, output [2:0] mem_pos
	, output [7:0][7:0] memory
	`endif
);

logic req, read;
wire [7:0] data;

I2C_slave #(.ADDRESS(25)) sl1(rst_n, SDA, SCL, req, read, data);

logic [7:0][7:0] memory;
logic [2:0] mem_pos;
//Memory inside slave device

always_ff @(negedge SCL or negedge rst_n) begin : proc_memory
	if(~rst_n) begin
		memory <= #1 64'hdeadbeefdeadbeef;
	end else begin
		if(req) memory[mem_pos] <= #1 data;
	end
end

always_ff @(negedge SCL or negedge rst_n) begin : proc_mem_pos
	if(~rst_n) begin
		mem_pos <= #1 0;
	end else begin
		if(req) mem_pos <= #1 mem_pos + 1;
	end
end

assign data = read ? memory[mem_pos] : 8'hzz;

endmodule