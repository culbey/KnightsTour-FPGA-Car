module PWM11(
	input clk,				// Clock 
	input rst_n,				// Active low reset
	input [10:0] duty,			// 11-bit duty cycle setting 
	output logic PWM_sig, PWM_sig_n		// PWM output and its complement
);

// 11-bit counter for PWM timing
logic [10:0] cnt;

// Counter block: Continuously increments from 0 to 2047 (2^11 - 1)
always @(posedge clk, negedge rst_n) begin
	if (!rst_n) cnt <= 11'h000;	// Reset counter to 0
	else cnt <= cnt + 1;		// Increment counter
end

// PWM signal generation block
always @(posedge clk, negedge rst_n) begin
	if (!rst_n) PWM_sig <= 1'b0;		    // Reset PWM signal to 0
	else if (cnt <= duty) PWM_sig <= 1'b1;	// If counter is less than or equal to duty cycle, set PWM high
	else PWM_sig <= 1'b0;			        // Set low otherwise
end

// Generate complementary PWM signal
assign PWM_sig_n = ~(PWM_sig);

endmodule
