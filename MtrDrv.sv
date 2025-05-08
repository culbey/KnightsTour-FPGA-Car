module MtrDrv(
    input clk, rst_n,			    // Clock and active low reset
    input signed [10:0] lft_spd,	// Signed 11-bit speed control for left motor        
    input signed [10:0] rght_spd,    // Signed 11-bit speed control for right motor
    output lftPWM1, lftPWM2,		// PWM control signals for left motor    
    output rghtPWM1, rghtPWM2		// PWM control signals for right motor    
);

    // Internal signals for duty cycle calculations
    logic signed [10:0] lft_duty, rght_duty;

    // Add offset of 0x400 (1024) to convert speed to duty cycle
    // This creates a 50% duty cycle when input speed is 0
    assign lft_duty = $signed(lft_spd) + 11'sh400;
    assign rght_duty = $signed(rght_spd) + 11'sh400;

    // PWM instantiation
    PWM11 lft_PWM(
        .clk(clk),
        .rst_n(rst_n),
        .duty(lft_duty),
        .PWM_sig(lftPWM1),
        .PWM_sig_n(lftPWM2)
    );

    PWM11 rght_PWM(
        .clk(clk),
        .rst_n(rst_n),
        .duty(rght_duty),
        .PWM_sig(rghtPWM1),
        .PWM_sig_n(rghtPWM2)
    );

endmodule
