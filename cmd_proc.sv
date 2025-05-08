module cmd_proc(
	input clk,rst_n,				// 50MHz clock and asynch active low reset
	input [15:0] cmd,				// command from BLE
	input cmd_rdy,				// command ready
	output logic clr_cmd_rdy,			// mark command as consumed
	output logic send_resp,			// command finished, send_response via UART_wrapper/BT
	output logic strt_cal,			// initiate calibration of gyro
	input cal_done,				// calibration of gyro done
	input signed [11:0] heading,			// heading from gyro
	input heading_rdy,				// pulses high 1 clk for valid heading reading
	input lftIR,					// nudge error +
	input cntrIR,					// center IR reading (have I passed a line)
	input rghtIR,					// nudge error -
	output reg signed [11:0] error,		// error to PID (heading - desired_heading)
	output reg [9:0] frwrd,			// forward speed register
	output logic moving,				// asserted when moving (allows yaw integration)
	output logic tour_go,				// pulse to initiate TourCmd block
	output logic fanfare_go			// kick off the "Charge!" fanfare on piezo
);

	parameter FAST_SIM = 1;			// speeds up incrementing of frwrd register for faster simulation

	localparam [11:0] HEADING_THRESH = 12'h02C; // = d'44

	// FORWARD REGISTER
	logic inc_frwrd, dec_frwrd; 	// SM OUTPUTS

	logic frwrd_zero, frwrd_max_spd;
	assign frwrd_max_spd = &frwrd[9:8];	// max_spd when top 2 bits are 1
	assign frwrd_zero = ~|frwrd;

	logic [7:0] frwrd_amt;	// how much to inc/dec frwrd speed
	assign frwrd_amt =	(FAST_SIM & inc_frwrd) ? 8'h20 : 
						(~FAST_SIM & inc_frwrd) ? 8'h03 :
						(FAST_SIM & dec_frwrd) ? 8'h40 : // 2*(h'20)
						8'h06;
				
	// frwrd speed flop
	always_ff @(posedge clk, negedge rst_n) begin
		if (!rst_n)
			frwrd <= 10'h000;
		// if not at max speed AND need to speed up, ADD frwrd_amt
		else if (heading_rdy & ~frwrd_max_spd & inc_frwrd)
			frwrd <= frwrd + frwrd_amt;
		// if still moving AND need to slow down, SUBTRACT frwrd_amt
		else if (heading_rdy & ~frwrd_zero & dec_frwrd)
			frwrd <= frwrd - frwrd_amt;
		else if (frwrd_max_spd)
			frwrd <= 10'h300; // prevent from filling up bits [7:0]
		else if (frwrd_zero)
			frwrd <= 10'h000;
	end


	// PID INTERFACE
	logic [11:0] err_nudge, desired_heading;
	logic move_cmd; // SM output

	// err_nudge dictates to PID how much to correct course when IR sensors detect wandering
	assign err_nudge =	(FAST_SIM & lftIR) ? 12'h1FF : 	
						(~FAST_SIM & lftIR) ? 12'h05F :
						(FAST_SIM & rghtIR) ? 12'hE00 :
						(~FAST_SIM & rghtIR) ? 12'hFA1 :
						12'h000;

	// desired heading flop
	always_ff @(posedge clk, negedge rst_n) begin
		if (!rst_n)
			desired_heading <= 12'h000;
		else if (move_cmd) // promote bits and append 'F' if non-zero
			desired_heading <= (|cmd[11:4]) ? {cmd[11:4], 4'hF} : 12'h000;
	end

	assign error = $signed(heading) - $signed(desired_heading) + $signed(err_nudge);


	// STATES
	typedef enum logic [3:0] {IDLE, CALIB, WAIT_HEADING, MOVE_STRT, MOVE_FWD, SLOWING, FANFARE} state_t;
	state_t state, nxt_state;


	// COUNTING SQUARES
	logic [3:0] squares_to_move;
	logic [3:0] center_ir_cnt; // counter for centerIR pulses
	logic cntrIR_ff;
	logic rise_detected;
	logic move_done;
		
	// center IR risng edge detector
	always_ff @(posedge clk, negedge rst_n) begin
		if (!rst_n)
			cntrIR_ff <= 1'b0;
		else
			cntrIR_ff <= cntrIR;
	end
	assign rise_detected = ~(cntrIR_ff) & cntrIR;

	// counter for cntrIR pulses
	always_ff @(posedge clk, negedge rst_n) begin
		if (!rst_n)
			center_ir_cnt <= 1'b0;
		else if (move_cmd)
			center_ir_cnt <= 1'b0;
		else if (rise_detected) 
			center_ir_cnt <= center_ir_cnt + 1'b1;
	end

	// num squares to move
	always_ff @(posedge clk, negedge rst_n) begin
		if (!rst_n)
			squares_to_move <= 4'h0;
		else if (move_cmd)
			squares_to_move <= {cmd[2:0], 1'b0};
	end

	logic [2:0] old_cmd_opcode; // will equal 5 when fanfare

	// holding resgister for cmd
	always_ff @(posedge clk) begin
		if (move_cmd) old_cmd_opcode = cmd[14:12];
	end

	// move is done when we see twice as many center IR pulses as squares to move from cmd[2:0]
	assign move_done = (center_ir_cnt == squares_to_move);
		
	// SM logic
	always_ff @(posedge clk, negedge rst_n) begin
		if (!rst_n) state <= IDLE;
		else state <= nxt_state;
	end
		
	// SM outputs:
		// clr_cmd_rdy
		// send_resp
		// moving
		// dec_frwrd
		// inc_frwrd
	logic move_w_fanfare;
	assign move_w_fanfare = old_cmd_opcode == 3'd5;
	always_comb begin
		// defaults
		clr_cmd_rdy = 1'b0;
		tour_go = 1'b0;
		fanfare_go = 1'b0;
		move_cmd = 1'b0;
		inc_frwrd = 1'b0;
		dec_frwrd = 1'b0;
		strt_cal = 1'b0;
		send_resp = 1'b0;
		moving = 1'b0;
		nxt_state = state;

		case (state)
			
			// sits in IDLE until cmd_rdy
			// go to approp. state based on opcode (cmd[15:12]), assrt clr_cmd_rdy
			IDLE: begin
				if (cmd_rdy) begin
					// check opcode/what state to go to
					clr_cmd_rdy = 1;
					case (cmd[15:12])
						4'b0010: begin // calibrate
							nxt_state = CALIB;
							strt_cal = 1'b1;
						end
						
						4'b0100: begin // move
							nxt_state = MOVE_STRT;
						end
						
						4'b0101: begin // fanfare
							nxt_state = MOVE_STRT;
						end
						
						4'b0110: begin // start tour
							// do NOT assert send_resp
							tour_go = 1; //switch control to TourCmd
							nxt_state = IDLE;
						end
							
						default: begin
							nxt_state = IDLE;
							// can potentially make new "ERROR" state for invalid opcode
						end
					endcase
				end
			end
				
			CALIB: // send ACK when calibration complete
				if (cal_done) begin
					send_resp = 1;
					nxt_state = IDLE;
				end

			MOVE_STRT: begin
				// capture desired heading, wait for PID adjustments
				move_cmd = 1;
				moving = 1;
				nxt_state = WAIT_HEADING;
			end

			WAIT_HEADING: begin
				moving = 1;
				// -44 < PID error < 44
				if ((error < $signed(HEADING_THRESH)) && (error > $signed(~HEADING_THRESH + 1)))
					nxt_state = MOVE_FWD;
			end
				
			MOVE_FWD: begin
				// once PID error small enough, start to ramp up frwrd, assert moving
				moving = 1;
				inc_frwrd = 1;
				// once # of squares moved, ramp down speed, init fanfare if requested
				if (move_done) nxt_state = SLOWING;
			end
			
			SLOWING: begin
				moving = 1; // still moving even while slowing down
				dec_frwrd = 1;
				if (frwrd_zero) begin // once stopped, determine whether to use fanfare
					send_resp = 1;
					nxt_state = move_w_fanfare ? FANFARE : IDLE;
				end
			end
				
			FANFARE: begin // assert fanfare signal
				fanfare_go = 1;
				nxt_state = IDLE;
			end
				
			default: nxt_state = IDLE;
		endcase
	end
  
endmodule
