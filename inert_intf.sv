//////////////////////////////////////////////////////
// Interfaces with ST 6-axis inertial sensor.  In  //
// this application we only use Z-axis gyro for   //
// heading of robot.  Fusion correction comes    //
// from "gaurdrail" signals lftIR/rghtIR.       //
/////////////////////////////////////////////////
module inert_intf (
    clk,
    rst_n,
    strt_cal,
    cal_done,
    heading,
    rdy,
    lftIR,
    rghtIR,
    SS_n,
    SCLK,
    MOSI,
    MISO,
    INT,
    moving
);

  parameter FAST_SIM = 1;  // used to speed up simulation

  input clk, rst_n;
  input MISO;  // SPI input from inertial sensor
  input INT;  // goes high when measurement ready
  input strt_cal;  // initiate claibration of yaw readings
  input moving;  // Only integrate yaw when going
  input lftIR, rghtIR;  // gaurdrail sensors

  output logic cal_done;  // pulses high for 1 clock when calibration done
  output signed [11:0] heading;  // heading of robot.  000 = Orig dir 3FF = 90 CCW 7FF = 180 CCW
  output rdy;  // goes high for 1 clock when new outputs ready (from inertial_integrator)
  output SS_n, SCLK, MOSI;  // SPI outputs


  //////////////////////////////////
  // Declare any internal signal //
  ////////////////////////////////
  logic vld;  // vld yaw_rt provided to inertial_integrator

  logic snd;  // high for 1 clk to start SPI transaction
  logic [15:0] cmd;  // command being sent
  logic done;  // high when SPI is complete
  logic [15:0] resp;	// full response from SPI. (upper byte is dont care because we have to send register to read from)


  // INIT SPI_MNRCH
  SPI_mnrch MNRCH (
      .clk  (clk),
      .rst_n(rst_n),
      .SS_n (SS_n),
      .SCLK (SCLK),
      .MOSI (MOSI),
      .MISO (MISO),
      .snd  (snd),
      .cmd  (cmd),
      .done (done),
      .resp (resp)
  );

  typedef enum reg [2:0] {INIT1, INIT2, INIT3, LYAW, HYAW, WAIT} state_t;
  state_t state, nxt_state;

  // STATE TRANSITION
  always_ff @(posedge clk, negedge rst_n) begin
    if (!rst_n) state <= INIT1;
    else state <= nxt_state;
  end

  // INIT INIT TIMER
  logic [15:0] timer;  // 16-bit timer used to time the init commands
  logic timer_full;  // high when timer is full
  logic timer_clr;  // clear timer to 0

  always_ff @(posedge clk, negedge rst_n) begin
    if (!rst_n) timer <= 16'h0000;
    else if (timer_clr) timer <= 16'h0000;
    else timer <= timer + 1'b1;
  end

  assign timer_full = &timer;


  // DOUBLE FLOP ASYNCH SIGNAL INT FOR METASTABILITY
  logic INT1, INT_S;
  always_ff @(posedge clk, negedge rst_n) begin
    if (!rst_n) begin
      INT1  <= 1'b0;
      INT_S <= 1'b0;
    end else begin
      INT1  <= INT;
      INT_S <= INT1;
    end
  end

  // PITCH HOLDING REGISTERS
  logic CYH, CYL;  // signals to capture yaw high and capture yaw low into holding registers
  logic [15:0] yaw_rt;  // pitch holding registers

  always_ff @(posedge clk) begin
    if (CYH)  // get upper bits
      yaw_rt = {resp[7:0], yaw_rt[7:0]};
    else if (CYL)  // get lower bits
      yaw_rt = {yaw_rt[15:8], resp[7:0]};
  end


  // STATE TRASITION/OUTPUT LOGIC
  logic set_vld;

  always_ff @(posedge clk) begin
    vld = set_vld;
  end

  // first write to registers inside inertial sensor using SPI to configure
  // inertial sensor will raise INT signal when new values are ready
  // will read YAW high and low, pack into 16 bit YAW reading, and assert vld to integrator

  always_comb begin
    nxt_state = state;
    snd = 1'b0;
    cmd = 16'h0000;
    CYL = 1'b0;
    CYH = 1'b0;
    set_vld = 1'b0;
    timer_clr = 1'b1;

    case (state)
      WAIT:
      if (INT_S) begin
        cmd = 16'hA6xx;
        snd = 1'b1;
        nxt_state = LYAW;
      end
      HYAW:
      if (done) begin
        CYH = 1'b1;
        set_vld = 1'b1;
        nxt_state = WAIT;
      end
      LYAW:
      if (done) begin
        CYL = 1'b1;
        cmd = 16'hA7xx;
        snd = 1'b1;
        nxt_state = HYAW;
      end
      INIT3:
      if (done) begin
        cmd = 16'h1440;
        snd = 1'b1;
        nxt_state = WAIT;
      end
      INIT2:
      if (done) begin
        cmd = 16'h1160;
        snd = 1'b1;
        nxt_state = INIT3;
      end
      default: begin  // INIT1
        timer_clr = 1'b0;
        if (timer_full) begin
          cmd = 16'h0D02;
          snd = 1'b1;
          nxt_state = INIT2;
        end
      end
    endcase

  end


  ////////////////////////////////////////////////////////////////////
  // Instantiate Angle Engine that takes in angular rate readings  //
  // and acceleration info and produces a heading reading         //
  /////////////////////////////////////////////////////////////////
  inertial_integrator #(FAST_SIM) iINT (
      .clk(clk),
      .rst_n(rst_n),
      .strt_cal(strt_cal),
      .vld(vld),
      .rdy(rdy),
      .cal_done(cal_done),
      .yaw_rt(yaw_rt),
      .moving(moving),
      .lftIR(lftIR),
      .rghtIR(rghtIR),
      .heading(heading)
  );


endmodule
