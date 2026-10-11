// Control module to manage the flow of the 2D convolution process. 
// This module manages the states and control signals to load data, perform computations, write results, and signal process completion.
// Author: Andhika Narawangsa Susilo

`timescale 1ns/1ps

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

    // register state
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) state <= S_IDLE;
        else        state <= next_state;
    end

    // next-state logic
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

    // output logic
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