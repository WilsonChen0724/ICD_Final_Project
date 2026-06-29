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
// Experimental 2-line-buffer + bottom sliding-window frontend.
// ------------------------------------------------------------
// This first-pass RTL targets stride=1 scheduling only. It keeps
// the known-good deep MAC/cube pipeline style so the experiment
// isolates the 2-line overwrite/window schedule.
// ============================================================

localparam S_IDLE       = 4'd0;
localparam S_GET_W      = 4'd1;
localparam S_LOAD0      = 4'd2;
localparam S_LOAD1      = 4'd3;
localparam S_PRE_ROW0   = 4'd4;
localparam S_STREAM     = 4'd5;
localparam S_ROW_FLUSH  = 4'd6;
localparam S_FINAL_ROW  = 4'd7;
localparam S_DRAIN      = 4'd8;
localparam S_FINISH     = 4'd9;

reg [3:0] state;

reg signed [7:0] w0, w1, w2;
reg signed [7:0] w3, w4, w5;
reg signed [7:0] w6, w7, w8;
reg stride_reg;

reg [7:0] line0 [0:63];
reg [7:0] line1 [0:63];

reg [6:0] read_row;
reg [3:0] read_grp;
reg [3:0] pre_grp;
reg [3:0] final_grp;
reg [1:0] flush_phase;
reg [3:0] drain_count;

reg top_sel;
reg mid_sel;
reg write_sel;

reg [31:0] prev2_grp;
reg [31:0] prev1_grp;

reg        mac_valid;
reg signed [19:0] mac_prod0 [0:8], mac_prod1 [0:8], mac_prod2 [0:8], mac_prod3 [0:8];
reg [11:0] mac_base_addr;

reg        sum_valid;
reg signed [19:0] sum_a0, sum_b0, sum_c0;
reg signed [19:0] sum_a1, sum_b1, sum_c1;
reg signed [19:0] sum_a2, sum_b2, sum_c2;
reg signed [19:0] sum_a3, sum_b3, sum_c3;
reg [11:0] sum_base_addr;

reg        clamp_valid;
reg [7:0]  clamp0, clamp1, clamp2, clamp3;
reg [11:0] clamp_base_addr;

reg        square_valid;
reg [15:0] square_target0, square_target1, square_target2, square_target3;
reg [11:0] square_base_addr;

reg        pipe_valid [0:5];
reg [15:0] pipe_target0 [0:5], pipe_target1 [0:5], pipe_target2 [0:5], pipe_target3 [0:5];
reg [5:0]  pipe_lo0 [0:5], pipe_lo1 [0:5], pipe_lo2 [0:5], pipe_lo3 [0:5];
reg [5:0]  pipe_hi0 [0:5], pipe_hi1 [0:5], pipe_hi2 [0:5], pipe_hi3 [0:5];
reg [11:0] pipe_base_addr [0:5];

integer pi;

