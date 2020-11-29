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
	TRANS,
	START,
	ADDR,
	RW,
	GET_ACK,
	SEND_WRITE,
	GET_READ,
	SEND_ACK,
	STOP
} current_state, next_state, now_state;
//now_state is "real next state"

logic SDA_start, SDA_stop, SDA_signal, SDA_low;
//SDA_start is for start to change at SCL high
//SDA_stop is for stop to change at SCL high
//SDA_signal is for other signals to change at SCL low
//SDA_low is final output of SDA
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
logic SDA_pos, SDA_neg;
//for checking SDA signal interruption
logic wr_en, wr_full, rd_en, rd_empty;
logic [7:0] wr_data, rd_data;
Sync_FIFO sf1(clk, rst_n, wr_en, wr_data, wr_full, rd_en, rd_data, rd_empty);
//FIFO receiving input

assign wr_en = pushin;
assign wr_data = data_in;
assign data_out = memory;

always_ff @(posedge clk or negedge rst_n) begin : proc_SDA_pos
	if(~rst_n) begin
		SDA_pos <= #1 0;
	end else begin
		SDA_pos <= #1 (SDA == SDA_low);
	end
end

always_ff @(negedge clk or negedge rst_n) begin : proc_SDA_neg
	if(~rst_n) begin
		SDA_neg <= #1 0;
	end else begin
		SDA_neg <= #1 (SDA == SDA_low);
	end
end
//SDA_pos and SDA_neg = 1 when SDA is not the same as master's output

always_ff @(negedge clk or negedge rst_n) begin : proc_SDA_start_stop
	if(~rst_n) begin
		SDA_start <= #1 0;
		SDA_stop <= #1 1;
	end else begin
		if(current_state == START) SDA_start <= #1 1;
		else SDA_start <= #1 0;
		if(current_state == STOP) SDA_stop <= #1 0;
		else SDA_stop <= #1 1;
	end
end

always_ff @(negedge clk or negedge rst_n) begin : proc_SDA_signal
	if(~rst_n) begin
		SDA_signal <= #1 0;
	end else begin
		case(now_state)
			IDLE: SDA_signal <= #1 0;
			TRANS: begin
				if(now_state == START) SDA_signal <= #1 0;
				else if(now_state == STOP) SDA_signal <= #1 1;
			end
			ADDR: begin
				if(Addr[Addr_pos]) SDA_signal <= #1 0;
				else SDA_signal <= #1 1;
			end
			RW: begin
				if(write)
					SDA_signal <= #1 1;
				else
					SDA_signal <= #1 0;
			end
			GET_ACK: begin
				SDA_signal <= #1 0;
			end
			SEND_WRITE: begin
				if(memory[mem_pos]) SDA_signal <= #1 0;
				else SDA_signal <= #1 1;
			end
			GET_READ: begin
				SDA_signal <= #1 0;
			end
			SEND_ACK: begin
				SDA_signal <= #1 1;
			end
			STOP: begin
				SDA_signal <= #1 1;
			end
			default: SDA_signal <= #1 SDA_signal;
		endcase
	end
end

assign SDA_low = (SDA_start || SDA_signal) && SDA_stop;
assign SDA = SDA_low ? 1'b0 : 1'bz;
assign SCL = (current_state == TRANS && now_state != IDLE && now_state != START) ? 1'b0 : 1'bz;
//When IDLE stop tickling SCL

always_ff @(posedge clk or negedge rst_n) begin : proc_current_state
	if(~rst_n) begin
		current_state <= #1 TRANS;
	end else begin
		current_state <= #1 next_state;
	end
end

assign next_state = current_state == TRANS ? now_state : TRANS;
//TRANS is between state transitions, TRANS is when SCL is 0

