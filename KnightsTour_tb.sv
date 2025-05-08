module KnightsTour_tb ();
	// Import test tasks
	import tb_tasks::*;
	// Test parameter
	localparam FAST_SIM = 1;
	/////////////////////////////
	// Stimulus of type reg //
	/////////////////////////
	reg clk, RST_n;
	reg [15:0] cmd;
	reg send_cmd;
	///////////////////////////////////
	// Declare any internal signals //
	/////////////////////////////////
	wire SS_n, SCLK, MOSI, MISO, INT;
	wire lftPWM1, lftPWM2, rghtPWM1, rghtPWM2;
	wire TX_RX, RX_TX;
	logic cmd_sent;
	logic resp_rdy;
	logic [7:0] resp;
	wire IR_en;
	wire lftIR_n, rghtIR_n, cntrIR_n;
	wire piezo, piezo_n;


	logic test_cal_done;
	logic test_moving;

	logic [2:0] init_pos_x;
	logic [2:0] init_pos_y;

	//////////////////////
	// Instantiate DUT //
	////////////////////
	KnightsTour iKnight (
		.clk(clk), .RST_n(RST_n), .SS_n(SS_n), .SCLK(SCLK), .MOSI(MOSI), .MISO(MISO), .INT(INT),
		.lftPWM1(lftPWM1), .lftPWM2(lftPWM2),.rghtPWM1(rghtPWM1),.rghtPWM2(rghtPWM2),.RX(RX_TX),
		.TX(TX_RX),.piezo(piezo),.piezo_n(piezo_n),.IR_en(IR_en),.lftIR_n(lftIR_n),.rghtIR_n(rghtIR_n),
		.cntrIR_n(cntrIR_n)
	);
	/////////////////////////////////////////////////////
	// Instantiate RemoteComm to send commands to DUT //
	///////////////////////////////////////////////////
	RemoteComm iRMT_Comm (
		.clk(clk), .rst_n(RST_n), .RX(TX_RX), .TX(RX_TX), .cmd(cmd),
		.snd_cmd(send_cmd), .cmd_snt(cmd_sent), .resp_rdy(resp_rdy), .resp(resp)
	);
	//////////////////////////////////////////////////////
	// Instantiate model of Knight Physics (and board) //
	////////////////////////////////////////////////////
	KnightPhysics iKnight_PHYS (
		.clk(clk), .RST_n(RST_n), .SS_n(SS_n), .SCLK(SCLK), .MISO(MISO), .MOSI(MOSI),
		.INT(INT), .lftPWM1(lftPWM1), .lftPWM2(lftPWM2), .rghtPWM1(rghtPWM1), .rghtPWM2(rghtPWM2),
		.IR_en(IR_en), .lftIR_n(lftIR_n), .rghtIR_n(rghtIR_n), .cntrIR_n(cntrIR_n)
	);


	assign test_cal_done = iKnight.iNEMO.cal_done;
	assign test_moving = iKnight.iCMD.moving;

	initial begin
		$display("knight initialization/calibration tests...");
		// Initialize DUT
		initialize(clk, RST_n);
		wait4sig(iKnight_PHYS.iNEMO.NEMO_setup, 250000, clk, "NEMO_setup");
		$display("SUCCESS: NEMO_setup test");
		
		@(posedge clk);
		cmd = 16'h2xxx;
		send_cmd = 1'b1;
		@(posedge clk) send_cmd = 1'b0;
		
		wait4sig(test_cal_done, 1000000, clk, "cal_done");
		repeat (40000) @(posedge clk);
		assert (resp === 8'hA5) else begin
			$display("ERROR: calibration failed, expected 8'hA5, got %h", resp);
			$stop();
		end
		$display("SUCCESS: calibration test");

		init_pos_x = iKnight_PHYS.xx[14:12];
		init_pos_y = iKnight_PHYS.yy[14:12];
		
		@(negedge clk);
		cmd = 16'h43F1;		// Command to move west 1 square
		send_cmd = 1'b1;
		@(negedge clk) send_cmd = 1'b0;
		
		// Monitor heading change toward west (-X = sext(3F))
		fork 
			// to monitor heading convergence
			begin: heading_check1
				wait4sig(test_moving, 1000000, clk, "moving");
				repeat (10000000) @(posedge clk) begin
					if(iKnight.iNEMO.heading == 12'h3FF) begin
						$display("SUCCESS: Heading converged to west");
						disable heading_check1;
					end
				end
			end
			
			// to check center IR transitions
			begin: ir_check1
				@(posedge cntrIR_n);
				$display("SUCCESS: First center IR transition detected (leaving square)");
				@(posedge cntrIR_n);
				$display("SUCCESS: Second center IR transition detected (entering new square)");
				disable ir_check1;
			end
			
			// to check wheel duty cycles relative to each other
			begin: wheel_check1
				repeat(70000) @(posedge clk);
				if($signed(iKnight_PHYS.omega_rght) > $signed(iKnight_PHYS.omega_lft)) begin
					$display("SUCCESS: Right wheel speed > left wheel speed for west turn");
					disable wheel_check1;
				end else begin
					$display("ERROR: Expected right wheel speed (got %d) > left wheel speed (got %d) at time %t", iKnight_PHYS.omega_rght, iKnight_PHYS.omega_lft, $time);
					disable wheel_check1;
				end
			end

			// to check omega_sum ramping up
      		begin: omega_check1
        		int last_omega_sum;
        		last_omega_sum = iKnight_PHYS.omega_sum;
        		repeat(50000) @(posedge clk) begin
          			if(iKnight_PHYS.omega_sum > last_omega_sum) begin
            			$display("SUCCESS: omega_sum ramping up detected: from %d to %d", 
                    	last_omega_sum, iKnight_PHYS.omega_sum);
            			disable omega_check1;
          			end
          			last_omega_sum = iKnight_PHYS.omega_sum;
        		end
				$display("ERROR: omega_sum did not ramp up");
      		end
		join
		
		check_location(iKnight_PHYS.xx, iKnight_PHYS.yy, init_pos_x - 1, init_pos_y);

		@(negedge clk);
		cmd = 16'h47F2;		// Command to move south 2 squares
		send_cmd = 1'b1;
		@(negedge clk) send_cmd = 1'b0;
		
		// Monitor heading change toward south (-Y = sext(7F))
		fork 
			// to monitor heading convergence
			begin: heading_check2
				wait4sig(test_moving, 1000000, clk, "moving");
				repeat (10000000) @(posedge clk) begin
					if(iKnight.iNEMO.heading == 12'h7FF) begin
						$display("SUCCESS: Heading converged to south");
						disable heading_check2;
					end
				end
			end
			
			// to check center IR transitions
			begin: ir_check2
				@(posedge cntrIR_n);
				$display("SUCCESS: First center IR transition detected (leaving orig square)");
				@(posedge cntrIR_n);
				$display("SUCCESS: Second center IR transition detected (entering 1st square)");
				@(posedge cntrIR_n);
				$display("SUCCESS: Third center IR transition detected (leaving 1st square)");
				@(posedge cntrIR_n);
				$display("SUCCESS: Fourth center IR transition detected (entering 2nd square)");
				repeat (10000) @(posedge clk);
				check_location(iKnight_PHYS.xx, iKnight_PHYS.yy, init_pos_x - 1, init_pos_y - 2);
				disable ir_check2;
			end
			
			// to check wheel duty cycles relative to each other
			begin: wheel_check2
				repeat(70000) @(posedge clk);
				if($signed(iKnight_PHYS.omega_rght) > $signed(iKnight_PHYS.omega_lft)) begin
					$display("SUCCESS: Right wheel speed > left wheel speed for west turn");
					disable wheel_check2;
				end else begin
					$display("ERROR: Expected right wheel speed (got %d) > left wheel speed (got %d) at time %t", iKnight_PHYS.omega_rght, iKnight_PHYS.omega_lft, $time);
					disable wheel_check2;
				end
			end

		join
		
		@(negedge clk);
    	cmd = 16'h4BF1;     // move east 1 square
    	send_cmd = 1'b1;
    	@(negedge clk) send_cmd = 1'b0;

    	wait4sig(iKnight.iCMD.move_done, 100000000, clk, "east move complete");
		check_location(iKnight_PHYS.xx, iKnight_PHYS.yy, init_pos_x, init_pos_y - 2);

    	@(negedge clk);
    	cmd = 16'h5002;     // move north 2 squares w/ fanfare
    	send_cmd = 1'b1;
    	@(negedge clk) send_cmd = 1'b0;

    	wait4sig(iKnight.iCMD.move_done, 100000000, clk, "north move complete");
		wait4sig(iKnight.iCMD.send_resp, 1000000, clk, "send_resp");
		assert (resp === 8'hA5) else begin
			$display("ERROR: wrong response failed, expected 8'hA5, got %h", resp);
			$stop();
		end
		wait4sig(iKnight.iCMD.fanfare_go, 10, clk, "fanfare_go");
    
    	repeat(10000) @(posedge clk);
    	check_location(iKnight_PHYS.xx, iKnight_PHYS.yy, init_pos_x, init_pos_y);  // Should be back at initial position


	
		// test TourLogic
		@(negedge clk);
    	cmd = 16'h6022;     // start tour logic from (2,2) (curr pos)
    	send_cmd = 1'b1;
    	@(negedge clk) send_cmd = 1'b0;
		// Check Vertical and Horizontal headings and disances of 1st Move 
		wait4sig(iKnight.iCMD.move_done, 100000000, clk, "tour logic first move");
		assert(iKnight.iTC.cmd[11:4] === 8'h00) else 
        		$error("Move from 2x2: Wrong vertical heading. Expected 8'h00, got %h", 
               		iKnight.iTC.cmd[11:4]);
		assert(iKnight.iTC.cmd[3:0] === 4'b0010) else 
        		$error("Moved from 2x2: Wrong vertical distance. Expected 4'b0011, got %h",
              	 	iKnight.iTC.cmd[3:0]);
		wait4sig(iKnight.iCMD.move_done, 100000000, clk, "tour logic first move");
		assert(iKnight.iTC.cmd[11:4] === 8'hBF) else 
        		$error("Move from 2x2: Wrong horizontal heading. Expected 8'hBF, got %h", 
               		iKnight.iTC.cmd[11:4]);
		assert(iKnight.iTC.cmd[3:0] === 4'b0001) else 
        		$error("Moved from 2x2: Wrong horizontal distance. Expected 4'b0011, got %h",
              	 	iKnight.iTC.cmd[3:0]);

		// Check Vertical and Horizontal headings and distances of 2nd Move 
		wait4sig(iKnight.iCMD.move_done, 100000000, clk, "tour logic second move");
		assert(iKnight.iTC.cmd[11:4] === 8'h7F) else 
        		$error("Move from 2x2: Wrong vertical heading. Expected 8'h00, got %h", 
               		iKnight.iTC.cmd[11:4]);
		assert(iKnight.iTC.cmd[3:0] === 4'b0001) else 
        		$error("Moved from 2x2: Wrong vertical distance. Expected 4'b0011, got %h",
              	 	iKnight.iTC.cmd[3:0]);
		wait4sig(iKnight.iCMD.move_done, 100000000, clk, "tour logic first move");
		assert(iKnight.iTC.cmd[11:4] === 8'h3F) else 
        		$error("Move from 2x2: Wrong horizontal heading. Expected 8'hBF, got %h", 
               		iKnight.iTC.cmd[11:4]);
		assert(iKnight.iTC.cmd[3:0] === 4'b0010) else 
        		$error("Moved from 2x2: Wrong horizontal distance. Expected 4'b0011, got %h",
              	 	iKnight.iTC.cmd[3:0]);
		
		// Verify resp = h'5A after send_resp is asserted
		wait4sig(iKnight.iCMD.send_resp, 100000000, clk, "resp = 5A");
		assert(iKnight.iTC.resp == 8'h5A) else 
			$error("Resp did not equal 5A when send_resp was asserted");
		$display("SUCCESS: First 2 Moves: start tour logic from (2,2)");
		wait(iKnight.iTC.resp == 8'hA5);
		$stop();
	end

	always #5 clk = ~clk;
endmodule
