module sponge(clk, rst_n, go, piezo, piezo_n); 

parameter FAST_SIM = 1; // Parameter for fast simulation (1 for fast, 0 for normal)

input clk, rst_n; 
input go;						// go line to initiate a song being played
output logic piezo, piezo_n;	// pizeo line, and inverted piezo line to play the song

logic [14:0] freq_cnt;  		// Register used to count Frequency of Notes
logic [24:0] dur_cnt;   		// Register used to count Duration of Notes
logic en;						// Register that enables the counters, used to save power consumption
logic [14:0] note_freq;		 	// note frequency register
logic [24:0] duration;  		// note duration register
logic note_complete;			// signal to notify when note duration is complete
logic init;						// signal from SM to notify the song is gonna be played
logic swap;						// signal for piezo and piezo_n to to invert, to create square wave.

localparam D7_FREQ = 15'h2992;	// Count value for 50MHz clock for frequency Octave 7 Note D
localparam E7_FREQ = 15'h2508;  // Count value for 50MHz clock for frequency Octave 7 Note E
localparam F7_FREQ = 15'h20FD;  // Count value for 50MHz clock for frequency Octave 7 Note F#
localparam A6_FREQ = 15'h377C;  // Count value for 50MHz clock for frequency Octave 6 Note A

localparam DUR_2_23 = 2**23;	// Duration for Notes
localparam DUR_2_22 = 2**22;	// Duration for Notes

logic [4:0] increment;			// Increment value for duration counter based on FAST_SIM

////////////////////////////////////////////////////////
// Speed up simulation by 16 times if FAST SIM is high//
////////////////////////////////////////////////////////
generate
  assign increment = (FAST_SIM) ? 5'h10 : 1'b1;
endgenerate

//////////////////////////
// State Machine states //
//////////////////////////
typedef enum logic [3:0] {IDLE, D7_1, E7_2, F7_3, E7_4, F7_5, D7_6, A6_7, D7_8} state_t;
state_t state, nxt_state;

///////////////////
// State Machine //
///////////////////
always_ff @(posedge clk, negedge rst_n)
  if (!rst_n) 
    state <= IDLE;
  else
    state <= nxt_state;

always_comb begin 
  // Default Values // 
  nxt_state = state;
  note_freq = 0;
  duration = 0;
  en = 0;
  init = 0;
  
  case (state) 
    // Idle state, no note is playing //
    IDLE: 
      if (go) begin
	note_freq = D7_FREQ;
	duration = DUR_2_23;
	nxt_state = D7_1;
	en = 1;
	init = 1;
       end
    // The first D note in the song //
    D7_1: begin
      en = 1;
      if (note_complete) begin
        note_freq = E7_FREQ;
	duration = DUR_2_23;
	nxt_state = E7_2;
      end else begin
	note_freq = D7_FREQ;
	duration = DUR_2_23;
      end
    end
    
	// The second note with is an E //
    E7_2: begin
      en = 1;
      if (note_complete) begin
        note_freq = F7_FREQ;
	duration = DUR_2_23;
	nxt_state = F7_3;
      end else begin
	note_freq = E7_FREQ;
	duration = DUR_2_23;
      end
    end

    // The third note with is an F //
    F7_3: begin
      en = 1;
      if (note_complete) begin
        note_freq = E7_FREQ;
	duration = DUR_2_22 + DUR_2_23;
	nxt_state = E7_4;
      end else begin
	note_freq = F7_FREQ;
	duration = DUR_2_23;
      end
    end

    // The fourth note which is an E //
    E7_4: begin
      en = 1;
      if (note_complete) begin
        note_freq = F7_FREQ;
	duration = DUR_2_22;
	nxt_state = F7_5;
      end else begin
	note_freq = E7_FREQ;
	duration = DUR_2_22 + DUR_2_23;
      end
    end

    // The fifth note with is an F //
    F7_5: begin
      en = 1;
      if (note_complete) begin
        note_freq = D7_FREQ;
	duration = DUR_2_22 + DUR_2_23;
	nxt_state = D7_6;
      end else begin
	note_freq = F7_FREQ;
	duration = DUR_2_22;
      end
    end
    
	// The 6th note which is a D //
    D7_6: begin
      en = 1;
      if (note_complete) begin
        note_freq = A6_FREQ;
	duration = DUR_2_22;
	nxt_state = A6_7;
      end else begin
	note_freq = D7_FREQ;
	duration = DUR_2_22+ DUR_2_23;
      end
    end

    // The 7th note which is an A // 
    A6_7: begin
      en = 1;
      if (note_complete) begin
        note_freq = D7_FREQ;
	duration = DUR_2_23;
	nxt_state = D7_8;
      end else begin
	note_freq = A6_FREQ;
	duration = DUR_2_22;
      end
    end

    // The last note which is an D //
    D7_8: begin
      en = 1;
      if (note_complete) begin
	en = 0;
	nxt_state = IDLE;
      end else begin
	note_freq = D7_FREQ;
	duration = DUR_2_23;
      end
    end

    default: nxt_state = IDLE;
  endcase
end
	
///////////////////////
// Frequency Counter //
///////////////////////
always_ff @(posedge clk, negedge rst_n)
  if (!rst_n) begin
    freq_cnt <= 0;
    swap <= 0;
  end
  else if (note_freq <= freq_cnt)begin
    freq_cnt <= 0;
    swap <= 1;
  end
  // When  not enabled, the circuit doesn't counts to save power when not playing a song //
  else if (en) begin
    freq_cnt <= freq_cnt + 1'b1;
    swap <= 0;
  end

//////////////////////
// Duration Counter //
//////////////////////

    always_ff @(posedge clk, negedge rst_n) begin
      if (!rst_n) begin
        dur_cnt <= 0;
	note_complete <= 0;
      end
      else if (duration <= dur_cnt) begin
         dur_cnt <= 0;
	 note_complete <= 1;
      end
	  // Duration only counts when song is being played to save power //
      else if (en) begin
         dur_cnt <= dur_cnt + increment; // Increment by 16 in FAST_SIM mode
         note_complete <= 0;
	end
    end

///////////////
// Set Piezo //
///////////////
always_ff @(posedge clk, negedge rst_n)
  if (!rst_n) begin
    piezo <= 0;
    piezo_n <= 1;
  end else if (init) begin
    piezo <= 0;
    piezo_n <= 1;
  // Set piezo and piezo_n to reset level when not playing the song //
  end else if (!en) begin
    piezo <= 0; 
    piezo_n <= 1;
  end else if (swap && en) begin
    piezo <= ~piezo;
    piezo_n <= ~piezo_n;
  end   

endmodule
