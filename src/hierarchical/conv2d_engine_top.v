`timescale 1ns/1ps

module conv2d_engine_top (
    input  wire               clk,
    input  wire               rst_n,      // asynchronous reset, active low
    input  wire               start,
    input  wire               in_valid,
    input  wire        [7:0]  data_X,     // unsigned pixel
    input  wire        [7:0]  data_K,     // signed 2's complement weight
    output wire               out_valid,
    output wire signed [19:0] data_Y,
    output wire               done
);

    // kontrol signal (FSM -> datapath)
    wire ld_en;       // write data_X/data_K to register file
    wire ld_clr;      // reset load
    wire mac_en;      // 1 MAC cycle + shift index (m,n)
    wire out_adv;     // shift out index (i,j)

    // status (datapath -> FSM)
    wire load_last;   //  load = 24
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