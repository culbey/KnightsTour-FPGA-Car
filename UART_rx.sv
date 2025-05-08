module UART_rx (
    input logic clk, rst_n,
    input RX, 
    input clr_rdy,
    output logic [7:0] rx_data,
    output logic rdy
);
    // Internal signals
    logic start, shift, receiving;
    logic set_rdy;
    logic [3:0] bit_cnt;		// Counter for tracking number of received bits
    logic [11:0] baud_cnt;		// Baud counter to manage sampling timing
    logic [8:0] rx_shft_reg;	// Shift register for assembling received data bits
    logic RX_meta, RX_sync;		// Double flops for RX to handle metastability

    // Local Parameters
    localparam BAUD_DIV_HALF = 12'd1302;	// Half baud rate for sampling at middle of bits
    localparam BAUD_DIV = 12'd2604;		// Full baud rate for entire bit period

    // State machine
    typedef enum logic [1:0] {IDLE, SHIFT} state_t;
    state_t state, nxt_state;

    // Double Flop RX for metastability
    always_ff @(posedge clk, negedge rst_n) begin
        if (!rst_n) begin
            RX_meta <= 1'b1;
            RX_sync <= 1'b1;
        end else begin
            RX_meta <= RX;
            RX_sync <= RX_meta;
        end
    end

    // Sequential logic for state machine
    always_ff @(posedge clk, negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
        end else begin
            state <= nxt_state;
        end
    end

    // Combinational logic for state machine
    always_comb begin
        start = 1'b0;
        receiving = 1'b0;
        set_rdy = 1'b0;
        nxt_state = state;

        case (state)
            // IDLE state: Wait for falling edge of RX
            IDLE: begin
                if (!RX_sync) begin
                    nxt_state = SHIFT;
                    start = 1'b1;
                end
            end
                    
            // SHIFT state: Shift in 8 data bits
            SHIFT: begin
                receiving = 1'b1;
                set_rdy = (bit_cnt == 4'd10); 		// Set ready after 10 bits (1 start, 8 data, 1 stop)
                if (set_rdy) begin
                    nxt_state = IDLE;	// Return to IDLE after reception completes
                end 
            end
        endcase
    end

    // Bit counter: counts the received bits
    always_ff @(posedge clk, negedge rst_n) begin
        if (!rst_n) begin
            bit_cnt <= 4'd0;
        end else if (start) begin
            bit_cnt <= 4'd0;		// Reset bit counter on start
        end else if (shift) begin
            bit_cnt <= bit_cnt + 1'b1;	// Increment bit counter on each shift
        end
    end

    // Baud counter: timing bit shifts
    always_ff @(posedge clk, negedge rst_n) begin
        if (!rst_n) begin
            baud_cnt <= 12'd0;
        end else if (start | shift) begin
            baud_cnt <= (bit_cnt == 4'd0) ? BAUD_DIV_HALF : BAUD_DIV;	// Set baud counter for initial half period or full period
        end else if (receiving) begin
            baud_cnt <= baud_cnt - 1'b1;				// Decrement baud counter during reception
        end
    end

    // Shift signal asserts when baud counter reaches zero
    assign shift = ~(|baud_cnt);

    // Shift register to store received data bits
    always_ff @(posedge clk, negedge rst_n) begin
        if (!rst_n) begin
            rx_shft_reg <= 9'h1ff;				// Initialize shift register to all ones (idle)
        end else if (shift) begin
            rx_shft_reg <= {RX_sync, rx_shft_reg[8:1]};	// Shift in RX_sync bit
        end
    end

    // Output only the data bits from the shift register
    assign rx_data = rx_shft_reg[7:0];

    // Control signal for ready status
    always_ff @(posedge clk, negedge rst_n) begin
        if (!rst_n) begin
            rdy <= 1'b0;
        end else if (clr_rdy | start) begin
            rdy <= 1'b0;			// Clear ready flag on clear signal or new start
        end else if (set_rdy) begin
            rdy <= 1'b1;			// Set ready flag when data is completely received
        end
    end

endmodule