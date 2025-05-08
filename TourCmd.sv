////////////////////
// TourCmd design //
////////////////////

module TourCmd(
	input clk,rst_n,		// 50MHz clock and asynch active low reset
	input start_tour,		// from done signal from TourLogic
	input [7:0] move,		// encoded 1-hot move to perform
	output reg [4:0] mv_indx,	// "address" to access next move
	input [15:0] cmd_UART,		// cmd from UART_wrapper
	input cmd_rdy_UART,		// cmd_rdy from UART_wrapper
	output [15:0] cmd,		// multiplexed cmd to cmd_proc
	output cmd_rdy,			// cmd_rdy signal to cmd_proc
	input clr_cmd_rdy,		// from cmd_proc (goes to UART_wrapper too)
	input send_resp,		// lets us know cmd_proc is done with the move command
	output [7:0] resp		// either 0xA5 (done) or 0x5A (in progress)
);

	////////////////  
	// Parameters //
	////////////////

	// Move encodings
	localparam MOVE0 = 8'b00000001;		// Up 2, Right 1
	localparam MOVE1 = 8'b00000010;		// Up 2, Left 1
	localparam MOVE2 = 8'b00000100;		// Up 1, Left 2
	localparam MOVE3 = 8'b00001000;		// Down 1, Left 2
	localparam MOVE4 = 8'b00010000;		// Down 2, Left 1
	localparam MOVE5 = 8'b00100000;		// Down 2, Right 1
	localparam MOVE6 = 8'b01000000;		// Down 1, Right 2
	localparam MOVE7 = 8'b10000000;   	// Up 1, Right 2

	//////////////////////
	// Internal signals //
	//////////////////////

	logic cmd_proc_sel;				// selects between UART and decomposed command
	logic clr_mv_indx;          	// clears move index counter
	logic inc_mv_indx;          	// increments move index counter
	logic [15:0] decomposed_cmd; 	// command after vertical/horizontal decomposition
	logic decomposed_cmd_rdy;		// internal command ready signal

	///////////////////////
	// Command Selection //
	///////////////////////
	assign cmd = cmd_proc_sel ? decomposed_cmd : cmd_UART;
	assign cmd_rdy = cmd_proc_sel ? decomposed_cmd_rdy : cmd_rdy_UART;

	////////////////////
	// Response Logic //
	////////////////////
	assign resp = (mv_indx == 5'd23 || !cmd_proc_sel) ? 8'hA5 : 8'h5A;

	////////////////////////
	// Move Index Counter //
	////////////////////////
	always_ff @(posedge clk) begin
	  	if (clr_mv_indx) mv_indx <= 1'b0;
	  	else if (inc_mv_indx) mv_indx <= mv_indx + 1;
	end 
  
  	// function to decompose move to vertical component
	function void decompose_vert(input [7:0] move, output [15:0] vert_move);
		case (move)
			// up 2
			MOVE0: vert_move = 16'h4002;	
			// up 2
			MOVE1: vert_move = 16'h4002;	
			// up 1		
			MOVE2: vert_move = 16'h4001;
			// down 1
			MOVE3: vert_move = 16'h47f1;
			// down 2
			MOVE4: vert_move = 16'h47f2;
			// down 2
			MOVE5: vert_move = 16'h47f2;
			// down 1
			MOVE6: vert_move = 16'h47f1;
			// up 1
			MOVE7: vert_move = 16'h4001;	
			default: vert_move = 16'h5000; // don't move, assert repeating fanfare
		endcase	
	endfunction
  
	// function to decompose move to horizontal component
	function void decompose_horiz(input [7:0] move, output [15:0] horiz_move);
		case (move)
			// right 1
			MOVE0: horiz_move = 16'h5bf1;	
			// left 1
			MOVE1: horiz_move = 16'h53f1;	
			// left 2	
			MOVE2: horiz_move = 16'h53f2;
			// left 2
			MOVE3: horiz_move = 16'h53f2;
			// left 1
			MOVE4: horiz_move = 16'h53f1;
			// right 1
			MOVE5: horiz_move = 16'h5bf1;
			// right 2
			MOVE6: horiz_move = 16'h5bf2;
			// right 2
			MOVE7: horiz_move = 16'h5bf2;	
			default: horiz_move = 16'h5000; // don't move, assert repeating fanfare	
		endcase	
	endfunction
	   
	/////////////////////
	// Defining states //
	/////////////////////   
	typedef enum logic [2:0] {IDLE, MOVE_VERT, WAIT_VERT, MOVE_HORIZ, WAIT_HORIZ} state_t;
	state_t state, nxt_state;
	   
	//////////////////////
	// State Register ////
	//////////////////////
	always_ff @(posedge clk, negedge rst_n) begin
		if (!rst_n) state <= IDLE;
	  	else state <= nxt_state;
	end   
	
	/////////////////////////
	// State machine logic //
	/////////////////////////
	always_comb begin
		// default signal assignments
		cmd_proc_sel = 1'b1;
		clr_mv_indx = 1'b0;
		decomposed_cmd = 16'hxxxx;
		decomposed_cmd_rdy = 1'b0;
		inc_mv_indx = 1'b0;
		nxt_state = state;
			
		case (state)
			// IDLE implementation below
			
			// MOVE_VERT: decompose move to vert and move
			MOVE_VERT: begin				
				// decompose cmd into vertical move
				decompose_vert(move, decomposed_cmd);
				decomposed_cmd_rdy = 1;
				if (clr_cmd_rdy) nxt_state = WAIT_VERT;
			end

			// WAIT_VERT: Execute vertical movement
			// Wait for completion of vertical movement            
			WAIT_VERT: begin
				decompose_vert(move, decomposed_cmd);
				if (send_resp) nxt_state = MOVE_HORIZ;
			end

			// MOVE_HORIZ: decompose move to horiz and move         
			MOVE_HORIZ: begin
				decompose_horiz(move, decomposed_cmd);
				decomposed_cmd_rdy = 1;
				if (clr_cmd_rdy) nxt_state = WAIT_HORIZ;
			end
			
			// WAIT_HORIZ: Execute horizontal movement
			// Wait for completion and determine next action
			WAIT_HORIZ: begin
				decompose_horiz(move, decomposed_cmd);
				if (send_resp) begin
					if (mv_indx == 5'd23) begin
						nxt_state = IDLE;
					end else begin
						inc_mv_indx = 1;
						nxt_state = MOVE_VERT;
					end
				end
			end

			// IDLE: Wait for tour to start		
			// TourCmd should act as carrier from UART_wrapper
			default: begin
			  	cmd_proc_sel = 1'b0; // passes UART directly through
				if (start_tour) begin
					cmd_proc_sel = 1'b1; // usurpes control
					clr_mv_indx = 1'b1;
					nxt_state = MOVE_VERT;
				end
            end
		endcase
	end
     
endmodule