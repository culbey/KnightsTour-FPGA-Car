module rst_synch(
	input clk,		// Clock
	input RST_n,		// Asynchronous Active low reset input
	output logic rst_n	// Synchronized active low reset output
);

	logic rst_mid;	// Intermediate flop signal for double-flop synchronizer

	// first flop
	always_ff @(posedge clk, negedge RST_n) begin
		if (!RST_n) begin
			rst_mid <= 0;		// Reset intermediate signal
			rst_n <= 0;		// Reset output signal
		end else begin
			rst_mid <= 1;		// First flop
			rst_n <= rst_mid;	// Second flop
		end
	end

	
endmodule
