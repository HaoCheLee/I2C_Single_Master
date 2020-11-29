module I2C_slave #(parameter ADDRESS=0) (
	input rst_n,
	inout SDA,
	input SCL,
	output logic req,
	output logic read,
	inout [7:0] data
);

enum [3:0] {
	IDLE,
	CHECK_ADDR,
	GET_RW,
	SEND_ACK,
	SEND_READ,
	GET_ACK,
	GET_WRITE
} current_state, next_state;

logic [6:0] Addr;
logic [2:0] Addr_pos;
assign Addr = ADDRESS;
//The slave address
logic SDA_low;
logic [2:0] mem_pos;
logic [7:0] memory;
//Memory inside the slave module
logic Start, Stop;
//Detect Start/Stop signal
logic no_req;

`ifdef NO_ACK
int NO_ACK_counter = 50;
always @(negedge SCL) if(NO_ACK_counter) NO_ACK_counter--;
`endif

always_ff @(posedge SDA or negedge SCL) begin : proc_Stop
	if(SCL) begin
		Stop <= #1 1;
	end else begin
		Stop <= #1 0;
	end
end

always_ff @(negedge SDA or negedge SCL) begin : proc_Start
	if(SCL) begin
		Start <= #1 1;
	end else begin
		Start <= #1 0;
	end
end

//SDA has to change prior a clock to make sure master receive at the right clock
always_comb begin : proc_SDA_low
	case (current_state)
		SEND_ACK: begin
			`ifdef NO_ACK
			if(NO_ACK_counter) SDA_low = 0;
			else
			`endif
			SDA_low = 1;
		end
		SEND_READ: begin
			SDA_low = !memory[mem_pos];
		end
		default : SDA_low = 0;
	endcase
end

assign SDA = SDA_low ? 1'b0 : 1'bz;

always_ff @(negedge SCL or negedge rst_n) begin : proc_current_state
	if(~rst_n) begin
		current_state <= #1 IDLE;
	end else begin
		current_state <= #1 next_state;
	end
end

always_comb begin : proc_next_state
	if(Start) next_state = CHECK_ADDR;
	else if(Stop) next_state = IDLE;
	//Stop immediately after Start is not allowed, thus the priority of Start is higher
	else case (current_state)
			CHECK_ADDR: begin
				if(Addr[Addr_pos] == SDA) begin
					if(Addr_pos > 0) next_state = CHECK_ADDR;
					else next_state = GET_RW;
				end
				else next_state = IDLE;
			end
			GET_RW: begin
				next_state = SEND_ACK;
			end
			SEND_ACK: begin
				if(read) next_state = SEND_READ;
				else next_state = GET_WRITE;
			end
			SEND_READ: begin
				if(mem_pos > 0) next_state = SEND_READ;
				else next_state = GET_ACK;
			end
			GET_ACK: begin
				if(SDA) next_state = IDLE;//Not receiving ACK
				else next_state = SEND_READ;
			end
			GET_WRITE: begin
				if(mem_pos > 0) next_state = GET_WRITE;
				else next_state = SEND_ACK;
			end
			default : next_state = IDLE;
		endcase
end

always_ff @(negedge SCL) begin : proc_Addr_pos
	case (current_state)
		CHECK_ADDR: begin
			Addr_pos <= #1 Addr_pos - 1;
		end
		default : Addr_pos <= #1 6;
	endcase
end

always_ff @(negedge SCL or negedge rst_n) begin : proc_read
	if(~rst_n) read <= #1 1;
	else if(current_state == GET_RW) read <= #1 SDA;
end

always_ff @(negedge SCL or negedge rst_n) begin : proc_no_req
	if(~rst_n) no_req <= #1 1;
	else if(current_state == GET_RW) no_req <= #1 1;
	else if(current_state == GET_WRITE) no_req <= #1 0;
	else if(current_state == SEND_READ) no_req <= #1 0;
end

always_ff @(negedge SCL or negedge rst_n) begin : proc_memory
	if(~rst_n) begin
		memory <= #1 0;
		mem_pos <= #1 7;
	end
	else begin
		if(current_state == SEND_READ) begin
			mem_pos <= #1 mem_pos - 1;
		end
		else if(current_state == GET_WRITE) begin
			mem_pos <= #1 mem_pos - 1;
			memory[mem_pos] <= #1 SDA;
		end
		else begin
			memory <= #1 data;
			mem_pos <= #1 7;
		end
	end
end

assign req = (current_state == SEND_ACK && !no_req) || (current_state == SEND_READ && mem_pos == 0);
assign data = read ? 8'hzz : memory;

endmodule