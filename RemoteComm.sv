module RemoteComm(
	input clk, rst_n,	// Clock and active low reset
	input snd_cmd,		// send the cmd when asserted
	input [15:0] cmd,	// command to be sent
	input RX,		// Receive line
	output logic TX,	// Transmit line
	output logic cmd_snt,	// cmd_snt -> signals when the command has finished sending
	output logic resp_rdy,	// Indicates valid response has been received
	output logic [7:0] resp	// 8-bit response received
);


    // States and state flop
    typedef enum reg [1:0] {IDLE, MSB, LSB} state_t;
    state_t state, nxt_state;

    // State register
    always_ff @(posedge clk, negedge rst_n) begin
        if (!rst_n)
            state <= IDLE;
        else
            state <= nxt_state;
    end

    // Internal control signals
    logic trmt;			// to tell TX to start transmitting 
    logic sel, tx_done;		// Select between MSB and LSB
    logic [7:0] tx_data, lsb;	// Data to transmit and stored LSB

    // Flop for LSB
    always_ff @(posedge clk)
        if (snd_cmd) lsb <= cmd[7:0];
            
    // if sel high, transmit high byte
    assign tx_data = (sel) ? cmd[15:8] : lsb;

    logic clr_rx_rdy;	// Clears the recieved data ready signal

    // UART instantiation
    UART iUART_RC(.clk(clk),
        .rst_n(rst_n),
        .RX(RX),.TX(TX),
        .rx_rdy(resp_rdy),
        .clr_rx_rdy(clr_rx_rdy),
        .rx_data(resp),
        .trmt(trmt),
        .tx_data(tx_data),
        .tx_done(tx_done)
    );

    // State transition and output logic
    logic set_cmd_snt;

    always_comb begin
        // Default statements
        nxt_state = state;
        trmt = 1'b0;
        sel = 1'b1; // default to MSB
        set_cmd_snt = 1'b0;


        case(state)
        LSB:
            if (tx_done) begin // trmt will be 0, MSB & LSB have been transmitted
                // stop transmitting
                set_cmd_snt = 1'b1;	// Signal full command sent
                nxt_state = IDLE;
            end
            else
                sel = 1'b1; // transmit most recent 8 bits (LSB)
        MSB:
            if (tx_done) begin
                trmt = 1'b1; // TX to start transmitting
                sel = 1'b0; // transmit lowest stored/oldest 8 bits
                nxt_state = LSB;
            end
        default: // IDLE state
            if (snd_cmd) begin
                trmt = 1'b1;		// Start MSB transmission
                nxt_state = MSB;
            end
        endcase


    end

    // SR flop for CMD_SNT signal; set when transmission complete
    always_ff @(posedge clk, negedge rst_n) begin
        if (!rst_n)
            cmd_snt <= 1'b0;
        else if (snd_cmd)
            cmd_snt <= 1'b0;
        else if (set_cmd_snt)
            cmd_snt <= 1'b1;
    end

endmodule
