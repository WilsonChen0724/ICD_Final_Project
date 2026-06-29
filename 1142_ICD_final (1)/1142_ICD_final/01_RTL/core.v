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
// 3-line row-at-a-time line-buffer version.
// The design reads only the rows needed for the current output row,
// pulls o_in_ready low while calculating that row, then reads the next
// source row. This avoids the fourth line buffer used by the streaming
// implementation.
// ============================================================

localparam S_IDLE   = 3'd0;
localparam S_GET_W  = 3'd1;
localparam S_GAP    = 3'd2;
localparam S_DECIDE = 3'd3;
localparam S_READ   = 3'd4;
localparam S_CALC   = 3'd5;
localparam S_FINISH = 3'd6;

reg [2:0] state;

// 3x3 kernel, Q0.7 signed fixed-point
reg signed [7:0] w0, w1, w2;
reg signed [7:0] w3, w4, w5;
reg signed [7:0] w6, w7, w8;
reg stride_reg;

// 3-row rolling line buffer
reg [7:0] line0 [0:63];
reg [7:0] line1 [0:63];
reg [7:0] line2 [0:63];

// input stream counters
reg [6:0] loaded_count;   // number of source rows already loaded
reg [1:0] read_row_mod;   // read_row % 3
reg [3:0] read_grp;       // 0..15, each group contains 4 pixels

// output-row counters
reg [5:0] out_row;
reg [3:0] out_grp;
reg [1:0] center_row_mod;

integer i;

