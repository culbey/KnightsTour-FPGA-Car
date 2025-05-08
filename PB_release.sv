module PB_release(
	input PB,           	// Push Button input, asynchronous
	input rst_n, clk,    	// Active low reset and clock signals
	output logic released 	// Output to indicate button release (rising edge detection)
);

    logic PB_ff1;        	// First flip-flop for synchronizing PB to clk domain
    logic PB_ff2;        	// Second flip-flop for double-flopping (reduces metastability)
    logic PB_ff3;        	// Third flip-flop used for rising edge detection

    always_ff @(posedge clk, negedge rst_n) begin
        if (!rst_n) begin
        // Asynchronous reset for all flip-flops
        PB_ff1 <= 1'b1;
        PB_ff2 <= 1'b1;
        PB_ff3 <= 1'b1;
        end else begin
        // Shift the PB signal through the flip-flops
        PB_ff1 <= PB;
        PB_ff2 <= PB_ff1;
        PB_ff3 <= PB_ff2;
        end
    end

    // Rising edge detection logic
    // Output 'released' is high when PB_ff2 is high and PB_ff3 is low
    assign released = PB_ff2 & ~(PB_ff3);

endmodule
