////////////////////////
// PID control module //
////////////////////////

module PID (
    input logic clk,		// Clock input
    input logic rst_n,		// Reset (active-low)
    input logic moving,		// Movement status flag
    input logic err_vld,		// Error valid flag
    input logic [11:0] error,	// Error input
    input logic [9:0] frwrd,	// Feed-forward value
    output logic [10:0] lft_spd,	// Left motor speed
    output logic [10:0] rght_spd	// Right motor speed
);

    localparam P_COEFF = 6'h10;	// Proportional coefficient constant

    // Internal signals for PID control computation
    logic signed [13:0] P_term;     // Proportional term
    logic [8:0] I_term;      // Integral term
    logic [12:0] D_term;     // Derivative term

    logic [13:0] PID_sum;    // Combined control signal
    logic [10:0] PID_top;    // MSBs of PID_sum
    logic [10:0] PID_neg;    // Inverted PID_top value

    logic [10:0] lft_sum;    // Left motor speed computation
    logic [10:0] rght_sum;   // Right motor speed computation

    //////////////////
    // P_TERM logic //
    //////////////////

    // Proportional control calculation
    logic signed [9:0] err_sat;	// Saturated error
    
    assign err_sat =    (~error[11] & |error[10:9]) ? 10'b01_1111_1111 :	// Positive error saturation
                        (error[11] & ~&error[10:9]) ? 10'b10_0000_0000 :	// Negative error saturation
                                                    error[9:0]; 			// Else, take lowest 10 bits
        
        
    // PIPELINE
    logic signed [9:0] pipe_err_sat;
    logic pipe_err_vld;

    always_ff @(posedge clk, negedge rst_n) begin
        if (!rst_n) begin
            pipe_err_sat <= 10'h000;
            pipe_err_vld <= 1'b0;
        end
        else begin
            pipe_err_sat <= err_sat;
            pipe_err_vld <= err_vld;
        end
    end

    assign P_term = pipe_err_sat * $signed(P_COEFF);

    //////////////////
    // I_TERM logic //
    //////////////////

    logic [14:0] error_saturated,	// Sign-extended saturated error
                adder,		// Sum of error and integrator
                integrator,	// Running accumulation register
                nxt_integrator;	// Next value for integrator

    logic err_ov;			// Overflow detection flag

    // Sign-extend the saturated error to 15 bits to match integrator width
    assign error_saturated = {{5{pipe_err_sat[9]}},pipe_err_sat};

    // Add current error to accumulated integral term
    assign adder = $signed(error_saturated) + $signed(integrator);

    // Detect postive and negative overflow
    assign err_ov = (error_saturated[14] & integrator[14] & ~adder[14]) |
            (~error_saturated[14] & ~integrator[14] & adder[14]);


    // Reset the integator when it's not moving, otherwise take new integration value if no overflow
    assign nxt_integrator = (~moving) ? 15'h0000 : 
                            (~err_ov & pipe_err_vld) ? adder : 
                                                    integrator;

    // Sequential logic for integration accumulation
    always_ff @(posedge clk, negedge rst_n) begin
        if (!rst_n)
            integrator <= 15'h0000;
        else
            integrator <= nxt_integrator;
    end

    // Take upper 9 bits of the integrator for I_term
    assign I_term = integrator[14:6];

    //////////////////
    // D_TERM logic //
    //////////////////

    logic signed [9:0] Out1,	// First pipeline register
                    Out2,	// Second pipeline register
                    prev_err,	// Previous error storage
                    D_diff;	// Error difference

    logic signed [7:0] D_diff_out;	// Saturated error difference

    localparam signed [4:0] D_COEFF = 5'h07;	// Derivative gain coefficient

    // Pipeline registers for error derivative calculation
    always_ff@(posedge clk, negedge rst_n) begin
        if (!rst_n) begin
            Out1 <= 10'b0;		// Clear first pipeline stage
            Out2 <= 10'b0;		// Clear second pipeline stage
            prev_err <= 10'b0;	// Clear previous error storage
        end 
        else if (pipe_err_vld) begin
            Out1 <= pipe_err_sat;    // Capture current error
            Out2 <= Out1;       // Shift to second stage of pipeline
            prev_err <= Out2;   // Store the difference calculated
        end
    end

    // Calculate difference between current and previous error
    assign D_diff = $signed(pipe_err_sat) - $signed(prev_err);

    // Saturation difference to prevent overflow
    assign D_diff_out = (~D_diff[9] & |D_diff[8:7]) ? 8'b0111_1111: // positive saturation (limit to 127)
                        (D_diff[9] & ~&D_diff[8:7]) ? 8'b1000_0000: // negative saturation (limit to -128)
                                                    D_diff[7:0];

    assign D_term = $signed(D_diff_out) * $signed(D_COEFF);

    ///////////////
    // PID Logic //
    ///////////////
    logic [10:0] pre_lft_spd, pre_rght_spd;

    assign PID_sum = {P_term[13], P_term[13:1]} + {{5{I_term[8]}}, I_term} + {D_term[12], D_term};	// add sign extended terms 
    assign PID_top = PID_sum[13:3];		// Extract upper 11 bits
    assign PID_neg = (~PID_top + 1'b1);	// 2's complement for negative PID


    // Left motor speed calculation
    assign lft_sum = PID_top + {1'b0, frwrd};					// Combine PID and frwrd_ze
    assign pre_lft_spd =    (!moving) ? 11'h000 :					// Zero output when stationary
                            ((!PID_top[10] & lft_sum[10]) ? 11'h3FF : 
                            lft_sum);	// Saturate if overflow occurs



    // Right motor speed calculation
    assign rght_sum = PID_neg + {1'b0, frwrd};					// Combine negated PID and frwrd_ze
    assign pre_rght_spd =   (!moving) ? 11'h000 :					// Zero output when stationary
                            ((!PID_neg[10] & rght_sum[10]) ? 11'h3FF : 
                            rght_sum);	// Saturate if overflow occurs

    always_ff @(posedge clk) begin
        lft_spd <= pre_lft_spd;
        rght_spd <= pre_rght_spd;
    end

endmodule
