package tb_tasks;


	// Task to initialize the testbench
	task automatic initialize(ref clk, ref RST_n);
		// Start with everything low
		clk = 0;
		@(posedge clk);
		@(negedge clk);
		RST_n = 0;
		// Hold reset for a good long time to ensure power-up stability
		repeat (50) @(posedge clk);
		@(negedge clk);
		RST_n = 1;
		// Wait additional cycles for synchronizers to settle
		repeat (10) @(posedge clk);
	endtask
	
	// task to wait for signal assertion
	task automatic wait4sig(ref sig, input int clks2wait, ref clk, input string sig_name);
		fork
			begin : timeout
				repeat (clks2wait) @(posedge clk);
				$display("ERROR: timed out waiting for %s", sig_name);
				$stop();
			end
			begin
				@(posedge sig) disable timeout;
			end
		join
	endtask
	
	task automatic print_location(ref [14:0] xx, ref [14:0] yy);
		$display("Knight at (%.2f, %.2f)", xx[14:12], yy[14:12]);
	endtask
	
	task automatic check_location(ref [14:0] xx, ref [14:0] yy, input [2:0] expected_x, input [2:0] expected_y);
    	if (!((xx[14:12] == expected_x) && (yy[14:12] == expected_y))) begin
        	$display("ERROR: moved to wrong location");
        	$display("expected (%d, %d), got (%d, %d)", expected_x, expected_y, xx[14:12], yy[14:12]);
    	end else begin
        	$display("SUCCESS: Knight positioned at (%d, %d)", expected_x, expected_y);
    	end
endtask
	
	
	
endpackage
