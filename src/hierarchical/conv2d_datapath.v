// Datapath module for 2D convolution.
// This module manages the register file, indexer, multiplier, and accumulator.
// Author: Andhika Narawangsa Susilo

`timescale 1ns/1ps

module conv2d_datapath (
    input  wire               clk,
    input  wire               rst_n,
    // from control unit
    input  wire               ld_en,
    input  wire               ld_clr,
    input  wire               mac_en,
    input  wire               out_adv,
    // data
    input  wire        [7:0]  data_X,
    input  wire        [7:0]  data_K,
    // to control unit
    output wire               load_last,
    output wire               mn_last,
    output wire               out_last,
    // result
    output wire signed [19:0] acc_out
);

    // ---------------- Register file X (25 byte) & K (9 byte) ----------------
    // No reset (memory stored in LOAD state before being read).
    reg [7:0] x_mem [0:24];
    reg [7:0] k_mem [0:8];

    // ---------------- Indexer ----------------
    reg [4:0] ld_cnt;      // 0..24 : write address in LOAD state
    reg [1:0] m, n;        // kernel indices
    reg [1:0] i, j;        // output indices

    assign load_last = (ld_cnt == 5'd24);
    assign mn_last   = (m == 2'd2) && (n == 2'd2);
    assign out_last  = (i == 2'd2) && (j == 2'd2);

    // load indexer (wrap automatically to 0 after transfer of 25)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)       ld_cnt <= 5'd0;
        else if (ld_clr)  ld_cnt <= 5'd0;
        else if (ld_en)   ld_cnt <= load_last ? 5'd0 : ld_cnt + 5'd1;
    end

    // write register file
    always @(posedge clk) begin
        if (ld_en) begin
            x_mem[ld_cnt] <= data_X;
            if (ld_cnt < 5'd9)
                k_mem[ld_cnt[3:0]] <= data_K;
        end
    end

    // indexer (m,n): n turning fastest, wrap to (0,0) after 9 MAC
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

    // output indexer (i,j): j turning fastest, wrap to (0,0) after 9 outputs
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

    // ---------------- Address Generator ----------------
    // x_addr = (i+m)*5 + (j+n) ; k_addr = m*3 + n  (constant multiplication -> shift+add)
    wire [2:0] row    = {1'b0, i} + {1'b0, m};                          // 0..4
    wire [2:0] col    = {1'b0, j} + {1'b0, n};                          // 0..4
    wire [4:0] x_addr = {row, 2'b00} + {2'b00, row} + {2'b00, col};     // 0..24
    wire [3:0] k_addr = {1'b0, m, 1'b0} + {2'b00, m} + {2'b00, n};      // 0..8
    wire [7:0] x_data = x_mem[x_addr];
    wire [7:0] k_data = k_mem[k_addr];

    // ---------------- Multiplier (8-bit unsigned x 8-bit signed) ----------------
    // X extended with 0 to 9-bit signed for signed multiplication.
    wire signed [8:0]  x_s  = {1'b0, x_data};
    wire signed [7:0]  k_s  = k_data;
    wire signed [16:0] prod = x_s * k_s;                // range -32640 .. 32385
    wire signed [19:0] prod_ext = {{3{prod[16]}}, prod};

    // ---------------- Akumulator 20-bit ----------------
    // 1st MAC cycle (m=n=0) load direct product
    // result Y[i,j] stored in acc WRITE_OUT & DONE.
    wire first = (m == 2'd0) && (n == 2'd0);
    reg signed [19:0] acc;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)       acc <= 20'sd0;
        else if (mac_en)  acc <= first ? prod_ext : (acc + prod_ext);
    end

    assign acc_out = acc;

endmodule