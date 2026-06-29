module core (
    input              i_clk,
    input              i_rst_n,
    input              i_in_valid,
    input      [31:0]  i_in_data,
    input              i_stride_mode,
    input      [71:0]  i_weight,

    output reg         o_in_ready,

    output reg [7:0]   o_out_data1,
    output reg [7:0]   o_out_data2,
    output reg [7:0]   o_out_data3,
    output reg [7:0]   o_out_data4,

    output reg [11:0]  o_out_addr1,
    output reg [11:0]  o_out_addr2,
    output reg [11:0]  o_out_addr3,
    output reg [11:0]  o_out_addr4,

    output reg         o_out_valid1,
    output reg         o_out_valid2,
    output reg         o_out_valid3,
    output reg         o_out_valid4,

    output reg         o_exe_finish
);

// ============================================================
// Streaming line-buffer version
// ------------------------------------------------------------
// Important design choice:
// The testbench sends the whole image continuously after the
// one-cycle gap. Therefore this design keeps o_in_ready high
// during the whole image input phase and computes outputs in
// parallel with input reception.
//
// This version uses a 4-row rolling line buffer instead of 3 rows.
// Reason: while computing row r, the circuit is already receiving
// row r+2. The fourth row prevents the new input row from overwriting
// the top row still needed by the current 3x3 window.
// This is still a line-buffer design, not full 64x64 image storage.
// ============================================================

localparam S_IDLE   = 3'd0;
localparam S_GET_W  = 3'd1;
localparam S_GAP    = 3'd2;
localparam S_STREAM = 3'd3;
localparam S_FLUSH  = 3'd4;
localparam S_DRAIN  = 3'd5;
localparam S_FINISH = 3'd6;

reg [2:0] state;

// 3x3 kernel, Q0.7 signed fixed-point
reg signed [7:0] w0, w1, w2;
reg signed [7:0] w3, w4, w5;
reg signed [7:0] w6, w7, w8;
reg stride_reg;

// 4-row rolling line buffer
reg [7:0] line0 [0:63];
reg [7:0] line1 [0:63];
reg [7:0] line2 [0:63];
reg [7:0] line3 [0:63];

// input stream counters
reg [6:0] read_row;   // 0..63
reg [3:0] read_grp;   // 0..15, each group contains 4 pixels

// flush counters for the last rows after input ends
reg [5:0] flush_out_r;
reg [3:0] flush_grp;
reg [3:0] drain_count;

// Front-end pipeline before cube-root.
reg        mac_valid;
reg signed [19:0] mac_prod0 [0:8], mac_prod1 [0:8], mac_prod2 [0:8], mac_prod3 [0:8];
reg [11:0] mac_addr0, mac_addr1, mac_addr2, mac_addr3;

reg        sum_valid;
reg signed [19:0] sum_a0, sum_b0, sum_c0;
reg signed [19:0] sum_a1, sum_b1, sum_c1;
reg signed [19:0] sum_a2, sum_b2, sum_c2;
reg signed [19:0] sum_a3, sum_b3, sum_c3;
reg [11:0] sum_addr0, sum_addr1, sum_addr2, sum_addr3;

reg        clamp_valid;
reg [7:0]  clamp0, clamp1, clamp2, clamp3;
reg [11:0] clamp_addr0, clamp_addr1, clamp_addr2, clamp_addr3;

reg        square_valid;
reg [15:0] square_target0, square_target1, square_target2, square_target3;
reg [11:0] square_addr0, square_addr1, square_addr2, square_addr3;

// 4-lane, 6-stage cube-root pipeline. Each group carries 4 output pixels.
reg        pipe_valid [0:5];
reg [15:0] pipe_target0 [0:5], pipe_target1 [0:5], pipe_target2 [0:5], pipe_target3 [0:5];
reg [5:0]  pipe_lo0 [0:5], pipe_lo1 [0:5], pipe_lo2 [0:5], pipe_lo3 [0:5];
reg [5:0]  pipe_hi0 [0:5], pipe_hi1 [0:5], pipe_hi2 [0:5], pipe_hi3 [0:5];
reg [11:0] pipe_addr0 [0:5], pipe_addr1 [0:5], pipe_addr2 [0:5], pipe_addr3 [0:5];

