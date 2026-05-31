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
localparam S_FINISH = 3'd5;

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

integer i;

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
        if (rr < 0 || rr > 63 || cc < 0 || cc > 63) begin
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
function [7:0] cube_root_floor;
    input [15:0] target;
    reg [5:0] lo;
    reg [5:0] hi;
    reg [5:0] mid;
    reg [17:0] mid3;
    integer k;
    begin
        lo = 6'd0;
        hi = 6'd40;
        for (k = 0; k < 6; k = k + 1) begin
            mid  = (lo + hi + 6'd1) >> 1;
            mid3 = mid * mid * mid;
            if (mid3 <= target)
                lo = mid;
            else
                hi = mid - 6'd1;
        end
        cube_root_floor = {2'b00, lo};
    end
endfunction

function [7:0] activate_x_2_over_3;
    input [7:0] x;
    reg [15:0] sq;
    begin
        // Important: square first, then cube-root, then truncate.
        sq = x * x;
        activate_x_2_over_3 = cube_root_floor(sq);
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
// Calculate one output pixel.
// center_r/center_c are coordinates in the original 64x64 image.
// ============================================================
function [7:0] calc_one;
    input [6:0] center_r;
    input [6:0] center_c;
    reg signed [7:0] cr;
    reg signed [7:0] cc;
    reg [7:0] p0, p1, p2;
    reg [7:0] p3, p4, p5;
    reg [7:0] p6, p7, p8;
    reg signed [21:0] acc;
    reg signed [21:0] rounded;
    reg [7:0] clamped;
    begin
        cr = {1'b0, center_r};
        cc = {1'b0, center_c};

        p0 = get_pixel(cr - 8'sd1, cc - 8'sd1);
        p1 = get_pixel(cr - 8'sd1, cc          );
        p2 = get_pixel(cr - 8'sd1, cc + 8'sd1);
        p3 = get_pixel(cr          , cc - 8'sd1);
        p4 = get_pixel(cr          , cc          );
        p5 = get_pixel(cr          , cc + 8'sd1);
        p6 = get_pixel(cr + 8'sd1, cc - 8'sd1);
        p7 = get_pixel(cr + 8'sd1, cc          );
        p8 = get_pixel(cr + 8'sd1, cc + 8'sd1);

        acc = 22'sd0;
        acc = acc + ($signed({1'b0, p0}) * w0);
        acc = acc + ($signed({1'b0, p1}) * w1);
        acc = acc + ($signed({1'b0, p2}) * w2);
        acc = acc + ($signed({1'b0, p3}) * w3);
        acc = acc + ($signed({1'b0, p4}) * w4);
        acc = acc + ($signed({1'b0, p5}) * w5);
        acc = acc + ($signed({1'b0, p6}) * w6);
        acc = acc + ($signed({1'b0, p7}) * w7);
        acc = acc + ($signed({1'b0, p8}) * w8);

        // Q0.7 -> integer. Add 0.5 LSB and arithmetic shift.
        // This implements nearest integer, ties toward positive infinity.
        rounded = (acc + 22'sd64) >>> 7;

        if (rounded < 0)
            clamped = 8'd0;
        else if (rounded > 22'sd255)
            clamped = 8'd255;
        else
            clamped = rounded[7:0];

        calc_one = activate_x_2_over_3(clamped);
    end
endfunction

// ============================================================
// Output one group of 4 pixels.
// out_r/out_c_base are output-map coordinates.
// center_r is original-image center row.
// center_c is generated from out_c according to stride mode.
// ============================================================
task emit_group;
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

        o_out_data1  <= calc_one(center_r, c0);
        o_out_data2  <= calc_one(center_r, c1);
        o_out_data3  <= calc_one(center_r, c2);
        o_out_data4  <= calc_one(center_r, c3);

        o_out_addr1  <= make_addr(out_r, out_c_base);
        o_out_addr2  <= make_addr(out_r, out_c_base + 6'd1);
        o_out_addr3  <= make_addr(out_r, out_c_base + 6'd2);
        o_out_addr4  <= make_addr(out_r, out_c_base + 6'd3);

        o_out_valid1 <= 1'b1;
        o_out_valid2 <= 1'b1;
        o_out_valid3 <= 1'b1;
        o_out_valid4 <= 1'b1;
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
        o_out_data1 <= 8'd0;
        o_out_data2 <= 8'd0;
        o_out_data3 <= 8'd0;
        o_out_data4 <= 8'd0;
        o_out_addr1 <= 12'd0;
        o_out_addr2 <= 12'd0;
        o_out_addr3 <= 12'd0;
        o_out_addr4 <= 12'd0;
        o_out_valid1 <= 1'b0;
        o_out_valid2 <= 1'b0;
        o_out_valid3 <= 1'b0;
        o_out_valid4 <= 1'b0;
        o_exe_finish <= 1'b0;

        w0 <= 8'sd0; w1 <= 8'sd0; w2 <= 8'sd0;
        w3 <= 8'sd0; w4 <= 8'sd0; w5 <= 8'sd0;
        w6 <= 8'sd0; w7 <= 8'sd0; w8 <= 8'sd0;
        stride_reg <= 1'b0;

        read_row <= 7'd0;
        read_grp <= 4'd0;
        flush_out_r <= 6'd0;
        flush_grp <= 4'd0;

        for (i = 0; i < 64; i = i + 1) begin
            line0[i] <= 8'd0;
            line1[i] <= 8'd0;
            line2[i] <= 8'd0;
            line3[i] <= 8'd0;
        end
    end else begin
        // default output behavior
        o_out_valid1 <= 1'b0;
        o_out_valid2 <= 1'b0;
        o_out_valid3 <= 1'b0;
        o_out_valid4 <= 1'b0;
        o_exe_finish <= 1'b0;

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
                            emit_group(
                                row_minus_2_low6(read_row),
                                {read_grp, 2'b00},
                                row_minus_2(read_row)
                            );
                        end
                    end else begin
                        // stride = 2, 32 outputs per row, 8 groups per output row
                        if ((read_row >= 7'd2) && (read_row[0] == 1'b0) && (read_grp <= 4'd7)) begin
                            emit_group(
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
                    emit_group(
                        flush_out_r,
                        {flush_grp, 2'b00},
                        {1'b0, flush_out_r}
                    );

                    if (flush_grp == 4'd15) begin
                        flush_grp <= 4'd0;
                        if (flush_out_r == 6'd62) begin
                            flush_out_r <= 6'd63;
                        end else begin
                            state <= S_FINISH;
                        end
                    end else begin
                        flush_grp <= flush_grp + 4'd1;
                    end
                end else begin
                    // stride=2: flush only output row 31, center row 62, 8 groups
                    emit_group(
                        6'd31,
                        {1'b0, flush_grp[2:0], 2'b00},
                        7'd62
                    );

                    if (flush_grp == 4'd7) begin
                        flush_grp <= 4'd0;
                        state <= S_FINISH;
                    end else begin
                        flush_grp <= flush_grp + 4'd1;
                    end
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
