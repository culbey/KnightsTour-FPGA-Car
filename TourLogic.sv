module TourLogic(
    input clk, rst_n,
    input [2:0] x_start, y_start,	// starting position of the robot
    input go,			// high pulse on go to start
    input [4:0] indx,		// used to get move X that the robot should make
    output logic done,			// high for 1 clk pulse when done
    output [7:0] move		// move that the robot should perform (moves[indx])
);

    // MEM
    logic visited[0:4][0:4];		// keeps track of where the knight has visited; uses 5 bits to represent the move number
    logic [7:0] moves[0:23];		// stores the last move at each location
    logic [7:0] possible_moves[0:23];	// array of possible moves at any given position

    // OUTPUT MOVE
    assign move = moves[indx];

    // STATE
    typedef enum reg [2:0] {IDLE,INIT,POSSIBLE,MAKE_MOVE,BACKUP} state_t;
    state_t state, nxt_state;

    always_ff @(posedge clk, negedge rst_n) begin
        if (!rst_n)
            state <= IDLE;
        else
            state <= nxt_state;
    end
    
    function signed [2:0] off_y(input [7:0] try);
            casex (try) 
            8'b1???????: begin
                return 1;
            end
            8'b?1??????: begin
                return -1;
            end
            8'b??1?????: begin
                return -2;
            end
            8'b???1????: begin
                return -2;
            end
            8'b????1???: begin
                return -1;
            end
            8'b?????1??: begin
                return 1;
            end
            8'b??????1?: begin
                return 2;
            end
            default: begin
                return 2;
            end
        endcase
    endfunction

    function signed [2:0] off_x(input [7:0] try);
        casex (try)
            8'b1???????: begin
                return 2;
            end
            8'b?1??????: begin
                return 2;
            end
            8'b??1?????: begin
                return 1;
            end
            8'b???1????: begin
                return -1;
            end
            8'b????1???: begin
                return -2;
            end
            8'b?????1??: begin
                return -2;
            end
            8'b??????1?: begin
                return -1;
            end
            default: begin
                return 1;
            end
        endcase
    endfunction

    // MOVE COUNTER
    logic [4:0] move_num;		// counter to determine which move we are on
    logic inc_move, rst_move;	// signal to increment or decrement the move number
    logic backup;					// signal to backup

    always_ff @(posedge clk, negedge rst_n) begin
        if (!rst_n)
            move_num <= 5'h00;
        else if (rst_move)
            move_num <= 5'h00;
        else if (inc_move)
            move_num <= move_num + 1'b1;
        else if (backup)
            move_num <= move_num - 1'b1;
    end

    // TEST MOVES
    logic [7:0] curr_move;					// move to update cords
    logic rst_curr_move, shift_curr_move;			// reset the move to pos 0, shift to next move to test

    always_ff @(posedge clk) begin
        if (rst_curr_move)
            curr_move <= 8'h01;			// first try move 0
        else if (shift_curr_move)
            curr_move <= {curr_move[6:0], 1'b0};	// shift to test next move
        else if (backup)
            curr_move <= {moves[move_num - 1][6:0], 1'b0};
    end

    // LOCATION/LOCATION UPDATING
    logic [2:0] x_cord, y_cord;				// x and y hold current position
    logic update_cords;					// signal to update the current location
    logic init_cords;					// signal to initialize the cords to the starting pos

    always_ff @(posedge clk) begin
        if (init_cords) begin
            x_cord <= x_start;
            y_cord <= y_start;
        end
        else if (update_cords) begin
            x_cord <= x_cord + off_x(curr_move);
            y_cord <= y_cord + off_y(curr_move);
        end
        else if (backup) begin
            x_cord <= x_cord - off_x(moves[move_num - 1]);
            y_cord <= y_cord - off_y(moves[move_num - 1]);
        end
    end

    // VISITED

    logic set_visited;		// signal to re/set current location
    logic init_board, rst_board;		// initialize starting pos, reset board

    always_ff @(posedge clk) begin
        if (rst_board)
            visited <= '{'{0,0,0,0,0},'{0,0,0,0,0},'{0,0,0,0,0},'{0,0,0,0,0},'{0,0,0,0,0}};
        else if (init_board)
            visited[x_start][y_start] <= 1'b1;
        else if (set_visited)
            visited[x_cord + off_x(curr_move)][y_cord + off_y(curr_move)] <= 1;	// SET TO MOVE_NUM FOR TESTING
        else if (backup)
            visited[x_cord][y_cord] <= 5'h00;
    end

    // SAVE MOVE
    logic save_move; 		// signal to save the current move at the current move count

    always_ff @(posedge clk)
        if (save_move) moves[move_num] <= curr_move;


    // UPDATE POSSIBLE MOVES FOR CURRENT LOCATION
    logic [7:0] poss_moves;			// the set of possible moves to set to
    logic set_possible_moves;		// signal to set the possible moves

    always_ff @(posedge clk)
        if (set_possible_moves) possible_moves[move_num] <= poss_moves;



    always_comb begin

        nxt_state = state;
        done = 1'b0;
        // update location
        shift_curr_move = 1'b0;		// move used to update the x and y cords
        rst_curr_move = 1'b0;		// reset the curr move to pos 0
        update_cords = 1'b0;		// signals the cordinates should be updated
        backup = 1'b0;		// signal to backup cords
        init_cords = 1'b0;		// signal to initialize x, y to start vals

        // update move counter
        inc_move = 1'b0;		// signal to increment the move count number
        save_move = 1'b0;		// signal to decrement the move count number
        rst_move = 1'b0;		// signal to reset move counter to 0

        // update visited
        init_board = 1'b0;		// set starting location on board to 1
        rst_board = 1'b0;		// reset the board to 0s
        set_visited = 1'b0;		// set the current x,y cord as visited

        // update possible moves
        poss_moves = 8'hFF;		// used to set possible moves at current location
        set_possible_moves = 1'b0;		// signal to update the possible moves

        case(state)

            INIT: begin
                init_board = 1'b1;
                init_cords = 1'b1;
                nxt_state = POSSIBLE;
            end
            POSSIBLE: begin

                if (x_cord > 2) begin
                    poss_moves = poss_moves & 8'b00111111; // rule out move 6 and 7

                    if (x_cord > 3) // at ind 4
                        poss_moves = poss_moves & 8'b11011110; // rule out move 0 and 5

                end


                if (x_cord < 2) begin
                    poss_moves = poss_moves & 8'b11110011; // rule out move 2 and 3

                    if (x_cord < 1) // at ind 0
                        poss_moves = poss_moves & 8'b11101101; // rule out move 1 and 4
                end

                if (y_cord > 2) begin
                    poss_moves = poss_moves & 8'b11111100; // rule out move 0 and 1

                    if (y_cord > 3) // at ind 4
                        poss_moves = poss_moves & 8'b01111011; // rule out move 2 and 7

                end


                if (y_cord < 2) begin
                    poss_moves = poss_moves & 8'b11001111; // rule out move 4 and 5

                    if (y_cord < 1) // at ind 0
                        poss_moves = poss_moves & 8'b10110111; // rule out move 3 and 6
                end

                rst_curr_move = 1'b1;		// reset curr_move to test move 0 first
                set_possible_moves = 1'b1;	// save the possible moves
                nxt_state = MAKE_MOVE;

            end
            MAKE_MOVE: begin

                if (move_num === 24) begin
                done = 1'b1;
                nxt_state = IDLE;
                end

                if (possible_moves[move_num] & curr_move && visited[x_cord + off_x(curr_move)][y_cord + off_y(curr_move)] === 0) begin

                    update_cords = 1'b1;
                    set_visited = 1'b1;
                    save_move = 1'b1;
                    inc_move = 1'b1;
                    nxt_state = POSSIBLE;
                end

                    else if (curr_move !== 8'h80)
                    shift_curr_move = 1'b1;

                else begin
                    backup = 1'b1;
                    nxt_state = BACKUP;
                end

            end

            BACKUP: begin

                if (curr_move !== 8'h00)
                    nxt_state = MAKE_MOVE;
                else begin
                    backup = 1'b1;
                end

            end

            default: // IDLE
                if (go) begin
                    rst_board = 1'b1;
                    rst_move = 1'b1;
                    nxt_state = INIT;
                end

        endcase
    end

endmodule