module SPI_mnrch(clk, rst_n, SS_n, SCLK, MOSI, MISO, snd, cmd, done, resp);

input clk, rst_n;
input MISO;		// Monarch In line
input snd;		// High for 1 clk to init SPI transaction
input [15:0]cmd;	// command being sent to inertial sensor

output logic SS_n, SCLK, MOSI, done;	// SS_n -> Active low serf select, SCLK -> serial clk, MOSI -> monarch out line, done -> high when SPI transaction is complete
output [15:0] resp;		// data from SPI serf


    // STATE DEFINITIONS AND FLOP
    typedef enum reg [1:0] {IDLE, TRMT, BCK} state_t;
    state_t state, nxt_state;

    always_ff @(posedge clk, negedge rst_n) begin
        if (!rst_n)
            state <= IDLE;
        else
            state <= nxt_state;
    end


    logic init, shft;
    // MOSI/MISO LOGIC
    logic [15:0] shft_reg;
    assign MOSI = shft_reg[15];

    always_ff @(posedge clk) begin
        if (init)
            shft_reg <= cmd;
        else if (shft)
            shft_reg <= {shft_reg[14:0], MISO};
    end

    assign resp = shft_reg[7:0];

    // SCLK LOGIC
    logic full, ld_SCLK;
    logic [4:0] SCLK_div;

    assign SCLK = SCLK_div[4];
    assign full = &SCLK_div;
    assign shft = (SCLK_div === 5'b10001) ? 1'b1 : 1'b0;

    always_ff @(posedge clk) begin
        if(ld_SCLK)
            SCLK_div <= 5'b10111;
        else
            SCLK_div <= SCLK_div + 1;
    end

    // SHIFT COUNTER
    logic done16;
    logic [4:0] bit_cntr;

    assign done16 = (bit_cntr == 5'b10000) ? 1'b1 : 1'b0;

    always_ff @(posedge clk) begin
        if (init)
            bit_cntr <= 5'h00;
        else if (shft)
            bit_cntr <= bit_cntr + 1;
    end

    // STATE OUTPUT AND TRANSITION LOGIC
    logic set_done;
    always_comb begin
        init = 0;
        ld_SCLK = 1'b1;
        set_done = 0;
        nxt_state = state;

        case(state)
            TRMT: begin
                ld_SCLK = 1'b0;
                if (done16) nxt_state = BCK;
                end
            BCK: if (full) begin
                    set_done = 1'b1;
                    nxt_state = IDLE;
                end else ld_SCLK = 1'b0;
            default: // IDLE
                if (snd) begin
                    init = 1'b1;
                    nxt_state = TRMT;
                end
        endcase
    end

    // done/SS_n SR-flop
    always_ff @(posedge clk, negedge rst_n) begin
        if (!rst_n) begin
            SS_n <= 1'b1;
            done <= 1'b0;
        end
        else if (init) begin
            SS_n <= 1'b0;
            done <= 1'b0;
        end
        else if (set_done) begin
            SS_n <= 1'b1;
            done <= 1'b1;
        end
    end

endmodule