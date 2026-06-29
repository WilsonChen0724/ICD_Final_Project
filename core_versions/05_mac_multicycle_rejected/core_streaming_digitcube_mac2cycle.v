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
reg        mac_busy;
reg        mac_phase;
reg [5:0]  mac_job_out_r;
reg [5:0]  mac_job_out_c_base;
reg [6:0]  mac_job_center_r;
reg        sum_valid;
reg signed [18:0] sum_a0, sum_b0, sum_c0;
reg signed [18:0] sum_a1, sum_b1, sum_c1;
reg signed [18:0] sum_a2, sum_b2, sum_c2;
reg signed [18:0] sum_a3, sum_b3, sum_c3;
reg [11:0] sum_base_addr;

reg        clamp_valid;
reg [7:0]  clamp0, clamp1, clamp2, clamp3;
reg [11:0] clamp_base_addr;

reg        square_valid;
reg [15:0] square_target0, square_target1, square_target2, square_target3;
reg [11:0] square_base_addr;

// 4-lane, 6-stage cube-root pipeline. Each group carries 4 output pixels.
reg        pipe_valid [0:5];
reg [15:0] pipe_target0 [0:5], pipe_target1 [0:5], pipe_target2 [0:5], pipe_target3 [0:5];
reg [5:0]  pipe_root0 [0:5], pipe_root1 [0:5], pipe_root2 [0:5], pipe_root3 [0:5];
reg [10:0] pipe_root2_0 [0:5], pipe_root2_1 [0:5], pipe_root2_2 [0:5], pipe_root2_3 [0:5];
reg [15:0] pipe_root3_0 [0:5], pipe_root3_1 [0:5], pipe_root3_2 [0:5], pipe_root3_3 [0:5];
reg [11:0] pipe_base_addr [0:5];

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

function [7:0] get_pixel_raw;
    input [5:0] rr;
    input [5:0] cc;
    begin
        case (rr[1:0])
            2'd0: get_pixel_raw = line0[cc];
            2'd1: get_pixel_raw = line1[cc];
            2'd2: get_pixel_raw = line2[cc];
            default: get_pixel_raw = line3[cc];
        endcase
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