wire [5:0] in_col_base = {read_grp, 2'b00};
wire [5:0] last_out_row = stride_reg ? 6'd31 : 6'd63;
wire [3:0] last_out_grp = stride_reg ? 4'd7 : 4'd15;
wire [6:0] center_row = stride_reg ? {out_row, 1'b0} : {1'b0, out_row};
wire [6:0] required_bottom_row = center_row + 7'd1;
wire need_read_more = (required_bottom_row <= 7'd63) &&
                      (loaded_count <= required_bottom_row);

// ============================================================
// Read a buffered image pixel with zero-padding.
// row_sel is tracked by counters to avoid synthesizing modulo logic.
// ============================================================
function [7:0] read_line;
    input [1:0] row_sel;
    input [5:0] col;
    begin
        if (row_sel == 2'd0)
            read_line = line0[col];
        else if (row_sel == 2'd1)
            read_line = line1[col];
        else
            read_line = line2[col];
    end
endfunction

function [7:0] get_pixel_sel;
    input zero_row;
    input [1:0] row_sel;
    input signed [7:0] cc;
    begin
        if (zero_row || cc < 0 || cc > 63) begin
            get_pixel_sel = 8'd0;
        end else begin
            get_pixel_sel = read_line(row_sel, cc[5:0]);
        end
    end
endfunction

function [1:0] mod3_plus1;
    input [1:0] x;
    begin
        if (x == 2'd2)
            mod3_plus1 = 2'd0;
        else
            mod3_plus1 = x + 2'd1;
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
    reg [6:0] mid_sum;
    reg [11:0] mid2;
    reg [17:0] mid3;
    integer k;
    begin
        lo = 6'd0;
        hi = 6'd40;
        for (k = 0; k < 6; k = k + 1) begin
            mid_sum = {1'b0, lo} + {1'b0, hi} + 7'd1;
            mid = mid_sum[6:1];
            mid2 = {6'd0, mid} * {6'd0, mid};
            mid3 = {6'd0, mid2} * {12'd0, mid};

            if (mid3 <= target)
                lo = mid;
            else
                hi = mid - 6'd1;
        end
        cube_root_floor = {2'b00, lo};
    end
endfunction

function [15:0] square_u8;
    input [7:0] x;
    begin
        square_u8 = {8'd0, x} * {8'd0, x};
    end
endfunction

function [7:0] activate_x_2_over_3;
    input [7:0] x;
    reg [15:0] sq;
    begin
        // Important: square first, then cube-root, then truncate.
        sq = square_u8(x);
        activate_x_2_over_3 = cube_root_floor(sq);
    end
endfunction

function signed [21:0] mul_pixel_weight;
    input [7:0] p;
    input signed [7:0] w;
    reg signed [16:0] prod;
    begin
        prod = $signed({1'b0, p}) * w;
        mul_pixel_weight = {{5{prod[16]}}, prod};
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

// ============================================================
// Calculate one output pixel.
// center_r/center_c are coordinates in the original 64x64 image.
// ============================================================
function [7:0] calc_one;
    input [6:0] center_r;
    input [6:0] center_c;
    reg signed [7:0] cr;
    reg signed [7:0] cc;
    reg [1:0] top_sel;
    reg [1:0] mid_sel;
    reg [1:0] bot_sel;
    reg top_zero;
    reg bot_zero;
    reg [7:0] p0, p1, p2;
    reg [7:0] p3, p4, p5;
    reg [7:0] p6, p7, p8;
    reg signed [21:0] acc;
    reg signed [21:0] rounded;
    reg [7:0] clamped;
    reg [7:0] activated;
    begin
        cr = {1'b0, center_r};
        cc = {1'b0, center_c};

        mid_sel = center_row_mod;
        top_sel = (center_row_mod == 2'd0) ? 2'd2 : (center_row_mod - 2'd1);
        bot_sel = (center_row_mod == 2'd2) ? 2'd0 : (center_row_mod + 2'd1);
        top_zero = (cr == 8'sd0);
        bot_zero = (cr == 8'sd63);

        p0 = get_pixel_sel(top_zero, top_sel, cc - 8'sd1);
        p1 = get_pixel_sel(top_zero, top_sel, cc          );
        p2 = get_pixel_sel(top_zero, top_sel, cc + 8'sd1);
        p3 = get_pixel_sel(1'b0,     mid_sel, cc - 8'sd1);
        p4 = get_pixel_sel(1'b0,     mid_sel, cc          );
        p5 = get_pixel_sel(1'b0,     mid_sel, cc + 8'sd1);
        p6 = get_pixel_sel(bot_zero, bot_sel, cc - 8'sd1);
        p7 = get_pixel_sel(bot_zero, bot_sel, cc          );
        p8 = get_pixel_sel(bot_zero, bot_sel, cc + 8'sd1);

        acc = 22'sd0;
        acc = acc + mul_pixel_weight(p0, w0);
        acc = acc + mul_pixel_weight(p1, w1);
        acc = acc + mul_pixel_weight(p2, w2);
        acc = acc + mul_pixel_weight(p3, w3);
        acc = acc + mul_pixel_weight(p4, w4);
        acc = acc + mul_pixel_weight(p5, w5);
        acc = acc + mul_pixel_weight(p6, w6);
        acc = acc + mul_pixel_weight(p7, w7);
        acc = acc + mul_pixel_weight(p8, w8);

        // Q0.7 -> integer. Add 0.5 LSB and arithmetic shift.
        // This implements nearest integer, ties toward positive infinity.
        rounded = (acc + 22'sd64) >>> 7;

        if (rounded < 0)
            clamped = 8'd0;
        else if (rounded > 22'sd255)
            clamped = 8'd255;
        else
            clamped = rounded[7:0];

        activated = activate_x_2_over_3(clamped);

        calc_one = activated;
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
    reg [7:0] d0, d1, d2, d3;
    reg [11:0] a0, a1, a2, a3;
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

        d0 = calc_one(center_r, c0);
        d1 = calc_one(center_r, c1);
        d2 = calc_one(center_r, c2);
        d3 = calc_one(center_r, c3);

        a0 = make_addr(out_r, out_c_base);
        a1 = make_addr(out_r, out_c_base + 6'd1);
        a2 = make_addr(out_r, out_c_base + 6'd2);
        a3 = make_addr(out_r, out_c_base + 6'd3);

        o_out_data1  <= d0;
        o_out_data2  <= d1;
        o_out_data3  <= d2;
        o_out_data4  <= d3;

        o_out_addr1  <= a0;
        o_out_addr2  <= a1;
        o_out_addr3  <= a2;
        o_out_addr4  <= a3;

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
        case (read_row_mod)
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

        loaded_count <= 7'd0;
        read_row_mod <= 2'd0;
        read_grp <= 4'd0;
        out_row <= 6'd0;
        out_grp <= 4'd0;
        center_row_mod <= 2'd0;

        for (i = 0; i < 64; i = i + 1) begin
            line0[i] <= 8'd0;
            line1[i] <= 8'd0;
            line2[i] <= 8'd0;
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
                loaded_count <= 7'd0;
                read_row_mod <= 2'd0;
                read_grp <= 4'd0;
                out_row <= 6'd0;
                out_grp <= 4'd0;
                center_row_mod <= 2'd0;
                state <= S_DECIDE;
            end

            // ------------------------------------------------------------
            // Read rows only when the current 3x3 window needs one more
            // source row. Otherwise calculate one output row with ready low.
            // ------------------------------------------------------------
            S_DECIDE: begin
                if (need_read_more) begin
                    o_in_ready <= 1'b1;
                    read_grp <= 4'd0;
                    state <= S_READ;
                end else begin
                    o_in_ready <= 1'b0;
                    out_grp <= 4'd0;
                    state <= S_CALC;
                end
            end

            // ------------------------------------------------------------
            // Read exactly one 64-pixel source row, 4 pixels per cycle.
            // ------------------------------------------------------------
            S_READ: begin
                o_in_ready <= 1'b1;

                if (i_in_valid) begin
                    write_input_group();

                    if (read_grp == 4'd15) begin
                        read_grp <= 4'd0;
                        loaded_count <= loaded_count + 7'd1;
                        read_row_mod <= mod3_plus1(read_row_mod);
                        o_in_ready <= 1'b0;
                        state <= S_DECIDE;
                    end else begin
                        read_grp <= read_grp + 4'd1;
                    end
                end
            end

            // ------------------------------------------------------------
            // Calculate one output row. Each cycle emits 4 output pixels.
            // ------------------------------------------------------------
            S_CALC: begin
                o_in_ready <= 1'b0;

                if (!stride_reg) begin
                    emit_group(out_row, {out_grp, 2'b00}, center_row);
                end else begin
                    emit_group(out_row, {1'b0, out_grp[2:0], 2'b00}, center_row);
                end

                if (out_grp == last_out_grp) begin
                    out_grp <= 4'd0;
                    if (out_row == last_out_row) begin
                        state <= S_FINISH;
                    end else begin
                        out_row <= out_row + 6'd1;
                        if (stride_reg)
                            center_row_mod <= mod3_plus1(mod3_plus1(center_row_mod));
                        else
                            center_row_mod <= mod3_plus1(center_row_mod);
                        state <= S_DECIDE;
                    end
                end else begin
                    out_grp <= out_grp + 4'd1;
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
