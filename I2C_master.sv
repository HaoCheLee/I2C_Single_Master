`include "Sync_FIFO.sv"
module I2C_master (
	input clk,
	input rst_n,
	inout SDA,
	inout SCL,
	input pushin,
	input [7:0] data_in,
	output logic canin,
	output logic pushout,
	output [7:0] data_out
);

enum [3:0] {
	IDLE,
	START,
	ADDR,
	RW,
	GET_ACK,
	SEND_WRITE,
	GET_READ,
	SEND_ACK,
	STOP
} current_state, next_state;
//now_state is "real next state"

logic SDA_low;
//SDA_low is output of SDA
logic [2:0] Addr_pos;
logic [6:0] Addr;
//The slave address
logic write;
//control bit write = 1 means write
logic get_Addr;
//When no ACK received, resend request, no need to update Addr
logic [2:0] mem_pos;
logic [7:0] memory;
//memory inside master module
logic done;
//indicate data in FIFO are all transfered
logic wr_en, wr_full, rd_en, rd_empty;
logic [7:0] wr_data, rd_data;
Sync_FIFO sf1(	.clk(clk), .rst_n(rst_n), .wr_en(wr_en),
				.wr_data(wr_data), .wr_full(wr_full), .rd_en(rd_en),
				.rd_data(rd_data), .rd_empty(rd_empty));
//FIFO receiving input

assign wr_en = pushin;
assign wr_data = data_in;
assign data_out = memory;

always_comb begin : proc_SDA_low
	case(current_state)
		IDLE: SDA_low = 0;
		START: SDA_low = 1;
		ADDR: begin
			if(Addr[Addr_pos]) SDA_low = 0;
			else SDA_low = 1;
		end
		RW: begin
			if(write)
				SDA_low = 1;
			else
				SDA_low = 0;
		end
		GET_ACK: begin
			SDA_low = 0;
		end
		SEND_WRITE: begin
			if(memory[mem_pos]) SDA_low = 0;
			else SDA_low = 1;
		end
		GET_READ: begin
			SDA_low = 0;
		end
		SEND_ACK: begin
			SDA_low = 1;
		end
		STOP: begin
			SDA_low = 1;
		end
		default: SDA_low = 0;
	endcase
end

assign SDA = SDA_low ? 1'b0 : 1'bz;
assign SCL = (clk && current_state != IDLE && current_state != START) ? 1'b0 : 1'bz;
//When IDLE stop tickling SCL

always_ff @(posedge clk or negedge rst_n) begin : proc_current_state
	if(~rst_n) begin
		current_state <= IDLE;
	end else begin
		if(SCL) current_state <= next_state;
	end
end

always_comb begin : proc_next_state
	case(current_state)
		IDLE: begin
			if(!rd_empty) next_state = START;
			else next_state = IDLE;
		end
		START: begin
			next_state = ADDR;
		end
		ADDR: begin
			if(Addr_pos > 0) next_state = ADDR;
			else next_state = RW;
		end
		RW: begin
			next_state = GET_ACK;
		end
		GET_ACK: begin
			if(SDA) next_state = START;
			else if(done) next_state = STOP;
			else if(write) next_state = SEND_WRITE;
			else next_state = GET_READ;
		end
		SEND_WRITE: begin
			if(mem_pos == 0) next_state = GET_ACK;
			else next_state = SEND_WRITE;
		end
		GET_READ: begin
			if(mem_pos == 0) begin//If done, no need to send ACK, directly send STOP
				if(done) next_state = STOP;
				else next_state = SEND_ACK;
			end
			else next_state = GET_READ;
		end
		SEND_ACK: begin
			next_state = GET_READ;
		end
		STOP: begin
			next_state = IDLE;
		end
		default: next_state = current_state;
	endcase
end

always_ff @(posedge clk or negedge rst_n) begin : proc_done
	if(~rst_n) begin
		done <= 1;
	end else begin
		if(rd_empty) done <= 1;
		else if(current_state == START) done <= 0;
	end
end
//Cannot use rd_empty directly, because when FIFO goes empty, 
//new data can pushin, but current transaction is done

always_ff @(negedge SCL or negedge rst_n) begin : proc_Addr_pos
	if(~rst_n) begin
		Addr_pos <= 7;
	end else begin
		if(current_state == ADDR) Addr_pos <= Addr_pos - 1;
		else if(current_state == START) Addr_pos <= 6;
	end
end

always_ff @(posedge clk or negedge rst_n) begin : proc_Addr_write
	if(~rst_n) begin
		Addr <= 0;
		write <= 0;
	end else begin
		if(current_state == START && done) begin
			Addr <= rd_data[7:1];
			write <= rd_data[0];
		end
	end
end

always_ff @(posedge clk or negedge rst_n) begin : proc_get_Addr
	if(~rst_n) begin
		get_Addr <= 1;
	end else begin
		if(current_state == GET_ACK) get_Addr <= 0;
		else if(current_state == STOP) get_Addr <= 1;
	end
end

always_ff @(negedge SCL or negedge rst_n) begin : proc_memory
	if(~rst_n) begin
		memory <= 0;
	end else begin
		if(current_state == GET_READ) begin
			memory[mem_pos] <= SDA;
			mem_pos <= mem_pos - 1;
		end
		else if(current_state == SEND_WRITE) begin
			mem_pos <= mem_pos - 1;
		end
		else if(current_state == GET_ACK) begin
			memory <= rd_data;
			mem_pos <= 7;
		end
	end
end

always_ff @(posedge clk or negedge rst_n) begin : proc_canin
	if(~rst_n) begin
		canin <= 1;
	end else begin
		if(canin && pushin && !wr_full)
			canin <= 1;
		else if(rd_empty)
			canin <= 1;
		else
			canin <= 0;
	end
end
//Cannot accept new request when not send out all data

always_comb begin
	if(current_state == RW && get_Addr) rd_en = 1;
	else if (current_state == GET_ACK && SDA == 0 && !done) rd_en = 1;
	else if (current_state == SEND_ACK) rd_en = 1;
	else rd_en = 0;

	if(current_state == SEND_ACK) pushout = 1;
	else if(current_state == STOP && write == 0) pushout = 1;
	else pushout = 0;
end

endmodule