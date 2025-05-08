module UART_tx(
    input logic clk, rst_n, 
    input logic trmt,
    input logic [7:0] tx_data,
    output logic TX, tx_done
);
    // Internal signals
    logic init, shift, transmitting, set_done;		
    logic [3:0] bit_cnt;					
    logic [11:0] baud_cnt;
    logic rst_baud;
    logic [8:0] tx_shft_reg;                     

    // State machine
    typedef enum reg {INIT, TRANSMITTING} state_t;
    state_t state, nxt_state;

    // Sequential logic for state machine
    always_ff@(posedge clk or negedge rst_n) begin
        if (!rst_n) state <= INIT;					// Reset to INIT state
        else state <= nxt_state;				// Move to next state
    end

    // Combinational logic for state machine
    always_comb begin
        set_done = 1'b0;
        init = 1'b0;
        transmitting = 1'b0;
        nxt_state = state;

        case (state)

            // INIT state : waiting for trmt
            INIT: begin
                if (trmt) begin
                    nxt_state = TRANSMITTING;    			// Transition to TRANSMITTING state
                    init = 1'b1;					// Initialize transmission
                    transmitting = 1'b1;   			        // Set transmission active
                end
            end

            // TRANSMITTING state: shift the data and send each bit
            TRANSMITTING: begin
                transmitting = 1'b1;             			// Enable transmission
                if (bit_cnt == 4'hA) begin       			// After 10 bits (start, 8 data, stop)
                    nxt_state = INIT;            			// Go back to INIT state
                    set_done = 1'b1;             			// Signal transmission complete
                end else begin
                    nxt_state = TRANSMITTING;
                    init = 1'b0;
                end
            end

            default: nxt_state = INIT;
        endcase
    end

    // Bit counter
    always_ff@(posedge clk) begin
        if (init) bit_cnt <= 0;	    // Initialize bit counter at the start of transmission
        else if (shift) bit_cnt <= bit_cnt + 1;     // Increment bit counter during transmission
    end

    // Baud counter

    always_ff @(posedge clk) begin
        if (init | shift) baud_cnt <= 12'h000;
        else if (transmitting) baud_cnt <= baud_cnt + 1;
    end

    // Shift
    always_ff@(posedge clk, negedge rst_n) begin
        if (!rst_n) tx_shft_reg <= 9'h1FF;      // Reset to idle state (TX line high)
        else if (init) tx_shft_reg <= {tx_data, 1'b0};      // Load tx_data with start bit (LSB first)
        else if (shift) tx_shft_reg <= {1'b1, tx_shft_reg[8:1]};    // Shift right, LSB out first
    end

    assign TX = tx_shft_reg[0];     // Output LSB to TX

    // SR Flop
    always_ff@(posedge clk, negedge rst_n) begin
        if (!rst_n)
            tx_done <= 1'b0;    // Reset tx_done
        else if (init)
            tx_done <= 1'b0;    // Clear tx_done on initialization
        else if (set_done)
            tx_done <= 1'b1;    // Set tx_done when transmission is complete
    end         				

    assign shift = {baud_cnt == 12'd2604};

endmodule


		
