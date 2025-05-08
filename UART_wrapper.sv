module UART_wrapper(
    input clk, rst_n,
    input RX,
    input clr_cmd_rdy,          // exernal signal to clear command ready flag
    input trmt,                 // transmit response
    input [7:0] resp,           // response byte to transmit
    output logic tx_done,
    output logic TX,
    output logic [15:0] cmd,    // full 16-bit command from two received bytes
    output logic cmd_rdy        // indicates reception of full command
);
    logic rx_rdy;
    logic [7:0] rx_data;
    logic clr_rx_rdy;
    logic [7:0] high_byte;      // to store first byte
    logic get_high;             // to capture high byte
    logic clr_cmd_rdy_i;        // internal clear command ready signal
    logic cmd_done;             // both bytes have been received
    
    typedef enum logic {IDLE, ACTIVE} state_t;
    state_t state, nxt_state;
    
    // UART instantiation
    UART iUART_wrap(
        .clk(clk),
        .rst_n(rst_n),
        .RX(RX),
        .TX(TX),
        .rx_rdy(rx_rdy),
        .clr_rx_rdy(clr_rx_rdy),
        .rx_data(rx_data),
        .trmt(trmt),
        .tx_data(resp),
        .tx_done(tx_done)
    );

    always_ff @(posedge clk, negedge rst_n) begin
        if (!rst_n) state <= IDLE;
        else state <= nxt_state;
    end

    // SM logic - receives two bytes sequentially
    always_comb begin
        get_high = 1'b0;
        clr_rx_rdy = 1'b0;
        cmd_done = 1'b0;
        clr_cmd_rdy_i = 1'b0;
        nxt_state = state;
        
        case (state)
            IDLE: begin
                // clear cmd_rdy when start bit of new command detected
                if (cmd_rdy & (!RX)) begin
                    clr_cmd_rdy_i = 1'b1;
                end
                // 1st byte received
                if (rx_rdy) begin
                    get_high = 1'b1;
                    clr_rx_rdy = 1'b1;
                    nxt_state = ACTIVE;
                end
            end
            ACTIVE: begin
                // 2nd byte received - complete command
                if (rx_rdy) begin
                    clr_rx_rdy = 1'b1;
                    cmd_done = 1'b1;
                    nxt_state = IDLE;
                end
            end
			default: nxt_state = IDLE;
        endcase
    end

    // SR FF for cmd_rdy flag
    always_ff @(posedge clk, negedge rst_n) begin
        if (!rst_n)
            cmd_rdy <= 1'b0;
        else if (clr_cmd_rdy_i | clr_cmd_rdy) // either external OR internal clear
            cmd_rdy <= 1'b0;
        else if (cmd_done)
            cmd_rdy <= 1'b1;
    end

    // get high byte of command
    always_ff @(posedge clk) begin
        if (get_high)
            high_byte <= rx_data;
    end

    // assemble full 16-bit command
    assign cmd = {high_byte, rx_data};
endmodule
