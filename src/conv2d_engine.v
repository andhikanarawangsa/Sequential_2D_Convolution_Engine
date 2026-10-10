// =============================================================================
// File    : conv2d_engine.v
// Project : Sequential Convolution Engine (FSMD) - Individual VLSI System Assignment
// Description:
//           Sequential 2D convolution. Input X is 5x5 (unsigned 8-bit), kernel K
//           is 3x3 (signed 8-bit), and output Y is 3x3 (signed 20-bit), with
//           stride 1 and no padding.
//           Only one MAC unit is used and shared across all operations (MAC sharing).
//
//   Y[i,j] = sum_{m=0..2} sum_{n=0..2} X[i+m, j+n] * K[m, n]
//
// Hierarchy:
//   conv2d_engine     (top)  : connects the control unit and datapath
//    |- conv2d_ctrl         : FSM (IDLE, LOAD, COMPUTE_MAC, WRITE_OUT, DONE)
//    |- conv2d_datapath     : X/K register files, indexers, multiplier, accumulator
//
// Interface Protocol:
//   1. start: A one-clock-cycle pulse while the FSM is in IDLE (or DONE)
//      initiates a new operation.
//   2. In the LOAD state, each clock cycle with in_valid=1 stores one transfer:
//        - data_X: X[0..24] in row-major order
//          (X[0,0], X[0,1], ..., X[4,4])
//        - data_K: K[0..8] in row-major order, valid for the first 9 transfers;
//          data_K is ignored for transfers 10 through 25.
//      After 25 transfers, the FSM automatically enters COMPUTE_MAC.
//      in_valid may go low (stall) during loading; stalled cycles are not counted.
//   3. out_valid: A one-clock-cycle pulse for each Y[i,j], in row-major order.
//      data_Y: The value of Y[i,j], stable while out_valid=1 and held afterward.
//   4. done: HIGH when all 9 elements of Y have been computed (DONE state).
//      It goes LOW when the next start signal is asserted.
//
// Computation latency (without stalls):
//   25 LOAD cycles + 9 x (9 MAC cycles + 1 WRITE cycle) = 115 clock cycles.
// =============================================================================
`timescale 1ns/1ps

// -----------------------------------------------------------------------------
// Top Level
// -----------------------------------------------------------------------------
module conv2d_engine (
    input  wire               clk,
    input  wire               rst_n,      // Asynchronous reset, active low
    input  wire               start,
    input  wire               in_valid,
    input  wire        [7:0]  data_X,     // Unsigned pixel
    input  wire        [7:0]  data_K,     // Signed 2's complement weight
    output wire               out_valid,
    output wire signed [19:0] data_Y,
    output wire               done
);

    // Control signals (FSM -> datapath)
    wire ld_en;       // Enable writing data_X/data_K to the register files
    wire ld_clr;      // Reset the load counter
    wire mac_en;      // One MAC cycle and advance the (m,n) index
    wire out_adv;     // Advance the output index (i,j)

    // Status signals (datapath -> FSM)
    wire load_last;   // Load counter equals 24
    wire mn_last;     // (m,n) = (2,2)
    wire out_last;    // (i,j) = (2,2)

    conv2d_ctrl u_ctrl (
        .clk       (clk),
        .rst_n     (rst_n),
        .start     (start),
        .in_valid  (in_valid),
        .load_last (load_last),
        .mn_last   (mn_last),
        .out_last  (out_last),
        .ld_en     (ld_en),
        .ld_clr    (ld_clr),
        .mac_en    (mac_en),
        .out_adv   (out_adv),
        .out_valid (out_valid),
        .done      (done)
    );

    conv2d_datapath u_dp (
        .clk       (clk),
        .rst_n     (rst_n),
        .ld_en     (ld_en),
        .ld_clr    (ld_clr),
        .mac_en    (mac_en),
        .out_adv   (out_adv),
        .data_X    (data_X),
        .data_K    (data_K),
        .load_last (load_last),
        .mn_last   (mn_last),
        .out_last  (out_last),
        .acc_out   (data_Y)
    );

endmodule


// -----------------------------------------------------------------------------
// Control Unit (FSM) - Moore outputs (depend only on the current state), except
// for ld_en, which also depends on in_valid in the LOAD state (Mealy behavior).
// -----------------------------------------------------------------------------
module conv2d_ctrl (
    input  wire clk,
    input  wire rst_n,
    input  wire start,
    input  wire in_valid,
    input  wire load_last,
    input  wire mn_last,
    input  wire out_last,
    output reg  ld_en,
    output reg  ld_clr,
    output reg  mac_en,
    output reg  out_adv,
    output reg  out_valid,
    output reg  done
);

    localparam [2:0] S_IDLE    = 3'd0,
                     S_LOAD    = 3'd1,
                     S_COMPUTE = 3'd2,   // COMPUTE_MAC
                     S_WRITE   = 3'd3,   // WRITE_OUT
                     S_DONE    = 3'd4;

    reg [2:0] state, next_state;

    // State register
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) state <= S_IDLE;
        else        state <= next_state;
    end

    // Next-state logic
    always @(*) begin
        next_state = state;
        case (state)
            S_IDLE:    if (start)                    next_state = S_LOAD;
            S_LOAD:    if (in_valid && load_last)    next_state = S_COMPUTE;
            S_COMPUTE: if (mn_last)                  next_state = S_WRITE;
            S_WRITE:   next_state = out_last ? S_DONE : S_COMPUTE;
            S_DONE:    if (start)                    next_state = S_LOAD;
            default:   next_state = S_IDLE;
        endcase
    end

    // Output logic
    always @(*) begin
        ld_en     = 1'b0;
        ld_clr    = 1'b0;
        mac_en    = 1'b0;
        out_adv   = 1'b0;
        out_valid = 1'b0;
        done      = 1'b0;
        case (state)
            S_IDLE:    ld_clr = 1'b1;
            S_LOAD:    ld_en  = in_valid;
            S_COMPUTE: mac_en = 1'b1;
            S_WRITE: begin
                out_valid = 1'b1;
                out_adv   = 1'b1;
            end
            S_DONE:    done = 1'b1;
            default: ;
        endcase
    end

endmodule


// -----------------------------------------------------------------------------
// Datapath
// -----------------------------------------------------------------------------
module conv2d_datapath (
    input  wire               clk,
    input  wire               rst_n,
    // Control signals from the control unit
    input  wire               ld_en,
    input  wire               ld_clr,
    input  wire               mac_en,
    input  wire               out_adv,
    // Data inputs
    input  wire        [7:0]  data_X,
    input  wire        [7:0]  data_K,
    // Status outputs to the control unit
    output wire               load_last,
    output wire               mn_last,
    output wire               out_last,
    // Result output
    output wire signed [19:0] acc_out
);

    // ---------------- X register file (25 bytes) and K register file (9 bytes) ----------------
    // No reset is applied; both memories are fully loaded in the LOAD state
    // before their contents are read.
    reg [7:0] x_mem [0:24];
    reg [7:0] k_mem [0:8];

    // ---------------- Indexers / counters ----------------
    reg [4:0] ld_cnt;      // 0..24: write address during LOAD
    reg [1:0] m, n;        // Kernel indices
    reg [1:0] i, j;        // Output indices

    assign load_last = (ld_cnt == 5'd24);
    assign mn_last   = (m == 2'd2) && (n == 2'd2);
    assign out_last  = (i == 2'd2) && (j == 2'd2);

    // Load counter (automatically wraps to 0 after the 25th transfer)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)       ld_cnt <= 5'd0;
        else if (ld_clr)  ld_cnt <= 5'd0;
        else if (ld_en)   ld_cnt <= load_last ? 5'd0 : ld_cnt + 5'd1;
    end

    // Write to the register files
    always @(posedge clk) begin
        if (ld_en) begin
            x_mem[ld_cnt] <= data_X;
            if (ld_cnt < 5'd9)
                k_mem[ld_cnt[3:0]] <= data_K;
        end
    end

    // (m,n) counter: n increments fastest and wraps to (0,0) after 9 MAC cycles
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m <= 2'd0;
            n <= 2'd0;
        end else if (mac_en) begin
            if (n == 2'd2) begin
                n <= 2'd0;
                m <= (m == 2'd2) ? 2'd0 : m + 2'd1;
            end else begin
                n <= n + 2'd1;
            end
        end
    end

    // (i,j) counter: j increments fastest and wraps to (0,0) after 9 outputs
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            i <= 2'd0;
            j <= 2'd0;
        end else if (out_adv) begin
            if (j == 2'd2) begin
                j <= 2'd0;
                i <= (i == 2'd2) ? 2'd0 : i + 2'd1;
            end else begin
                j <= j + 2'd1;
            end
        end
    end

    // ---------------- Address generation ----------------
    // x_addr = (i+m)*5 + (j+n); k_addr = m*3 + n
    // Constant multiplications are implemented using shifts and additions.
    wire [2:0] row    = {1'b0, i} + {1'b0, m};                          // 0..4
    wire [2:0] col    = {1'b0, j} + {1'b0, n};                          // 0..4
    wire [4:0] x_addr = {row, 2'b00} + {2'b00, row} + {2'b00, col};     // 0..24
    wire [3:0] k_addr = {1'b0, m, 1'b0} + {2'b00, m} + {2'b00, n};      // 0..8

    wire [7:0] x_data = x_mem[x_addr];
    wire [7:0] k_data = k_mem[k_addr];

    // ---------------- Multiplier (8-bit unsigned x 8-bit signed) ----------------
    // X is zero-extended to a 9-bit signed value to ensure correct signed multiplication.
    wire signed [8:0]  x_s  = {1'b0, x_data};
    wire signed [7:0]  k_s  = k_data;
    wire signed [16:0] prod = x_s * k_s;                // Range: -32640 to 32385
    wire signed [19:0] prod_ext = {{3{prod[16]}}, prod};

    // ---------------- 20-bit accumulator ----------------
    // On the first MAC cycle (m=n=0), the product is loaded directly into the
    // accumulator instead of clearing it. This keeps Y[i,j] stored in acc
    // during WRITE_OUT and DONE.
    wire first = (m == 2'd0) && (n == 2'd0);
    reg signed [19:0] acc;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)       acc <= 20'sd0;
        else if (mac_en)  acc <= first ? prod_ext : (acc + prod_ext);
    end

    assign acc_out = acc;

endmodule