function signed [16:0] mul_pixel_weight;
    input [7:0] p;
    input signed [7:0] w;
    reg signed [8:0] p_s;
    reg signed [16:0] prod;
    begin
        p_s = $signed({1'b0, p});
        prod = p_s * w;
        mul_pixel_weight = prod;
    end
endfunction

function signed [18:0] row_sum3;
    input signed [16:0] a;
    input signed [16:0] b;
    input signed [16:0] c;
    begin
        row_sum3 = $signed({{2{a[16]}}, a}) + $signed({{2{b[16]}}, b}) + $signed({{2{c[16]}}, c});
    end
endfunction

function signed [19:0] row_total3;
    input signed [18:0] a;
    input signed [18:0] b;
    input signed [18:0] c;
    begin
        row_total3 = $signed({a[18], a}) + $signed({b[18], b}) + $signed({c[18], c});
    end
endfunction

function [32:0] cube_digit_next32;
    input [15:0] target;
    begin
        cube_digit_next32 = (18'd32768 <= {2'b00, target}) ?
                            {16'd32768, 11'd1024, 6'd32} :
                            {16'd0, 11'd0, 6'd0};
    end
endfunction

function [32:0] cube_digit_next16;
    input [5:0]  root;
    input [10:0] root2;
    input [15:0] root3;
    input [15:0] target;
    reg [5:0]  cand_root;
    reg [11:0] cand_root2;
    reg [17:0] term_a;
    reg [17:0] term_b;
    reg [17:0] sum_a;
    reg [17:0] sum_b;
    reg [17:0] sum_c;
    reg [17:0] cand_root3;
    begin
        cand_root = root + 6'd16;
        cand_root2 = root2 + ({6'd0, root} << 5) + 12'd256;
        term_a = {7'd0, root2} << 4;
        term_b = {12'd0, root} << 8;
        sum_a = {2'd0, root3} + term_a;
        sum_b = term_a + term_a;
        sum_c = term_b + term_b + term_b + 18'd4096;
        cand_root3 = sum_a + sum_b + sum_c;
        cube_digit_next16 = (cand_root3 <= {2'b00, target}) ?
                            {cand_root3[15:0], cand_root2[10:0], cand_root} :
                            {root3, root2, root};
    end
endfunction

function [32:0] cube_digit_next8;
    input [5:0]  root;
    input [10:0] root2;
    input [15:0] root3;
    input [15:0] target;
    reg [5:0]  cand_root;
    reg [11:0] cand_root2;
    reg [17:0] term_a;
    reg [17:0] term_b;
    reg [17:0] sum_a;
    reg [17:0] sum_b;
    reg [17:0] sum_c;
    reg [17:0] cand_root3;
    begin
        cand_root = root + 6'd8;
        cand_root2 = root2 + ({6'd0, root} << 4) + 12'd64;
        term_a = {7'd0, root2} << 3;
        term_b = {12'd0, root} << 6;
        sum_a = {2'd0, root3} + term_a;
        sum_b = term_a + term_a;
        sum_c = term_b + term_b + term_b + 18'd512;
        cand_root3 = sum_a + sum_b + sum_c;
        cube_digit_next8 = (cand_root3 <= {2'b00, target}) ?
                           {cand_root3[15:0], cand_root2[10:0], cand_root} :
                           {root3, root2, root};
    end
endfunction

function [32:0] cube_digit_next4;
    input [5:0]  root;
    input [10:0] root2;
    input [15:0] root3;
    input [15:0] target;
    reg [5:0]  cand_root;
    reg [11:0] cand_root2;
    reg [17:0] term_a;
    reg [17:0] term_b;
    reg [17:0] sum_a;
    reg [17:0] sum_b;
    reg [17:0] sum_c;
    reg [17:0] cand_root3;
    begin
        cand_root = root + 6'd4;
        cand_root2 = root2 + ({6'd0, root} << 3) + 12'd16;
        term_a = {7'd0, root2} << 2;
        term_b = {12'd0, root} << 4;
        sum_a = {2'd0, root3} + term_a;
        sum_b = term_a + term_a;
        sum_c = term_b + term_b + term_b + 18'd64;
        cand_root3 = sum_a + sum_b + sum_c;
        cube_digit_next4 = (cand_root3 <= {2'b00, target}) ?
                           {cand_root3[15:0], cand_root2[10:0], cand_root} :
                           {root3, root2, root};
    end
endfunction

function [32:0] cube_digit_next2;
    input [5:0]  root;
    input [10:0] root2;
    input [15:0] root3;
    input [15:0] target;
    reg [5:0]  cand_root;
    reg [11:0] cand_root2;
    reg [17:0] term_a;
    reg [17:0] term_b;
    reg [17:0] sum_a;
    reg [17:0] sum_b;
    reg [17:0] sum_c;
    reg [17:0] cand_root3;
    begin
        cand_root = root + 6'd2;
        cand_root2 = root2 + ({6'd0, root} << 2) + 12'd4;
        term_a = {7'd0, root2} << 1;
        term_b = {12'd0, root} << 2;
        sum_a = {2'd0, root3} + term_a;
        sum_b = term_a + term_a;
        sum_c = term_b + term_b + term_b + 18'd8;
        cand_root3 = sum_a + sum_b + sum_c;
        cube_digit_next2 = (cand_root3 <= {2'b00, target}) ?
                           {cand_root3[15:0], cand_root2[10:0], cand_root} :
                           {root3, root2, root};
    end
endfunction

function [32:0] cube_digit_next1;
    input [5:0]  root;
    input [10:0] root2;
    input [15:0] root3;
    input [15:0] target;
    reg [5:0]  cand_root;
    reg [11:0] cand_root2;
    reg [17:0] term_a;
    reg [17:0] term_b;
    reg [17:0] sum_a;
    reg [17:0] sum_b;
    reg [17:0] cand_root3;
    begin
        cand_root = root + 6'd1;
        cand_root2 = root2 + ({6'd0, root} << 1) + 12'd1;
        term_a = {7'd0, root2};
        term_b = {12'd0, root};
        sum_a = {2'd0, root3} + term_a + term_a;
        sum_b = term_a + term_b + term_b + term_b + 18'd1;
        cand_root3 = sum_a + sum_b;
        cube_digit_next1 = (cand_root3 <= {2'b00, target}) ?
                           {cand_root3[15:0], cand_root2[10:0], cand_root} :
                           {root3, root2, root};
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
function signed [16:0] calc_product;
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
// Queue one group of 4 pixels for the shared 2-cycle MAC engine.
// ============================================================
task push_group;
    input [5:0] out_r;
    input [5:0] out_c_base;
    input [6:0] center_r;
    begin
        o_in_ready <= 1'b0;
        mac_busy <= 1'b1;
        mac_phase <= 1'b1;
        mac_job_out_r <= out_r;
        mac_job_out_c_base <= out_c_base;
        mac_job_center_r <= center_r;
        sum_base_addr <= make_addr(out_r, out_c_base);
        sum_a0 <= row_sum3(calc_product(center_r, stride_reg ? {out_c_base, 1'b0} : {1'b0, out_c_base}, 4'd0), calc_product(center_r, stride_reg ? {out_c_base, 1'b0} : {1'b0, out_c_base}, 4'd1), calc_product(center_r, stride_reg ? {out_c_base, 1'b0} : {1'b0, out_c_base}, 4'd2));
        sum_b0 <= row_sum3(calc_product(center_r, stride_reg ? {out_c_base, 1'b0} : {1'b0, out_c_base}, 4'd3), calc_product(center_r, stride_reg ? {out_c_base, 1'b0} : {1'b0, out_c_base}, 4'd4), calc_product(center_r, stride_reg ? {out_c_base, 1'b0} : {1'b0, out_c_base}, 4'd5));
        sum_a1 <= row_sum3(calc_product(center_r, stride_reg ? {out_c_base + 6'd1, 1'b0} : {1'b0, out_c_base + 6'd1}, 4'd0), calc_product(center_r, stride_reg ? {out_c_base + 6'd1, 1'b0} : {1'b0, out_c_base + 6'd1}, 4'd1), calc_product(center_r, stride_reg ? {out_c_base + 6'd1, 1'b0} : {1'b0, out_c_base + 6'd1}, 4'd2));
        sum_b1 <= row_sum3(calc_product(center_r, stride_reg ? {out_c_base + 6'd1, 1'b0} : {1'b0, out_c_base + 6'd1}, 4'd3), calc_product(center_r, stride_reg ? {out_c_base + 6'd1, 1'b0} : {1'b0, out_c_base + 6'd1}, 4'd4), calc_product(center_r, stride_reg ? {out_c_base + 6'd1, 1'b0} : {1'b0, out_c_base + 6'd1}, 4'd5));
        sum_a2 <= row_sum3(calc_product(center_r, stride_reg ? {out_c_base + 6'd2, 1'b0} : {1'b0, out_c_base + 6'd2}, 4'd0), calc_product(center_r, stride_reg ? {out_c_base + 6'd2, 1'b0} : {1'b0, out_c_base + 6'd2}, 4'd1), calc_product(center_r, stride_reg ? {out_c_base + 6'd2, 1'b0} : {1'b0, out_c_base + 6'd2}, 4'd2));
        sum_b2 <= row_sum3(calc_product(center_r, stride_reg ? {out_c_base + 6'd2, 1'b0} : {1'b0, out_c_base + 6'd2}, 4'd3), calc_product(center_r, stride_reg ? {out_c_base + 6'd2, 1'b0} : {1'b0, out_c_base + 6'd2}, 4'd4), calc_product(center_r, stride_reg ? {out_c_base + 6'd2, 1'b0} : {1'b0, out_c_base + 6'd2}, 4'd5));
        sum_a3 <= row_sum3(calc_product(center_r, stride_reg ? {out_c_base + 6'd3, 1'b0} : {1'b0, out_c_base + 6'd3}, 4'd0), calc_product(center_r, stride_reg ? {out_c_base + 6'd3, 1'b0} : {1'b0, out_c_base + 6'd3}, 4'd1), calc_product(center_r, stride_reg ? {out_c_base + 6'd3, 1'b0} : {1'b0, out_c_base + 6'd3}, 4'd2));
        sum_b3 <= row_sum3(calc_product(center_r, stride_reg ? {out_c_base + 6'd3, 1'b0} : {1'b0, out_c_base + 6'd3}, 4'd3), calc_product(center_r, stride_reg ? {out_c_base + 6'd3, 1'b0} : {1'b0, out_c_base + 6'd3}, 4'd4), calc_product(center_r, stride_reg ? {out_c_base + 6'd3, 1'b0} : {1'b0, out_c_base + 6'd3}, 4'd5));
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
        mac_busy <= 1'b0;
        mac_phase <= 1'b0;
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
            o_out_data1  <= {2'b00, pipe_root0[5]};
            o_out_data2  <= {2'b00, pipe_root1[5]};
            o_out_data3  <= {2'b00, pipe_root2[5]};
            o_out_data4  <= {2'b00, pipe_root3[5]};
            o_out_addr1  <= pipe_base_addr[5];
            o_out_addr2  <= pipe_base_addr[5] + 12'd1;
            o_out_addr3  <= pipe_base_addr[5] + 12'd2;
            o_out_addr4  <= pipe_base_addr[5] + 12'd3;
            o_out_valid1 <= 1'b1;
            o_out_valid2 <= 1'b1;
            o_out_valid3 <= 1'b1;
            o_out_valid4 <= 1'b1;
        end

        pipe_valid[5] <= pipe_valid[4];
        pipe_target0[5] <= pipe_target0[4];
        pipe_target1[5] <= pipe_target1[4];
        pipe_target2[5] <= pipe_target2[4];
        pipe_target3[5] <= pipe_target3[4];
        {pipe_root3_0[5], pipe_root2_0[5], pipe_root0[5]} <= cube_digit_next1(pipe_root0[4], pipe_root2_0[4], pipe_root3_0[4], pipe_target0[4]);
        {pipe_root3_1[5], pipe_root2_1[5], pipe_root1[5]} <= cube_digit_next1(pipe_root1[4], pipe_root2_1[4], pipe_root3_1[4], pipe_target1[4]);
        {pipe_root3_2[5], pipe_root2_2[5], pipe_root2[5]} <= cube_digit_next1(pipe_root2[4], pipe_root2_2[4], pipe_root3_2[4], pipe_target2[4]);
        {pipe_root3_3[5], pipe_root2_3[5], pipe_root3[5]} <= cube_digit_next1(pipe_root3[4], pipe_root2_3[4], pipe_root3_3[4], pipe_target3[4]);
        pipe_base_addr[5] <= pipe_base_addr[4];

        pipe_valid[4] <= pipe_valid[3];
        pipe_target0[4] <= pipe_target0[3];
        pipe_target1[4] <= pipe_target1[3];
        pipe_target2[4] <= pipe_target2[3];
        pipe_target3[4] <= pipe_target3[3];
        {pipe_root3_0[4], pipe_root2_0[4], pipe_root0[4]} <= cube_digit_next2(pipe_root0[3], pipe_root2_0[3], pipe_root3_0[3], pipe_target0[3]);
        {pipe_root3_1[4], pipe_root2_1[4], pipe_root1[4]} <= cube_digit_next2(pipe_root1[3], pipe_root2_1[3], pipe_root3_1[3], pipe_target1[3]);
        {pipe_root3_2[4], pipe_root2_2[4], pipe_root2[4]} <= cube_digit_next2(pipe_root2[3], pipe_root2_2[3], pipe_root3_2[3], pipe_target2[3]);
        {pipe_root3_3[4], pipe_root2_3[4], pipe_root3[4]} <= cube_digit_next2(pipe_root3[3], pipe_root2_3[3], pipe_root3_3[3], pipe_target3[3]);
        pipe_base_addr[4] <= pipe_base_addr[3];

        pipe_valid[3] <= pipe_valid[2];
        pipe_target0[3] <= pipe_target0[2];
        pipe_target1[3] <= pipe_target1[2];
        pipe_target2[3] <= pipe_target2[2];
        pipe_target3[3] <= pipe_target3[2];
        {pipe_root3_0[3], pipe_root2_0[3], pipe_root0[3]} <= cube_digit_next4(pipe_root0[2], pipe_root2_0[2], pipe_root3_0[2], pipe_target0[2]);
        {pipe_root3_1[3], pipe_root2_1[3], pipe_root1[3]} <= cube_digit_next4(pipe_root1[2], pipe_root2_1[2], pipe_root3_1[2], pipe_target1[2]);
        {pipe_root3_2[3], pipe_root2_2[3], pipe_root2[3]} <= cube_digit_next4(pipe_root2[2], pipe_root2_2[2], pipe_root3_2[2], pipe_target2[2]);
        {pipe_root3_3[3], pipe_root2_3[3], pipe_root3[3]} <= cube_digit_next4(pipe_root3[2], pipe_root2_3[2], pipe_root3_3[2], pipe_target3[2]);
        pipe_base_addr[3] <= pipe_base_addr[2];

        pipe_valid[2] <= pipe_valid[1];
        pipe_target0[2] <= pipe_target0[1];
        pipe_target1[2] <= pipe_target1[1];
        pipe_target2[2] <= pipe_target2[1];
        pipe_target3[2] <= pipe_target3[1];
        {pipe_root3_0[2], pipe_root2_0[2], pipe_root0[2]} <= cube_digit_next8(pipe_root0[1], pipe_root2_0[1], pipe_root3_0[1], pipe_target0[1]);
        {pipe_root3_1[2], pipe_root2_1[2], pipe_root1[2]} <= cube_digit_next8(pipe_root1[1], pipe_root2_1[1], pipe_root3_1[1], pipe_target1[1]);
        {pipe_root3_2[2], pipe_root2_2[2], pipe_root2[2]} <= cube_digit_next8(pipe_root2[1], pipe_root2_2[1], pipe_root3_2[1], pipe_target2[1]);
        {pipe_root3_3[2], pipe_root2_3[2], pipe_root3[2]} <= cube_digit_next8(pipe_root3[1], pipe_root2_3[1], pipe_root3_3[1], pipe_target3[1]);
        pipe_base_addr[2] <= pipe_base_addr[1];

        pipe_valid[1] <= pipe_valid[0];
        pipe_target0[1] <= pipe_target0[0];
        pipe_target1[1] <= pipe_target1[0];
        pipe_target2[1] <= pipe_target2[0];
        pipe_target3[1] <= pipe_target3[0];
        {pipe_root3_0[1], pipe_root2_0[1], pipe_root0[1]} <= cube_digit_next16(pipe_root0[0], pipe_root2_0[0], pipe_root3_0[0], pipe_target0[0]);
        {pipe_root3_1[1], pipe_root2_1[1], pipe_root1[1]} <= cube_digit_next16(pipe_root1[0], pipe_root2_1[0], pipe_root3_1[0], pipe_target1[0]);
        {pipe_root3_2[1], pipe_root2_2[1], pipe_root2[1]} <= cube_digit_next16(pipe_root2[0], pipe_root2_2[0], pipe_root3_2[0], pipe_target2[0]);
        {pipe_root3_3[1], pipe_root2_3[1], pipe_root3[1]} <= cube_digit_next16(pipe_root3[0], pipe_root2_3[0], pipe_root3_3[0], pipe_target3[0]);
        pipe_base_addr[1] <= pipe_base_addr[0];

        pipe_valid[0] <= 1'b0;
        sum_valid <= 1'b0;
        clamp_valid <= 1'b0;
        square_valid <= 1'b0;

        if (square_valid) begin
            pipe_valid[0] <= 1'b1;
            pipe_target0[0] <= square_target0;
            pipe_target1[0] <= square_target1;
            pipe_target2[0] <= square_target2;
            pipe_target3[0] <= square_target3;
            {pipe_root3_0[0], pipe_root2_0[0], pipe_root0[0]} <= cube_digit_next32(square_target0);
            {pipe_root3_1[0], pipe_root2_1[0], pipe_root1[0]} <= cube_digit_next32(square_target1);
            {pipe_root3_2[0], pipe_root2_2[0], pipe_root2[0]} <= cube_digit_next32(square_target2);
            {pipe_root3_3[0], pipe_root2_3[0], pipe_root3[0]} <= cube_digit_next32(square_target3);
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
            clamp0 <= clamp_acc(row_total3(sum_a0, sum_b0, sum_c0));
            clamp1 <= clamp_acc(row_total3(sum_a1, sum_b1, sum_c1));
            clamp2 <= clamp_acc(row_total3(sum_a2, sum_b2, sum_c2));
            clamp3 <= clamp_acc(row_total3(sum_a3, sum_b3, sum_c3));
            clamp_base_addr <= sum_base_addr;
        end

        if (mac_busy && mac_phase) begin
            mac_busy <= 1'b0;
            mac_phase <= 1'b0;
            sum_valid <= 1'b1;
            sum_c0 <= row_sum3(calc_product(mac_job_center_r, stride_reg ? {mac_job_out_c_base, 1'b0} : {1'b0, mac_job_out_c_base}, 4'd6),
                               calc_product(mac_job_center_r, stride_reg ? {mac_job_out_c_base, 1'b0} : {1'b0, mac_job_out_c_base}, 4'd7),
                               calc_product(mac_job_center_r, stride_reg ? {mac_job_out_c_base, 1'b0} : {1'b0, mac_job_out_c_base}, 4'd8));
            sum_c1 <= row_sum3(calc_product(mac_job_center_r, stride_reg ? {mac_job_out_c_base + 6'd1, 1'b0} : {1'b0, mac_job_out_c_base + 6'd1}, 4'd6),
                               calc_product(mac_job_center_r, stride_reg ? {mac_job_out_c_base + 6'd1, 1'b0} : {1'b0, mac_job_out_c_base + 6'd1}, 4'd7),
                               calc_product(mac_job_center_r, stride_reg ? {mac_job_out_c_base + 6'd1, 1'b0} : {1'b0, mac_job_out_c_base + 6'd1}, 4'd8));
            sum_c2 <= row_sum3(calc_product(mac_job_center_r, stride_reg ? {mac_job_out_c_base + 6'd2, 1'b0} : {1'b0, mac_job_out_c_base + 6'd2}, 4'd6),
                               calc_product(mac_job_center_r, stride_reg ? {mac_job_out_c_base + 6'd2, 1'b0} : {1'b0, mac_job_out_c_base + 6'd2}, 4'd7),
                               calc_product(mac_job_center_r, stride_reg ? {mac_job_out_c_base + 6'd2, 1'b0} : {1'b0, mac_job_out_c_base + 6'd2}, 4'd8));
            sum_c3 <= row_sum3(calc_product(mac_job_center_r, stride_reg ? {mac_job_out_c_base + 6'd3, 1'b0} : {1'b0, mac_job_out_c_base + 6'd3}, 4'd6),
                               calc_product(mac_job_center_r, stride_reg ? {mac_job_out_c_base + 6'd3, 1'b0} : {1'b0, mac_job_out_c_base + 6'd3}, 4'd7),
                               calc_product(mac_job_center_r, stride_reg ? {mac_job_out_c_base + 6'd3, 1'b0} : {1'b0, mac_job_out_c_base + 6'd3}, 4'd8));
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
                mac_busy <= 1'b0;
                mac_phase <= 1'b0;
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
                o_in_ready <= !mac_busy;

                if (i_in_valid && !mac_busy) begin
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

                if (!mac_busy && !stride_reg) begin
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
                end else if (!mac_busy) begin
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
                if (drain_count == 4'd11) begin
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


