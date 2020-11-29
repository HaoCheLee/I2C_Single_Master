`define DEBUG_OUT

//`define NO_ACK
//`define SDA_INTERRUPT
//`define SCL_STRETCH

module I2C_tb ();

logic CLK, RST_n;
wire SCL, SDA;
//I2C Signals

logic [7:0] data_in, data_out;
logic pushin, canin, pushout;
//Master Signals

logic req, read;
logic [2:0] slave_mem_pos;
logic [7:0][7:0] slave_mem;
//Slave Debug Signals

logic [7:0] write_data[$];
int read_count;
logic [7:0] write_check;
always @(posedge SCL) write_check = write_data[0];
//Test Data

logic SDA_low;
assign SDA = SDA_low ? 1'b0 : 1'bz;
//for SDA Interruption

logic SCL_low;
assign SCL = SCL_low ? 1'b0 : 1'bz;
//for clock stretching

pullup(SDA);
pullup(SCL);

I2C_master ms1(CLK, RST_n, SDA, SCL, pushin, data_in, canin, pushout, data_out);
//Master module/device
slave_1 sl1(RST_n, SDA, SCL, req, read, slave_mem_pos, slave_mem);
//Slave Device

always #5 CLK = ~CLK;

task make_test;//Test Case Generate
	input [6:0] Addr;
	input write;
	input [3:0] num_of_data;
	@(posedge CLK)
	begin
		while(!canin) @(posedge CLK);
		pushin = 1;
		data_in = {Addr, write};
		if(write) $display("Sending write command into %d", Addr);
		else begin
			$display("Sending read command into %d", Addr);
			$display("Number of read is %d", num_of_data);
		end
		@(posedge CLK);
		for(int i = 0; i < num_of_data; i++) begin
			data_in = $random();
			if(write) begin
				write_data.push_back(data_in);
				$display("write_data %d is %h", i, data_in);
			end
			else read_count += 1;
			@(posedge CLK);
		end
		pushin = 0;
	end
endtask : make_test

function [2:0] minus_1;
	input [2:0] in;
	case (in)
		0: minus_1 = 7;
		default : minus_1 = in-1;
	endcase
endfunction : minus_1

property write_in;
	@(posedge SCL) ##[1:$] write_check == slave_mem[minus_1(slave_mem_pos)];
endproperty
always @(posedge SCL) assert property (pushin |-> write_in);

property read_out;
	data_out == slave_mem[minus_1(slave_mem_pos)];
endproperty
always @(posedge SCL) assert property (pushout |-> read_out);

task write_checker;
	@(posedge SCL)
	if(write_data[0] == slave_mem[minus_1(slave_mem_pos)]) begin
		$display("CORRECT WRITE");
		`ifdef NO_ACK
		write_data.pop_front();
		`endif
	end
	else begin
		$display("WRITE ERROR @ ",$time());
		$display("write_data is ",write_data[0]);
		$display("slave_mem is ",slave_mem[minus_1(slave_mem_pos)]);
	end
	`ifndef NO_ACK
	write_data.pop_front();
	`endif
endtask : write_checker

task read_checker;
	if(data_out == slave_mem[minus_1(slave_mem_pos)]) begin
		$display("CORRECT READ");
	end
	else begin
		$display("READ ERROR @ ",$time());
		$display("data_out is ",data_out);
		$display("slave_mem is ",slave_mem[minus_1(slave_mem_pos)]);
	end
	read_count -= 1;
endtask : read_checker

always @(posedge SCL) begin//Verify Block
	if(pushout) read_checker();
	if(req && !read) write_checker();
end

initial begin
	CLK = 0;
	RST_n = 0;
	SCL_low = 0;
	SDA_low = 0;
	read_count = 0;
	@(posedge CLK);
	$display("-----TEST START-----",);
	RST_n = 1;
	make_test(7'd25, 1'b1, 4'd5);
	make_test(7'd25, 1'b1, 4'd3);
	make_test(7'd25, 1'b0, 4'd3);
	make_test(7'd25, 1'b1, 4'd5);
	make_test(7'd25, 1'b0, 4'd3);
	while(write_data.size()) @(posedge CLK);//Check all write test cases
	while(read_count) @(posedge CLK);//Check all read test cases
	$display("-----TEST  DONE-----",);
	$finish;
end

`ifdef SDA_INTERRUPT
initial begin//SDA interrupt
	repeat(50) @(negedge SCL);
	#1 SDA_low = 1;
	$display("SDA interrupted @ ",$time());
	repeat(50) @(negedge SCL);
	#1 SDA_low = 0;
	$display("SDA not interrupted @ ",$time());
	repeat(10) @(negedge SCL);
end
`endif

`ifdef SCL_STRETCH
initial begin
	repeat(200) @(posedge CLK);
	#1 SCL_low = 1;
	$display("SCL stretch @ ",$time());
	repeat(200) @(posedge CLK);
	#2 SCL_low = 0;//#2 to prevent pulse
	$display("SCL not stretch @ ",$time());
	repeat(200) @(posedge CLK);
end
`endif

initial begin
	$dumpfile("I2C.vcd");
	$dumpvars();
end

endmodule