wire [5:0] in_col_base = {read_grp, 2'b00};

function [7:0] line_pixel;
    input sel;
    input [5:0] cc;
    begin
        line_pixel = sel ? line1[cc] : line0[cc];
    end
endfunction

function [7:0] checked_line_pixel;
    input row_ok;
    input sel;
    input signed [7:0] cc;
    begin
        if (!row_ok || cc < 8'sd0 || cc > 8'sd63)
            checked_line_pixel = 8'd0;
        else
            checked_line_pixel = line_pixel(sel, cc[5:0]);
    end
endfunction

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

function [7:0] clamp_acc;
    input signed [19:0] acc;
    reg signed [19:0] rounded;
    begin
        rounded = (acc + 20'sd64) >>> 7;
        if (rounded < 20'sd0)
            clamp_acc = 8'd0;
        else if (rounded > 20'sd255)
            clamp_acc = 8'd255;
        else
            clamp_acc = rounded[7:0];
    end
endfunction

function [11:0] make_addr;
    input [5:0] out_r;
    input [5:0] out_c;
    begin
        if (stride_reg)
            make_addr = {1'b0, out_r[4:0], 5'b0} + out_c;
        else
            make_addr = {out_r, 6'b0} + out_c;
    end
endfunction

task write_group_to_line;
    input sel;
    input [5:0] col_base;
    input [31:0] data;
    begin
        if (sel) begin
            line1[col_base       ] <= data[31:24];
            line1[col_base + 6'd1] <= data[23:16];
            line1[col_base + 6'd2] <= data[15:8];
            line1[col_base + 6'd3] <= data[7:0];
        end else begin
            line0[col_base       ] <= data[31:24];
            line0[col_base + 6'd1] <= data[23:16];
            line0[col_base + 6'd2] <= data[15:8];
            line0[col_base + 6'd3] <= data[7:0];
        end
    end
endtask

task push_group_2line;
    input [5:0] out_r;
    input [5:0] out_c_base;
    input       top_row_ok;
    input       bottom_row_ok;
    input       t_sel;
    input       m_sel;
    input [7:0] b0;
    input [7:0] b1;
    input [7:0] b2;
    input [7:0] b3;
    input [7:0] b4;
    input [7:0] b5;
    reg signed [7:0] cc;
    reg [7:0] t0, t1, t2, t3, t4, t5;
    reg [7:0] m0, m1, m2, m3, m4, m5;
    reg [7:0] bb0, bb1, bb2, bb3, bb4, bb5;
    begin
        mac_valid <= 1'b1;
        mac_base_addr <= make_addr(out_r, out_c_base);

        cc = $signed({2'b00, out_c_base});
        t0 = checked_line_pixel(top_row_ok, t_sel, cc - 8'sd1);
        t1 = checked_line_pixel(top_row_ok, t_sel, cc);
        t2 = checked_line_pixel(top_row_ok, t_sel, cc + 8'sd1);
        t3 = checked_line_pixel(top_row_ok, t_sel, cc + 8'sd2);
        t4 = checked_line_pixel(top_row_ok, t_sel, cc + 8'sd3);
        t5 = checked_line_pixel(top_row_ok, t_sel, cc + 8'sd4);

        m0 = checked_line_pixel(1'b1, m_sel, cc - 8'sd1);
        m1 = checked_line_pixel(1'b1, m_sel, cc);
        m2 = checked_line_pixel(1'b1, m_sel, cc + 8'sd1);
        m3 = checked_line_pixel(1'b1, m_sel, cc + 8'sd2);
        m4 = checked_line_pixel(1'b1, m_sel, cc + 8'sd3);
        m5 = checked_line_pixel(1'b1, m_sel, cc + 8'sd4);

        bb0 = bottom_row_ok ? b0 : 8'd0;
        bb1 = bottom_row_ok ? b1 : 8'd0;
        bb2 = bottom_row_ok ? b2 : 8'd0;
        bb3 = bottom_row_ok ? b3 : 8'd0;
        bb4 = bottom_row_ok ? b4 : 8'd0;
        bb5 = bottom_row_ok ? b5 : 8'd0;

        mac_prod0[0] <= mul_pixel_weight(t0, w0);
        mac_prod0[1] <= mul_pixel_weight(t1, w1);
        mac_prod0[2] <= mul_pixel_weight(t2, w2);
        mac_prod0[3] <= mul_pixel_weight(m0, w3);
        mac_prod0[4] <= mul_pixel_weight(m1, w4);
        mac_prod0[5] <= mul_pixel_weight(m2, w5);
        mac_prod0[6] <= mul_pixel_weight(bb0, w6);
        mac_prod0[7] <= mul_pixel_weight(bb1, w7);
        mac_prod0[8] <= mul_pixel_weight(bb2, w8);

        mac_prod1[0] <= mul_pixel_weight(t1, w0);
        mac_prod1[1] <= mul_pixel_weight(t2, w1);
        mac_prod1[2] <= mul_pixel_weight(t3, w2);
        mac_prod1[3] <= mul_pixel_weight(m1, w3);
        mac_prod1[4] <= mul_pixel_weight(m2, w4);
        mac_prod1[5] <= mul_pixel_weight(m3, w5);
        mac_prod1[6] <= mul_pixel_weight(bb1, w6);
        mac_prod1[7] <= mul_pixel_weight(bb2, w7);
        mac_prod1[8] <= mul_pixel_weight(bb3, w8);

        mac_prod2[0] <= mul_pixel_weight(t2, w0);
        mac_prod2[1] <= mul_pixel_weight(t3, w1);
        mac_prod2[2] <= mul_pixel_weight(t4, w2);
        mac_prod2[3] <= mul_pixel_weight(m2, w3);
        mac_prod2[4] <= mul_pixel_weight(m3, w4);
        mac_prod2[5] <= mul_pixel_weight(m4, w5);
        mac_prod2[6] <= mul_pixel_weight(bb2, w6);
        mac_prod2[7] <= mul_pixel_weight(bb3, w7);
        mac_prod2[8] <= mul_pixel_weight(bb4, w8);

        mac_prod3[0] <= mul_pixel_weight(t3, w0);
        mac_prod3[1] <= mul_pixel_weight(t4, w1);
        mac_prod3[2] <= mul_pixel_weight(t5, w2);
        mac_prod3[3] <= mul_pixel_weight(m3, w3);
        mac_prod3[4] <= mul_pixel_weight(m4, w4);
        mac_prod3[5] <= mul_pixel_weight(m5, w5);
        mac_prod3[6] <= mul_pixel_weight(bb3, w6);
        mac_prod3[7] <= mul_pixel_weight(bb4, w7);
        mac_prod3[8] <= mul_pixel_weight(bb5, w8);
    end
endtask

task push_group_from_input_window;
    input [5:0] out_r;
    input [3:0] group_idx;
    input [31:0] older_group;
    input [31:0] center_group;
    input [31:0] newer_group;
    reg [7:0] w0b, w1b, w2b, w3b, w4b, w5b;
    begin
        w0b = (group_idx == 4'd0) ? 8'd0 : older_group[7:0];
        w1b = center_group[31:24];
        w2b = center_group[23:16];
        w3b = center_group[15:8];
        w4b = center_group[7:0];
        w5b = (group_idx == 4'd15) ? 8'd0 : newer_group[31:24];
        push_group_2line(out_r, {group_idx, 2'b00}, 1'b1, 1'b1, top_sel, mid_sel,
                         w0b, w1b, w2b, w3b, w4b, w5b);
    end
endtask

task push_group_from_line_bottom;
    input [5:0] out_r;
    input [3:0] group_idx;
    input       top_row_ok;
    input       bottom_row_ok;
    input       t_sel;
    input       m_sel;
    input       b_sel;
    reg signed [7:0] cc;
    begin
        cc = $signed({2'b00, {group_idx, 2'b00}});
        push_group_2line(out_r, {group_idx, 2'b00}, top_row_ok, bottom_row_ok, t_sel, m_sel,
                         checked_line_pixel(bottom_row_ok, b_sel, cc - 8'sd1),
                         checked_line_pixel(bottom_row_ok, b_sel, cc),
                         checked_line_pixel(bottom_row_ok, b_sel, cc + 8'sd1),
                         checked_line_pixel(bottom_row_ok, b_sel, cc + 8'sd2),
                         checked_line_pixel(bottom_row_ok, b_sel, cc + 8'sd3),
                         checked_line_pixel(bottom_row_ok, b_sel, cc + 8'sd4));
    end
endtask

task push_group_2line_s2;
    input [5:0] out_r;
    input [5:0] out_c_base;
    input       top_row_ok;
    input       bottom_row_ok;
    input       t_sel;
    input       m_sel;
    input [7:0] b0;
    input [7:0] b1;
    input [7:0] b2;
    input [7:0] b3;
    input [7:0] b4;
    input [7:0] b5;
    input [7:0] b6;
    input [7:0] b7;
    input [7:0] b8;
    reg signed [7:0] cc;
    reg [7:0] t0, t1, t2, t3, t4, t5, t6, t7, t8;
    reg [7:0] m0, m1, m2, m3, m4, m5, m6, m7, m8;
    reg [7:0] bb0, bb1, bb2, bb3, bb4, bb5, bb6, bb7, bb8;
    begin
        mac_valid <= 1'b1;
        mac_base_addr <= make_addr(out_r, out_c_base);

        cc = $signed({1'b0, out_c_base, 1'b0});
        t0 = checked_line_pixel(top_row_ok, t_sel, cc - 8'sd1);
        t1 = checked_line_pixel(top_row_ok, t_sel, cc);
        t2 = checked_line_pixel(top_row_ok, t_sel, cc + 8'sd1);
        t3 = checked_line_pixel(top_row_ok, t_sel, cc + 8'sd2);
        t4 = checked_line_pixel(top_row_ok, t_sel, cc + 8'sd3);
        t5 = checked_line_pixel(top_row_ok, t_sel, cc + 8'sd4);
        t6 = checked_line_pixel(top_row_ok, t_sel, cc + 8'sd5);
        t7 = checked_line_pixel(top_row_ok, t_sel, cc + 8'sd6);
        t8 = checked_line_pixel(top_row_ok, t_sel, cc + 8'sd7);

        m0 = checked_line_pixel(1'b1, m_sel, cc - 8'sd1);
        m1 = checked_line_pixel(1'b1, m_sel, cc);
        m2 = checked_line_pixel(1'b1, m_sel, cc + 8'sd1);
        m3 = checked_line_pixel(1'b1, m_sel, cc + 8'sd2);
        m4 = checked_line_pixel(1'b1, m_sel, cc + 8'sd3);
        m5 = checked_line_pixel(1'b1, m_sel, cc + 8'sd4);
        m6 = checked_line_pixel(1'b1, m_sel, cc + 8'sd5);
        m7 = checked_line_pixel(1'b1, m_sel, cc + 8'sd6);
        m8 = checked_line_pixel(1'b1, m_sel, cc + 8'sd7);

        bb0 = bottom_row_ok ? b0 : 8'd0;
        bb1 = bottom_row_ok ? b1 : 8'd0;
        bb2 = bottom_row_ok ? b2 : 8'd0;
        bb3 = bottom_row_ok ? b3 : 8'd0;
        bb4 = bottom_row_ok ? b4 : 8'd0;
        bb5 = bottom_row_ok ? b5 : 8'd0;
        bb6 = bottom_row_ok ? b6 : 8'd0;
        bb7 = bottom_row_ok ? b7 : 8'd0;
        bb8 = bottom_row_ok ? b8 : 8'd0;

        mac_prod0[0] <= mul_pixel_weight(t0, w0);
        mac_prod0[1] <= mul_pixel_weight(t1, w1);
        mac_prod0[2] <= mul_pixel_weight(t2, w2);
        mac_prod0[3] <= mul_pixel_weight(m0, w3);
        mac_prod0[4] <= mul_pixel_weight(m1, w4);
        mac_prod0[5] <= mul_pixel_weight(m2, w5);
        mac_prod0[6] <= mul_pixel_weight(bb0, w6);
        mac_prod0[7] <= mul_pixel_weight(bb1, w7);
        mac_prod0[8] <= mul_pixel_weight(bb2, w8);

        mac_prod1[0] <= mul_pixel_weight(t2, w0);
        mac_prod1[1] <= mul_pixel_weight(t3, w1);
        mac_prod1[2] <= mul_pixel_weight(t4, w2);
        mac_prod1[3] <= mul_pixel_weight(m2, w3);
        mac_prod1[4] <= mul_pixel_weight(m3, w4);
        mac_prod1[5] <= mul_pixel_weight(m4, w5);
        mac_prod1[6] <= mul_pixel_weight(bb2, w6);
        mac_prod1[7] <= mul_pixel_weight(bb3, w7);
        mac_prod1[8] <= mul_pixel_weight(bb4, w8);

        mac_prod2[0] <= mul_pixel_weight(t4, w0);
        mac_prod2[1] <= mul_pixel_weight(t5, w1);
        mac_prod2[2] <= mul_pixel_weight(t6, w2);
        mac_prod2[3] <= mul_pixel_weight(m4, w3);
        mac_prod2[4] <= mul_pixel_weight(m5, w4);
        mac_prod2[5] <= mul_pixel_weight(m6, w5);
        mac_prod2[6] <= mul_pixel_weight(bb4, w6);
        mac_prod2[7] <= mul_pixel_weight(bb5, w7);
        mac_prod2[8] <= mul_pixel_weight(bb6, w8);

        mac_prod3[0] <= mul_pixel_weight(t6, w0);
        mac_prod3[1] <= mul_pixel_weight(t7, w1);
        mac_prod3[2] <= mul_pixel_weight(t8, w2);
        mac_prod3[3] <= mul_pixel_weight(m6, w3);
        mac_prod3[4] <= mul_pixel_weight(m7, w4);
        mac_prod3[5] <= mul_pixel_weight(m8, w5);
        mac_prod3[6] <= mul_pixel_weight(bb6, w6);
        mac_prod3[7] <= mul_pixel_weight(bb7, w7);
        mac_prod3[8] <= mul_pixel_weight(bb8, w8);
    end
endtask

task push_group_s2_from_input_window;
    input [5:0] out_r;
    input [3:0] out_group_idx;
    input [31:0] older_group;
    input [31:0] center_group;
    input [31:0] newer_group;
    begin
        push_group_2line_s2(out_r, {1'b0, out_group_idx[2:0], 2'b00}, 1'b1, 1'b1, top_sel, mid_sel,
                            (out_group_idx == 4'd0) ? 8'd0 : older_group[7:0],
                            center_group[31:24],
                            center_group[23:16],
                            center_group[15:8],
                            center_group[7:0],
                            newer_group[31:24],
                            newer_group[23:16],
                            newer_group[15:8],
                            newer_group[7:0]);
    end
endtask

task push_group_s2_from_line_bottom;
    input [5:0] out_r;
    input [3:0] out_group_idx;
    input       top_row_ok;
    input       bottom_row_ok;
    input       t_sel;
    input       m_sel;
    input       b_sel;
    reg signed [7:0] cc;
    begin
        cc = $signed({1'b0, {1'b0, out_group_idx[2:0], 2'b00}, 1'b0});
        push_group_2line_s2(out_r, {1'b0, out_group_idx[2:0], 2'b00}, top_row_ok, bottom_row_ok, t_sel, m_sel,
                            checked_line_pixel(bottom_row_ok, b_sel, cc - 8'sd1),
                            checked_line_pixel(bottom_row_ok, b_sel, cc),
                            checked_line_pixel(bottom_row_ok, b_sel, cc + 8'sd1),
                            checked_line_pixel(bottom_row_ok, b_sel, cc + 8'sd2),
                            checked_line_pixel(bottom_row_ok, b_sel, cc + 8'sd3),
                            checked_line_pixel(bottom_row_ok, b_sel, cc + 8'sd4),
                            checked_line_pixel(bottom_row_ok, b_sel, cc + 8'sd5),
                            checked_line_pixel(bottom_row_ok, b_sel, cc + 8'sd6),
                            checked_line_pixel(bottom_row_ok, b_sel, cc + 8'sd7));
    end
endtask

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
        pre_grp <= 4'd0;
        final_grp <= 4'd0;
        flush_phase <= 2'd0;
        drain_count <= 4'd0;
        top_sel <= 1'b0;
        mid_sel <= 1'b1;
        write_sel <= 1'b0;
        prev2_grp <= 32'd0;
        prev1_grp <= 32'd0;
        mac_valid <= 1'b0;
        sum_valid <= 1'b0;
        clamp_valid <= 1'b0;
        square_valid <= 1'b0;
        for (pi = 0; pi < 6; pi = pi + 1)
            pipe_valid[pi] <= 1'b0;
    end else begin
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
            o_out_addr1  <= pipe_base_addr[5];
            o_out_addr2  <= pipe_base_addr[5] + 12'd1;
            o_out_addr3  <= pipe_base_addr[5] + 12'd2;
            o_out_addr4  <= pipe_base_addr[5] + 12'd3;
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
            pipe_base_addr[pi] <= pipe_base_addr[pi-1];
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
            pipe_base_addr[0] <= square_base_addr;
        end

        if (clamp_valid) begin
            square_valid <= 1'b1;
            square_target0 <= square_u8(clamp0);
            square_target1 <= square_u8(clamp1);
            square_target2 <= square_u8(clamp2);
            square_target3 <= square_u8(clamp3);
            square_base_addr <= clamp_base_addr;
        end

        if (sum_valid) begin
            clamp_valid <= 1'b1;
            clamp0 <= clamp_acc(sum_a0 + sum_b0 + sum_c0);
            clamp1 <= clamp_acc(sum_a1 + sum_b1 + sum_c1);
            clamp2 <= clamp_acc(sum_a2 + sum_b2 + sum_c2);
            clamp3 <= clamp_acc(sum_a3 + sum_b3 + sum_c3);
            clamp_base_addr <= sum_base_addr;
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
            sum_base_addr <= mac_base_addr;
        end

        case (state)
            S_IDLE: begin
                o_in_ready <= 1'b1;
                state <= S_GET_W;
            end

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
                read_grp <= 4'd0;
                state <= S_LOAD0;
            end

            S_LOAD0: begin
                o_in_ready <= 1'b1;
                if (i_in_valid) begin
                    write_group_to_line(1'b0, in_col_base, i_in_data);
                    if (read_grp == 4'd15) begin
                        read_grp <= 4'd0;
                        state <= S_LOAD1;
                    end else begin
                        read_grp <= read_grp + 4'd1;
                    end
                end
            end

            S_LOAD1: begin
                o_in_ready <= 1'b1;
                if (i_in_valid) begin
                    write_group_to_line(1'b1, in_col_base, i_in_data);
                    if (read_grp == 4'd15) begin
                        o_in_ready <= 1'b0;
                        read_grp <= 4'd0;
                        pre_grp <= 4'd0;
                        top_sel <= 1'b0;
                        mid_sel <= 1'b1;
                        write_sel <= 1'b0;
                        state <= S_PRE_ROW0;
                    end else begin
                        read_grp <= read_grp + 4'd1;
                    end
                end
            end

            S_PRE_ROW0: begin
                o_in_ready <= 1'b0;
                if (stride_reg)
                    push_group_s2_from_line_bottom(6'd0, pre_grp, 1'b0, 1'b1, 1'b0, 1'b0, 1'b1);
                else
                    push_group_from_line_bottom(6'd0, pre_grp, 1'b0, 1'b1, 1'b0, 1'b0, 1'b1);

                if ((!stride_reg && pre_grp == 4'd15) || (stride_reg && pre_grp == 4'd7)) begin
                    read_row <= 7'd2;
                    read_grp <= 4'd0;
                    prev2_grp <= 32'd0;
                    prev1_grp <= 32'd0;
                    state <= S_STREAM;
                end else begin
                    pre_grp <= pre_grp + 4'd1;
                end
            end

            S_STREAM: begin
                o_in_ready <= 1'b1;
                if (i_in_valid) begin
                    if (stride_reg && !read_row[0]) begin
                        write_group_to_line(write_sel, in_col_base, i_in_data);

                        if (read_grp == 4'd15) begin
                            top_sel <= mid_sel;
                            mid_sel <= write_sel;
                            write_sel <= mid_sel;
                            read_grp <= 4'd0;
                            prev2_grp <= 32'd0;
                            prev1_grp <= 32'd0;
                            read_row <= read_row + 7'd1;
                        end else begin
                            read_grp <= read_grp + 4'd1;
                        end
                    end else begin
                        if (!stride_reg) begin
                            if (read_grp >= 4'd1)
                                push_group_from_input_window(read_row[5:0] - 6'd1, read_grp - 4'd1, prev2_grp, prev1_grp, i_in_data);

                            if (read_grp >= 4'd2)
                                write_group_to_line(write_sel, {read_grp - 4'd2, 2'b00}, prev2_grp);
                        end else begin
                            if (read_grp[0])
                                push_group_s2_from_input_window(read_row[5:1], read_grp[3:1], prev2_grp, prev1_grp, i_in_data);

                            if (read_grp[0] && read_grp >= 4'd3)
                                write_group_to_line(write_sel, {read_grp - 4'd2, 2'b00}, prev2_grp);
                            if (read_grp[0])
                                write_group_to_line(write_sel, {read_grp - 4'd1, 2'b00}, prev1_grp);
                        end

                        prev2_grp <= prev1_grp;
                        prev1_grp <= i_in_data;

                        if (read_grp == 4'd15) begin
                            o_in_ready <= 1'b0;
                            flush_phase <= 2'd0;
                            state <= S_ROW_FLUSH;
                        end else begin
                            read_grp <= read_grp + 4'd1;
                        end
                    end
                end
            end

            S_ROW_FLUSH: begin
                o_in_ready <= 1'b0;
                if (!stride_reg) begin
                    if (flush_phase == 2'd0) begin
                        push_group_from_input_window(read_row[5:0] - 6'd1, 4'd15, prev2_grp, prev1_grp, 32'd0);
                        write_group_to_line(write_sel, 6'd56, prev2_grp);
                        flush_phase <= 2'd1;
                    end else begin
                        write_group_to_line(write_sel, 6'd60, prev1_grp);
                        top_sel <= mid_sel;
                        mid_sel <= write_sel;
                        write_sel <= mid_sel;
                        read_grp <= 4'd0;
                        prev2_grp <= 32'd0;
                        prev1_grp <= 32'd0;
                        if (read_row == 7'd63) begin
                            final_grp <= 4'd0;
                            state <= S_FINAL_ROW;
                        end else begin
                            read_row <= read_row + 7'd1;
                            state <= S_STREAM;
                        end
                    end
                end else begin
                    write_group_to_line(write_sel, 6'd60, prev1_grp);
                    top_sel <= mid_sel;
                    mid_sel <= write_sel;
                    write_sel <= mid_sel;
                    read_grp <= 4'd0;
                    prev2_grp <= 32'd0;
                    prev1_grp <= 32'd0;
                    if (read_row == 7'd63) begin
                        drain_count <= 4'd0;
                        state <= S_DRAIN;
                    end else begin
                        read_row <= read_row + 7'd1;
                        state <= S_STREAM;
                    end
                end
            end

            S_FINAL_ROW: begin
                o_in_ready <= 1'b0;
                push_group_2line(6'd63, {final_grp, 2'b00}, 1'b1, 1'b0, top_sel, mid_sel,
                                 8'd0, 8'd0, 8'd0, 8'd0, 8'd0, 8'd0);
                if (final_grp == 4'd15) begin
                    drain_count <= 4'd0;
                    state <= S_DRAIN;
                end else begin
                    final_grp <= final_grp + 4'd1;
                end
            end

            S_DRAIN: begin
                o_in_ready <= 1'b0;
                if (drain_count == 4'd12) begin
                    state <= S_FINISH;
                end else begin
                    drain_count <= drain_count + 4'd1;
                end
            end

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
