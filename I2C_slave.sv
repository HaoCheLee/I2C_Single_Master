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
	WAIT_ACK,
	GET_ACK,
	GET_WRITE,
	STOP
} current_state, next_state;

logic SDA_pos;
logic [6:0] Addr;
logic [2:0] Addr_pos;
assign Addr = ADDRESS;
//The slave address
logic SDA_low;
logic [2:0] mem_pos;
logic [7:0] memory;
//Memory inside the slave module

`ifdef NO_ACK
int NO_ACK_counter = 50;
always @(negedge SCL) if(NO_ACK_counter) NO_ACK_counter--;
`endif

always_ff @(posedge SCL or negedge rst_n) begin : proc_SDA_pos
	if(~rst_n)
		SDA_pos <= #1 1;
	else
		SDA_pos <= #1 SDA;
end
//Save SDA at posedge to detect start/stop

//SDA has to change prior a clock to make sure master receive at the right clock
always_ff @(negedge SCL or negedge rst_n) begin : proc_SDA_low
	if(~rst_n)
		SDA_low <= #1 0;
	else
		case (current_state)
			IDLE: begin
				SDA_low <= #1 0;
			end
			CHECK_ADDR: begin
				SDA_low <= #1 0;
			end
			GET_RW: begin
				`ifdef NO_ACK
				if(NO_ACK_counter)
					SDA_low <= #1 0;
				else
					SDA_low <= #1 1;
				`else 
				SDA_low <= #1 1;
				`endif
			end
			SEND_ACK: begin
				if(read) SDA_low <= #1 !memory[7];
				else SDA_low <= #1 0;
			end
			SEND_READ: begin
				SDA_low <= #1 !memory[mem_pos];
			end
			GET_ACK: begin//If STOP, stop sending
				if(SDA_pos != SDA) SDA_low <= #1 0;
				else if(SDA) SDA_low <= #1 0;//Not receiving ACK
				else SDA_low <= #1 !memory[7];
			end
			GET_WRITE: begin
				if(mem_pos == 0) SDA_low <= #1 1;
			end
			default : SDA_low <= #1 0;
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
	if(SDA_pos == 0 && SDA == 1) next_state = IDLE;
	else if(SDA_pos == 1 && SDA == 0) next_state = CHECK_ADDR;
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
				else next_state = WAIT_ACK;
			end
			WAIT_ACK: begin
				next_state = GET_ACK;
			end
			GET_ACK: begin
				if(SDA) next_state = IDLE;//Not receiving ACK
				next_state = SEND_READ;
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
		IDLE: begin
			Addr_pos <= #1 6;
		end
		CHECK_ADDR: begin
			Addr_pos <= #1 Addr_pos - 1;
		end
		default : Addr_pos <= #1 6;
	endcase
end

always_ff @(negedge SCL or negedge rst_n) begin : proc_read
	if(~rst_n) read <= #1 1;
	else if(current_state == GET_RW) read <= #1 SDA;
	else if(current_state ==IDLE) read <= #1 1;
end

always_ff @(negedge SCL or negedge rst_n) begin : proc_memory
	if(~rst_n) begin
		memory <= #1 0;
		mem_pos <= #1 7;
	end else if(SDA_pos != SDA) begin
		memory <= #1 data;
		if(read) mem_pos <= #1 6;
		else mem_pos <= #1 7;
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
			if(current_state == WAIT_ACK) memory <= #1 data;
			else if(current_state == GET_RW) memory <= #1 data;
			if(read) mem_pos <= #1 6;
			else mem_pos <= #1 7;
		end
	end
end

assign req = (current_state == SEND_ACK && mem_pos == 7) || (current_state == SEND_READ && mem_pos == 0);
assign data = read ? 8'hzz : memory;

endmodule