always_ff @(posedge clk or negedge rst_n) begin : proc_now_state
	if(~rst_n) begin
		now_state <= #1 IDLE;
	end else begin
		if(SCL)
			case(current_state)
				IDLE: begin
					if(!rd_empty) now_state <= #1 START;
					else now_state <= IDLE;
				end
				START: begin
					now_state <= #1 ADDR;
				end
				ADDR: begin
					if(SDA_pos || SDA_neg) now_state <= #1 START;
					else begin
						if(Addr_pos > 0) now_state <= #1 ADDR;
						else now_state <= #1 RW;
					end
				end
				RW: begin
					if(SDA_pos || SDA_neg) now_state <= #1 START;
					else now_state <= #1 GET_ACK;
				end
				GET_ACK: begin
					if(SDA) now_state <= #1 START;
					else if(done) now_state <= #1 STOP;
					else if(write) now_state <= #1 SEND_WRITE;
					else now_state <= #1 GET_READ;
				end
				SEND_WRITE: begin
					if(mem_pos == 0) now_state <= #1 GET_ACK;
					else now_state <= #1 SEND_WRITE;
				end
				GET_READ: begin
					if(mem_pos == 0) begin//If done, no need to send ACK, directly send STOP
						if(done) now_state <= #1 STOP;
						else now_state <= #1 SEND_ACK;
					end
					else now_state <= #1 GET_READ;
				end
				SEND_ACK: begin
					now_state <= #1 GET_READ;
				end
				STOP: begin
					if(SDA_pos || SDA_neg) now_state <= #1 STOP;
					else now_state <= #1 IDLE;
				end
				default: now_state <= #1 now_state;
			endcase
	end
end

always_ff @(posedge clk or negedge rst_n) begin : proc_done
	if(~rst_n) begin
		done <= #1 1;
	end else begin
		if(rd_empty) done <= #1 1;
		else if(current_state == START) done <= #1 0;
	end
end
//Cannot use rd_empty directly, because when FIFO goes empty, 
//new data can pushin, but current transaction is done

always_ff @(posedge clk or negedge rst_n) begin : proc_Addr_pos
	if(~rst_n) begin
		Addr_pos <= #1 6;
	end else begin
		if(SCL)
			if(current_state == ADDR) Addr_pos <= #1 Addr_pos - 1;
			else if(current_state == START) Addr_pos <= #1 6;
	end
end

always_ff @(posedge clk or negedge rst_n) begin : proc_Addr_write
	if(~rst_n) begin
		Addr <= #1 0;
		write <= #1 0;
	end else begin
		if(current_state == START && done) begin
			Addr <= #1 rd_data[7:1];
			write <= #1 rd_data[0];
		end
	end
end

always_ff @(posedge clk or negedge rst_n) begin : proc_get_Addr
	if(~rst_n) begin
		get_Addr <= #1 1;
	end else begin
		if(current_state == GET_ACK) get_Addr <= #1 0;
		else if(current_state == STOP) get_Addr <= #1 1;
	end
end

always_ff @(posedge clk or negedge rst_n) begin : proc_memory
	if(~rst_n) begin
		memory <= #1 0;
	end else begin
		if(SCL)
			if(current_state == GET_READ) begin
				memory[mem_pos] <= #1 SDA;
				mem_pos <= #1 mem_pos - 1;
			end
			else if(current_state == SEND_WRITE) begin
				mem_pos <= #1 mem_pos - 1;
			end
			else if(current_state == GET_ACK) begin
				memory <= #1 rd_data;
				mem_pos <= #1 7;
			end
	end
end

always_ff @(posedge clk or negedge rst_n) begin : proc_canin
	if(~rst_n) begin
		canin <= #1 1;
	end else begin
		if(canin && pushin && !wr_full)
			canin <= #1 1;
		else if(rd_empty)
			canin <= #1 1;
		else
			canin <= #1 0;
	end
end
//Cannot accept new request when not send out all data

always_comb begin
	if(SCL)
		if(current_state == RW && get_Addr) rd_en = 1;
		else if (current_state == GET_ACK && SDA == 0 && !done) rd_en = 1;
		else if (current_state == SEND_ACK) rd_en = 1;
		else rd_en = 0;
	else rd_en = 0;

	if(SCL)
		if(current_state == SEND_ACK) pushout = 1;
		else if(current_state == STOP && write == 0) pushout = 1;
		else pushout = 0;
	else pushout = 0;
end

endmodule