integer pi;

wire [5:0] in_col_base = {read_grp, 2'b00};

// ============================================================
// Read a buffered image pixel with zero-padding.
// rr/cc are signed because rr-1 or cc-1 may be negative.
// row buffer selection uses rr[1:0], equivalent to rr % 4.
// ============================================================
function [7:0] get_pixel;
    input signed [7:0] rr;
    input signed [7:0] cc;
    begin
        if (rr < 8'sd0 || rr > 8'sd63 || cc < 8'sd0 || cc > 8'sd63) begin
            get_pixel = 8'd0;
        end else begin
            case (rr[1:0])
                2'd0: get_pixel = line0[cc[5:0]];
                2'd1: get_pixel = line1[cc[5:0]];
                2'd2: get_pixel = line2[cc[5:0]];
                default: get_pixel = line3[cc[5:0]];
            endcase
        end
    end
endfunction

// ============================================================
// floor(cuberoot(target)) by binary search.
// target range is 0..255^2 = 65025, so answer range is 0..40.
// This is not a LUT; mid^3 is computed and compared each step.
// ============================================================
function [15:0] square_u8;
    input [7:0] x;
    begin
        square_u8 = {8'd0, x} * {8'd0, x};
    end
endfunction

function signed [19:0] mul_pixel_weight;
    input [7:0] p;
    input signed [7:0] w;
    reg signed [8:0] p_s;
    reg signed [16:0] prod;
    begin
        p_s = $signed({1'b0, p});
        prod = p_s * w;
        mul_pixel_weight = {{3{prod[16]}}, prod};
    end
endfunction

function [11:0] cube_next_pair;
    input [5:0] lo;
    input [5:0] hi;
    input [15:0] target;
    reg [6:0] mid_sum;
    reg [5:0] mid;
    reg [10:0] mid2;
    reg [15:0] mid3;
    begin
        mid_sum = {1'b0, lo} + {1'b0, hi} + 7'd1;
        mid = mid_sum[6:1];
        mid2 = {5'd0, mid} * {5'd0, mid};
        mid3 = {5'd0, mid2} * {10'd0, mid};
        cube_next_pair = (mid3 <= target) ? {hi, mid} : {(mid - 6'd1), lo};
    end
endfunction

function [11:0] make_addr;
    input [5:0] out_r;
    input [5:0] out_c;
    begin
        if (stride_reg)
            make_addr = {1'b0, out_r[4:0], 5'b0} + out_c;  // out_r*32 + out_c
        else
            make_addr = {out_r, 6'b0} + out_c;             // out_r*64 + out_c
    end
endfunction

function [6:0] row_minus_2;
    input [6:0] r;
    begin
        row_minus_2 = r - 7'd2;
    end
endfunction

function [5:0] row_minus_2_low6;
    input [6:0] r;
    reg [6:0] tmp;
    begin
        tmp = r - 7'd2;
        row_minus_2_low6 = tmp[5:0];
    end
endfunction

function [5:0] row_minus_2_div2;
    input [6:0] r;
    reg [6:0] tmp;
    begin
        tmp = r - 7'd2;
        row_minus_2_div2 = tmp[6:1];
    end
endfunction

// ============================================================
// Calculate one product in the 3x3 convolution window.
// center_r/center_c are coordinates in the original 64x64 image.
// ============================================================
function signed [19:0] calc_product;
    input [6:0] center_r;
    input [6:0] center_c;
    input [3:0] tap;
    reg signed [7:0] cr;
    reg signed [7:0] cc;
    reg [7:0] p;
    reg signed [7:0] w;
    begin
        cr = $signed({1'b0, center_r});
        cc = $signed({1'b0, center_c});

        case (tap)
            4'd0: begin p = get_pixel(cr - 8'sd1, cc - 8'sd1); w = w0; end
            4'd1: begin p = get_pixel(cr - 8'sd1, cc          ); w = w1; end
            4'd2: begin p = get_pixel(cr - 8'sd1, cc + 8'sd1); w = w2; end
            4'd3: begin p = get_pixel(cr          , cc - 8'sd1); w = w3; end
            4'd4: begin p = get_pixel(cr          , cc          ); w = w4; end
            4'd5: begin p = get_pixel(cr          , cc + 8'sd1); w = w5; end
            4'd6: begin p = get_pixel(cr + 8'sd1, cc - 8'sd1); w = w6; end
            4'd7: begin p = get_pixel(cr + 8'sd1, cc          ); w = w7; end
            default: begin p = get_pixel(cr + 8'sd1, cc + 8'sd1); w = w8; end
        endcase

        calc_product = mul_pixel_weight(p, w);
    end
endfunction

function [7:0] clamp_acc;
    input signed [19:0] acc;
    reg signed [19:0] rounded;
    begin
        // Q0.7 -> integer. Add 0.5 LSB and arithmetic shift.
        // This implements nearest integer, ties toward positive infinity.
        rounded = (acc + 20'sd64) >>> 7;

        if (rounded < 20'sd0)
            clamp_acc = 8'd0;
        else if (rounded > 20'sd255)
            clamp_acc = 8'd255;
        else
            clamp_acc = rounded[7:0];
    end
endfunction

// ============================================================
// Push one group of 4 pixels into the MAC product stage.
// out_r/out_c_base are output-map coordinates.
// center_r is original-image center row.
// center_c is generated from out_c according to stride mode.
// ============================================================
task push_group;
    input [5:0] out_r;
    input [5:0] out_c_base;
    input [6:0] center_r;
    reg [6:0] c0, c1, c2, c3;
    begin
        if (stride_reg) begin
            c0 = {out_c_base, 1'b0};
            c1 = {out_c_base + 6'd1, 1'b0};
            c2 = {out_c_base + 6'd2, 1'b0};
            c3 = {out_c_base + 6'd3, 1'b0};
        end else begin
            c0 = {1'b0, out_c_base};
            c1 = {1'b0, out_c_base + 6'd1};
            c2 = {1'b0, out_c_base + 6'd2};
            c3 = {1'b0, out_c_base + 6'd3};
        end

        mac_valid <= 1'b1;
        mac_prod0[0] <= calc_product(center_r, c0, 4'd0);
        mac_prod0[1] <= calc_product(center_r, c0, 4'd1);
        mac_prod0[2] <= calc_product(center_r, c0, 4'd2);
        mac_prod0[3] <= calc_product(center_r, c0, 4'd3);
        mac_prod0[4] <= calc_product(center_r, c0, 4'd4);
        mac_prod0[5] <= calc_product(center_r, c0, 4'd5);
        mac_prod0[6] <= calc_product(center_r, c0, 4'd6);
        mac_prod0[7] <= calc_product(center_r, c0, 4'd7);
        mac_prod0[8] <= calc_product(center_r, c0, 4'd8);
        mac_prod1[0] <= calc_product(center_r, c1, 4'd0);
        mac_prod1[1] <= calc_product(center_r, c1, 4'd1);
        mac_prod1[2] <= calc_product(center_r, c1, 4'd2);
        mac_prod1[3] <= calc_product(center_r, c1, 4'd3);
        mac_prod1[4] <= calc_product(center_r, c1, 4'd4);
        mac_prod1[5] <= calc_product(center_r, c1, 4'd5);
        mac_prod1[6] <= calc_product(center_r, c1, 4'd6);
        mac_prod1[7] <= calc_product(center_r, c1, 4'd7);
        mac_prod1[8] <= calc_product(center_r, c1, 4'd8);
        mac_prod2[0] <= calc_product(center_r, c2, 4'd0);
        mac_prod2[1] <= calc_product(center_r, c2, 4'd1);
        mac_prod2[2] <= calc_product(center_r, c2, 4'd2);
        mac_prod2[3] <= calc_product(center_r, c2, 4'd3);
        mac_prod2[4] <= calc_product(center_r, c2, 4'd4);
        mac_prod2[5] <= calc_product(center_r, c2, 4'd5);
        mac_prod2[6] <= calc_product(center_r, c2, 4'd6);
        mac_prod2[7] <= calc_product(center_r, c2, 4'd7);
        mac_prod2[8] <= calc_product(center_r, c2, 4'd8);
        mac_prod3[0] <= calc_product(center_r, c3, 4'd0);
        mac_prod3[1] <= calc_product(center_r, c3, 4'd1);
        mac_prod3[2] <= calc_product(center_r, c3, 4'd2);
        mac_prod3[3] <= calc_product(center_r, c3, 4'd3);
        mac_prod3[4] <= calc_product(center_r, c3, 4'd4);
        mac_prod3[5] <= calc_product(center_r, c3, 4'd5);
        mac_prod3[6] <= calc_product(center_r, c3, 4'd6);
        mac_prod3[7] <= calc_product(center_r, c3, 4'd7);
        mac_prod3[8] <= calc_product(center_r, c3, 4'd8);
        mac_addr0 <= make_addr(out_r, out_c_base);
        mac_addr1 <= make_addr(out_r, out_c_base + 6'd1);
        mac_addr2 <= make_addr(out_r, out_c_base + 6'd2);
        mac_addr3 <= make_addr(out_r, out_c_base + 6'd3);
    end
endtask

// ============================================================
// Write current 4 input pixels into the rolling row buffer.
// ============================================================
task write_input_group;
    begin
        case (read_row[1:0])
            2'd0: begin
                line0[in_col_base    ] <= i_in_data[31:24];
                line0[in_col_base + 6'd1] <= i_in_data[23:16];
                line0[in_col_base + 6'd2] <= i_in_data[15:8];
                line0[in_col_base + 6'd3] <= i_in_data[7:0];
            end
            2'd1: begin
                line1[in_col_base    ] <= i_in_data[31:24];
                line1[in_col_base + 6'd1] <= i_in_data[23:16];
                line1[in_col_base + 6'd2] <= i_in_data[15:8];
                line1[in_col_base + 6'd3] <= i_in_data[7:0];
            end
            2'd2: begin
                line2[in_col_base    ] <= i_in_data[31:24];
                line2[in_col_base + 6'd1] <= i_in_data[23:16];
                line2[in_col_base + 6'd2] <= i_in_data[15:8];
                line2[in_col_base + 6'd3] <= i_in_data[7:0];
            end
            default: begin
                line3[in_col_base    ] <= i_in_data[31:24];
                line3[in_col_base + 6'd1] <= i_in_data[23:16];
                line3[in_col_base + 6'd2] <= i_in_data[15:8];
                line3[in_col_base + 6'd3] <= i_in_data[7:0];
            end
        endcase
    end
endtask

// ============================================================
// Main FSM
// ============================================================
always @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        state <= S_IDLE;

        o_in_ready <= 1'b0;
        o_out_valid1 <= 1'b0;
        o_out_valid2 <= 1'b0;
        o_out_valid3 <= 1'b0;
        o_out_valid4 <= 1'b0;
        o_exe_finish <= 1'b0;

        read_row <= 7'd0;
        read_grp <= 4'd0;
        flush_out_r <= 6'd0;
        flush_grp <= 4'd0;
        drain_count <= 4'd0;
        mac_valid <= 1'b0;
        sum_valid <= 1'b0;
        clamp_valid <= 1'b0;
        square_valid <= 1'b0;

        for (pi = 0; pi < 6; pi = pi + 1) begin
            pipe_valid[pi] <= 1'b0;
        end
    end else begin
        // default output behavior
        o_out_valid1 <= 1'b0;
        o_out_valid2 <= 1'b0;
        o_out_valid3 <= 1'b0;
        o_out_valid4 <= 1'b0;
        o_exe_finish <= 1'b0;

        if (pipe_valid[5]) begin
            o_out_data1  <= {2'b00, pipe_lo0[5]};
            o_out_data2  <= {2'b00, pipe_lo1[5]};
            o_out_data3  <= {2'b00, pipe_lo2[5]};
            o_out_data4  <= {2'b00, pipe_lo3[5]};
            o_out_addr1  <= pipe_addr0[5];
            o_out_addr2  <= pipe_addr1[5];
            o_out_addr3  <= pipe_addr2[5];
            o_out_addr4  <= pipe_addr3[5];
            o_out_valid1 <= 1'b1;
            o_out_valid2 <= 1'b1;
            o_out_valid3 <= 1'b1;
            o_out_valid4 <= 1'b1;
        end

        for (pi = 5; pi > 0; pi = pi - 1) begin
            pipe_valid[pi] <= pipe_valid[pi-1];
            pipe_target0[pi] <= pipe_target0[pi-1];
            pipe_target1[pi] <= pipe_target1[pi-1];
            pipe_target2[pi] <= pipe_target2[pi-1];
            pipe_target3[pi] <= pipe_target3[pi-1];
            {pipe_hi0[pi], pipe_lo0[pi]} <= cube_next_pair(pipe_lo0[pi-1], pipe_hi0[pi-1], pipe_target0[pi-1]);
            {pipe_hi1[pi], pipe_lo1[pi]} <= cube_next_pair(pipe_lo1[pi-1], pipe_hi1[pi-1], pipe_target1[pi-1]);
            {pipe_hi2[pi], pipe_lo2[pi]} <= cube_next_pair(pipe_lo2[pi-1], pipe_hi2[pi-1], pipe_target2[pi-1]);
            {pipe_hi3[pi], pipe_lo3[pi]} <= cube_next_pair(pipe_lo3[pi-1], pipe_hi3[pi-1], pipe_target3[pi-1]);
            pipe_addr0[pi] <= pipe_addr0[pi-1];
            pipe_addr1[pi] <= pipe_addr1[pi-1];
            pipe_addr2[pi] <= pipe_addr2[pi-1];
            pipe_addr3[pi] <= pipe_addr3[pi-1];
        end

        pipe_valid[0] <= 1'b0;
        mac_valid <= 1'b0;
        sum_valid <= 1'b0;
        clamp_valid <= 1'b0;
        square_valid <= 1'b0;

        if (square_valid) begin
            pipe_valid[0] <= 1'b1;
            pipe_target0[0] <= square_target0;
            pipe_target1[0] <= square_target1;
            pipe_target2[0] <= square_target2;
            pipe_target3[0] <= square_target3;
            {pipe_hi0[0], pipe_lo0[0]} <= cube_next_pair(6'd0, 6'd40, square_target0);
            {pipe_hi1[0], pipe_lo1[0]} <= cube_next_pair(6'd0, 6'd40, square_target1);
            {pipe_hi2[0], pipe_lo2[0]} <= cube_next_pair(6'd0, 6'd40, square_target2);
            {pipe_hi3[0], pipe_lo3[0]} <= cube_next_pair(6'd0, 6'd40, square_target3);
            pipe_addr0[0] <= square_addr0;
            pipe_addr1[0] <= square_addr1;
            pipe_addr2[0] <= square_addr2;
            pipe_addr3[0] <= square_addr3;
        end

        if (clamp_valid) begin
            square_valid <= 1'b1;
            square_target0 <= square_u8(clamp0);
            square_target1 <= square_u8(clamp1);
            square_target2 <= square_u8(clamp2);
            square_target3 <= square_u8(clamp3);
            square_addr0 <= clamp_addr0;
            square_addr1 <= clamp_addr1;
            square_addr2 <= clamp_addr2;
            square_addr3 <= clamp_addr3;
        end

        if (sum_valid) begin
            clamp_valid <= 1'b1;
            clamp0 <= clamp_acc(sum_a0 + sum_b0 + sum_c0);
            clamp1 <= clamp_acc(sum_a1 + sum_b1 + sum_c1);
            clamp2 <= clamp_acc(sum_a2 + sum_b2 + sum_c2);
            clamp3 <= clamp_acc(sum_a3 + sum_b3 + sum_c3);
            clamp_addr0 <= sum_addr0;
            clamp_addr1 <= sum_addr1;
            clamp_addr2 <= sum_addr2;
            clamp_addr3 <= sum_addr3;
        end

        if (mac_valid) begin
            sum_valid <= 1'b1;
            sum_a0 <= mac_prod0[0] + mac_prod0[1] + mac_prod0[2];
            sum_b0 <= mac_prod0[3] + mac_prod0[4] + mac_prod0[5];
            sum_c0 <= mac_prod0[6] + mac_prod0[7] + mac_prod0[8];
            sum_a1 <= mac_prod1[0] + mac_prod1[1] + mac_prod1[2];
            sum_b1 <= mac_prod1[3] + mac_prod1[4] + mac_prod1[5];
            sum_c1 <= mac_prod1[6] + mac_prod1[7] + mac_prod1[8];
            sum_a2 <= mac_prod2[0] + mac_prod2[1] + mac_prod2[2];
            sum_b2 <= mac_prod2[3] + mac_prod2[4] + mac_prod2[5];
            sum_c2 <= mac_prod2[6] + mac_prod2[7] + mac_prod2[8];
            sum_a3 <= mac_prod3[0] + mac_prod3[1] + mac_prod3[2];
            sum_b3 <= mac_prod3[3] + mac_prod3[4] + mac_prod3[5];
            sum_c3 <= mac_prod3[6] + mac_prod3[7] + mac_prod3[8];
            sum_addr0 <= mac_addr0;
            sum_addr1 <= mac_addr1;
            sum_addr2 <= mac_addr2;
            sum_addr3 <= mac_addr3;
        end

        case (state)
            // ------------------------------------------------------------
            // Raise ready so testbench can send weight on the next negedge.
            // ------------------------------------------------------------
            S_IDLE: begin
                o_in_ready <= 1'b1;
                state <= S_GET_W;
            end

            // ------------------------------------------------------------
            // Capture weight on the posedge after the testbench drives it.
            // ------------------------------------------------------------
            S_GET_W: begin
                o_in_ready <= 1'b0;
                w0 <= i_weight[71:64];
                w1 <= i_weight[63:56];
                w2 <= i_weight[55:48];
                w3 <= i_weight[47:40];
                w4 <= i_weight[39:32];
                w5 <= i_weight[31:24];
                w6 <= i_weight[23:16];
                w7 <= i_weight[15:8];
                w8 <= i_weight[7:0];
                stride_reg <= i_stride_mode;
                state <= S_GAP;
            end

            // ------------------------------------------------------------
            // One-cycle gap before image stream.
            // ------------------------------------------------------------
            S_GAP: begin
                o_in_ready <= 1'b0;
                read_row <= 7'd0;
                read_grp <= 4'd0;
                drain_count <= 4'd0;
                mac_valid <= 1'b0;
                sum_valid <= 1'b0;
                clamp_valid <= 1'b0;
                square_valid <= 1'b0;
                state <= S_STREAM;
            end

            // ------------------------------------------------------------
            // Receive the whole image continuously.
            // At the same time, output already-computable rows.
            //
            // stride=1 schedule:
            //   while reading row 2, output row 0
            //   while reading row 3, output row 1
            //   ...
            //   while reading row 63, output row 61
            //   flush rows 62 and 63
            //
            // stride=2 schedule:
            //   while reading row 2, output center row 0  -> out row 0
            //   while reading row 4, output center row 2  -> out row 1
            //   ...
            //   while reading row 62, output center row 60 -> out row 30
            //   flush center row 62 -> out row 31
            // ------------------------------------------------------------
            S_STREAM: begin
                o_in_ready <= 1'b1;

                if (i_in_valid) begin
                    write_input_group();

                    if (!stride_reg) begin
                        // stride = 1, 64 outputs per row, 16 groups per row
                        if (read_row >= 7'd2) begin
                            push_group(
                                row_minus_2_low6(read_row),
                                {read_grp, 2'b00},
                                row_minus_2(read_row)
                            );
                        end
                    end else begin
                        // stride = 2, 32 outputs per row, 8 groups per output row
                        if ((read_row >= 7'd2) && (read_row[0] == 1'b0) && (read_grp <= 4'd7)) begin
                            push_group(
                                row_minus_2_div2(read_row),
                                {1'b0, read_grp[2:0], 2'b00},
                                row_minus_2(read_row)
                            );
                        end
                    end

                    if (read_grp == 4'd15) begin
                        read_grp <= 4'd0;
                        if (read_row == 7'd63) begin
                            o_in_ready <= 1'b0;
                            flush_grp <= 4'd0;
                            if (stride_reg)
                                flush_out_r <= 6'd31;
                            else
                                flush_out_r <= 6'd62;
                            state <= S_FLUSH;
                        end else begin
                            read_row <= read_row + 7'd1;
                        end
                    end else begin
                        read_grp <= read_grp + 4'd1;
                    end
                end
            end

            // ------------------------------------------------------------
            // Flush last output row(s) after all input rows are received.
            // ------------------------------------------------------------
            S_FLUSH: begin
                o_in_ready <= 1'b0;

                if (!stride_reg) begin
                    // stride=1: flush output rows 62 and 63, 16 groups each
                    push_group(
                        flush_out_r,
                        {flush_grp, 2'b00},
                        {1'b0, flush_out_r}
                    );

                    if (flush_grp == 4'd15) begin
                        flush_grp <= 4'd0;
                        if (flush_out_r == 6'd62) begin
                            flush_out_r <= 6'd63;
                        end else begin
                            drain_count <= 4'd0;
                            state <= S_DRAIN;
                        end
                    end else begin
                        flush_grp <= flush_grp + 4'd1;
                    end
                end else begin
                    // stride=2: flush only output row 31, center row 62, 8 groups
                    push_group(
                        6'd31,
                        {1'b0, flush_grp[2:0], 2'b00},
                        7'd62
                    );

                    if (flush_grp == 4'd7) begin
                        flush_grp <= 4'd0;
                        drain_count <= 4'd0;
                        state <= S_DRAIN;
                    end else begin
                        flush_grp <= flush_grp + 4'd1;
                    end
                end
            end

            // ------------------------------------------------------------
            // Let conv/square plus the 6-stage cube pipeline emit the last group.
            // ------------------------------------------------------------
            S_DRAIN: begin
                o_in_ready <= 1'b0;
                if (drain_count == 4'd9) begin
                    state <= S_FINISH;
                end else begin
                    drain_count <= drain_count + 4'd1;
                end
            end

            // ------------------------------------------------------------
            // Tell testbench all outputs have been written.
            // ------------------------------------------------------------
            S_FINISH: begin
                o_in_ready <= 1'b0;
                o_exe_finish <= 1'b1;
                state <= S_FINISH;
            end

            default: begin
                state <= S_IDLE;
            end
        endcase
    end
end

endmodule
