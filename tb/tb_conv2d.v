// =============================================================================
// File    : tb_conv2d.v
// Description:
//           Self-checking testbench for conv2d_engine (Verilog-2001).
//
// Test Scenarios:
//   Test 1 : Example test case from the assignment (sample X 5x5, simple vertical Sobel kernel)
//   Test 2 : All X = 255, all K = -128 -> Y = -293760 (worst-case negative)
//   Test 3 : All X = 255, all K = +127 -> Y = +291465 (worst-case positive)
//   Test 4 : All X = 0, random K          -> Y = 0
//   Test 5 : Asynchronous reset during LOAD, then repeat Test 1
//   Test 6+: 20 random test cases; every even-numbered case uses in_valid stalls
//
// Expected results are calculated inside the testbench using behavioral loops
// and compared against the DUT output on every out_valid pulse.
// The "RESULT test=.. i=.. j=.. Y=.." lines are used by
// scripts/golden_model.py --check.
// =============================================================================
`timescale 1ns/1ps

module tb_conv2d;

    // ---------------- DUT signals ----------------
    reg         clk      = 1'b0;
    reg         rst_n    = 1'b0;
    reg         start    = 1'b0;
    reg         in_valid = 1'b0;
    reg  [7:0]  data_X   = 8'd0;
    reg  [7:0]  data_K   = 8'd0;
    wire        out_valid;
    wire signed [19:0] data_Y;
    wire        done;

    conv2d_engine dut (
        .clk       (clk),
        .rst_n     (rst_n),
        .start     (start),
        .in_valid  (in_valid),
        .data_X    (data_X),
        .data_K    (data_K),
        .out_valid (out_valid),
        .data_Y    (data_Y),
        .done      (done)
    );

    // 100 MHz clock
    always #5 clk = ~clk;

    // ---------------- Stimulus and reference data ----------------
    reg  [7:0]         x_in  [0:24];
    reg  [7:0]         k_in  [0:8];
    reg  signed [19:0] exp_y [0:8];

    integer errors     = 0;
    integer test_id    = 0;
    integer out_cnt    = 0;
    integer seed       = 32'h1234_5678;
    integer t_start, t_done;
    integer k;

    // Calculate expected Y using signed integer arithmetic
    task compute_expected;
        integer ii, jj, mm, nn, xi, ki, acc;
        begin
            for (ii = 0; ii < 3; ii = ii + 1)
                for (jj = 0; jj < 3; jj = jj + 1) begin
                    acc = 0;
                    for (mm = 0; mm < 3; mm = mm + 1)
                        for (nn = 0; nn < 3; nn = nn + 1) begin
                            xi = x_in[(ii+mm)*5 + (jj+nn)];
                            ki = k_in[mm*3 + nn];
                            if (ki > 127) ki = ki - 256;     // Convert from 2's complement
                            acc = acc + xi * ki;
                        end
                    exp_y[ii*3 + jj] = acc;
                end
        end
    endtask

    // Send one data transfer (one clock cycle).
    // In stall mode, insert cycles with in_valid=0 and invalid data
    // that must be ignored by the DUT.
    task send_data;
        input integer idx;
        input integer stall_mode;
        begin
            if (stall_mode != 0 && ($random(seed) & 1)) begin
                in_valid = 1'b0;
                data_X   = $random(seed);
                data_K   = $random(seed);
                @(negedge clk);
            end
            in_valid = 1'b1;
            data_X   = x_in[idx];
            data_K   = (idx < 9) ? k_in[idx] : 8'd0;
            @(negedge clk);
        end
    endtask

    // Generate a one-clock-cycle start pulse
    task pulse_start;
        begin
            @(negedge clk);
            start   = 1'b1;
            t_start = $time;
            @(negedge clk);
            start   = 1'b0;
        end
    endtask

    // Complete test sequence: start -> load 25 transfers -> wait for done -> verify output count
    task run_test;
        input integer stall_mode;
        integer idx;
        begin
            test_id = test_id + 1;
            compute_expected;
            pulse_start;
            out_cnt = 0;      // The previous done signal goes low after start is accepted
            for (idx = 0; idx < 25; idx = idx + 1)
                send_data(idx, stall_mode);
            in_valid = 1'b0;
            data_X   = 8'd0;
            data_K   = 8'd0;
            wait (done === 1'b1);
            t_done = $time;
            @(negedge clk);
            if (out_cnt !== 9) begin
                errors = errors + 1;
                $display("FAIL test=%0d: out_valid count = %0d (expected 9)", test_id, out_cnt);
            end
            $display("INFO  test=%0d completed, start-to-done latency = %0d clock cycles", test_id,
                     (t_done - t_start) / 10);
        end
    endtask

    // ---------------- Output monitor (on every positive clock edge) ----------------
    reg prev_valid = 1'b0;

    always @(posedge clk) begin
        if (rst_n) begin
            if (out_valid) begin
                if (out_cnt < 9) begin
                    $display("RESULT test=%0d i=%0d j=%0d Y=%0d",
                             test_id, out_cnt / 3, out_cnt % 3, data_Y);
                    if (data_Y !== exp_y[out_cnt]) begin
                        errors = errors + 1;
                        $display("FAIL  test=%0d Y[%0d,%0d]: DUT=%0d, expected=%0d",
                                 test_id, out_cnt / 3, out_cnt % 3, data_Y, exp_y[out_cnt]);
                    end
                end else begin
                    errors = errors + 1;
                    $display("FAIL  test=%0d: unexpected extra out_valid pulse", test_id);
                end
                out_cnt = out_cnt + 1;
            end

            // out_valid must be a one-clock-cycle pulse (no consecutive high cycles)
            if (out_valid && prev_valid) begin
                errors = errors + 1;
                $display("FAIL  test=%0d: out_valid remained high for more than one clock cycle", test_id);
            end

            // done and out_valid must not be asserted simultaneously
            if (out_valid && done) begin
                errors = errors + 1;
                $display("FAIL  test=%0d: done and out_valid asserted simultaneously", test_id);
            end

            // done must not be asserted before all 9 outputs have been produced
            if (done && out_cnt != 9) begin
                errors = errors + 1;
                $display("FAIL  test=%0d: done asserted before all 9 outputs (out_cnt=%0d)", test_id, out_cnt);
            end

            prev_valid = out_valid;
        end else begin
            prev_valid = 1'b0;
        end
    end

    // ---------------- Helper tasks for initializing test vectors ----------------
    task load_example;     // Test case from the assignment
        begin
            // X matrix (row-major order)
            x_in[0]=1;  x_in[1]=2;  x_in[2]=0;  x_in[3]=1;  x_in[4]=3;
            x_in[5]=2;  x_in[6]=1;  x_in[7]=3;  x_in[8]=2;  x_in[9]=0;
            x_in[10]=0; x_in[11]=1; x_in[12]=2; x_in[13]=1; x_in[14]=1;
            x_in[15]=1; x_in[16]=3; x_in[17]=0; x_in[18]=2; x_in[19]=2;
            x_in[20]=2; x_in[21]=0; x_in[22]=1; x_in[23]=0; x_in[24]=1;

            // K = [1 0 -1; 1 0 -1; 1 0 -1]
            k_in[0]=8'h01; k_in[1]=8'h00; k_in[2]=8'hFF;
            k_in[3]=8'h01; k_in[4]=8'h00; k_in[5]=8'hFF;
            k_in[6]=8'h01; k_in[7]=8'h00; k_in[8]=8'hFF;
        end
    endtask

    task load_const;
        input [7:0] xv;
        input [7:0] kv;
        integer q;
        begin
            for (q = 0; q < 25; q = q + 1) x_in[q] = xv;
            for (q = 0; q < 9;  q = q + 1) k_in[q] = kv;
        end
    endtask

    task load_random;
        integer q;
        begin
            for (q = 0; q < 25; q = q + 1) x_in[q] = $random(seed);
            for (q = 0; q < 9;  q = q + 1) k_in[q] = $random(seed);
        end
    endtask

    // ---------------- Test sequence ----------------
    initial begin
        $dumpfile("sim/conv2d.vcd");
        $dumpvars(0, tb_conv2d);

        // Initial reset
        rst_n = 1'b0;
        repeat (3) @(negedge clk);
        rst_n = 1'b1;
        repeat (2) @(negedge clk);

        // Test 1: Example from the assignment
        load_example;
        run_test(0);

        // Test 2: Worst-case negative value
        load_const(8'd255, 8'h80);
        run_test(0);

        // Test 3: Worst-case positive value
        load_const(8'd255, 8'h7F);
        run_test(0);

        // Test 4: X = 0
        load_random;
        for (k = 0; k < 25; k = k + 1) x_in[k] = 8'd0;
        run_test(0);

        // Test 5: Asynchronous reset during LOAD, then rerun the example
        load_example;
        test_id = test_id + 1;
        compute_expected;
        pulse_start;
        out_cnt = 0;
        for (k = 0; k < 10; k = k + 1) send_data(k, 0);
        in_valid = 1'b0;
        #3 rst_n = 1'b0;                    // Asynchronous reset (not aligned with a clock edge)
        #1;
        if (done !== 1'b0 || out_valid !== 1'b0) begin
            errors = errors + 1;
            $display("FAIL  test=%0d: outputs are not low after reset", test_id);
        end
        repeat (3) @(negedge clk);
        rst_n = 1'b1;
        repeat (2) @(negedge clk);
        run_test(0);

        // Tests 6+: 20 random test cases (even-numbered cases use in_valid stalls)
        for (k = 0; k < 20; k = k + 1) begin
            load_random;
            run_test(k % 2);
        end

        repeat (5) @(negedge clk);
        if (errors == 0) $display("=== ALL TESTS PASSED (%0d tests) ===", test_id);
        else             $display("=== TEST FAILED: %0d error(s) ===", errors);
        $finish;
    end

    // Watchdog timer
    initial begin
        #5_000_000;
        $display("=== TIMEOUT ===");
        $finish;
    end

endmodule