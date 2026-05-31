`timescale 1ns/1ps
`define CYCLE       10.0
`define HCYCLE      (`CYCLE/2)
`define MAX_CYCLE   1000000
`define RST_DELAY   2

`ifdef tb1
    `define INFILE "../00_TESTBED/PATTERNS/img1_0301.dat"
    `define WFILE  "../00_TESTBED/PATTERNS/weight_img1_0301.dat"
    `define GOLDEN "../00_TESTBED/PATTERNS/golden_img1_0301.dat"
    `define STRIDE_MODE 0
    `define OUTPUTSIZE 4096
`elsif tb2
    `define INFILE "../00_TESTBED/PATTERNS/img2_0301.dat"
    `define WFILE  "../00_TESTBED/PATTERNS/weight_img2_0301.dat"
    `define GOLDEN "../00_TESTBED/PATTERNS/golden_img2_0301.dat"
    `define STRIDE_MODE 0
    `define OUTPUTSIZE 4096
`elsif tb3
    `define INFILE "../00_TESTBED/PATTERNS/img3_0302.dat"
    `define WFILE  "../00_TESTBED/PATTERNS/weight_img3_0302.dat"
    `define GOLDEN "../00_TESTBED/PATTERNS/golden_img3_0302.dat"
    `define STRIDE_MODE 1
    `define OUTPUTSIZE 1024
`elsif tb4
    `define INFILE "../00_TESTBED/PATTERNS/img4_0302.dat"
    `define WFILE  "../00_TESTBED/PATTERNS/weight_img4_0302.dat"
    `define GOLDEN "../00_TESTBED/PATTERNS/golden_img4_0302.dat"
    `define STRIDE_MODE 1
    `define OUTPUTSIZE 1024
`else
    `define INFILE "../00_TESTBED/PATTERNS/img1_0301.dat"
    `define WFILE  "../00_TESTBED/PATTERNS/weight_img1_0301.dat"
    `define GOLDEN "../00_TESTBED/PATTERNS/golden_img1_0301.dat"
    `define STRIDE_MODE 0
    `define OUTPUTSIZE 4096
`endif


module testbed;

    reg         clk, rst_n;
    reg         in_valid;
    reg  [31:0] in_data;
    reg         stride_mode;
    reg  [71:0] weight;

    wire        in_ready;
    wire        out_valid1, out_valid2, out_valid3, out_valid4;
    wire [11:0] out_addr1, out_addr2, out_addr3, out_addr4;
    wire [ 7:0] out_data1, out_data2, out_data3, out_data4;
    wire        exe_finish;

    reg  [ 7:0] indata_mem [0:4095];
    reg  [ 7:0] weight_mem [0:8];
    reg  [ 7:0] golden_mem [0:4095];
    reg  [ 7:0] out_mem    [0:4095];

    integer cnt1, cnt2, cycle_count;
    integer error;

    `ifdef SDF_GATE
        initial $sdf_annotate("../02_SYN/Netlist/core_syn.sdf", u_core);
    `elsif SDF_POST
        initial $sdf_annotate("../04_APR/core_APR.sdf", u_core);
    `endif

    initial begin
        $fsdbDumpfile("core.fsdb");
        $fsdbDumpvars(0, testbed, "+mda");
    end

    core u_core (
        .i_clk        (clk),
        .i_rst_n      (rst_n),
        .i_in_valid   (in_valid),
        .i_in_data    (in_data),
        .i_stride_mode(stride_mode),
        .i_weight     (weight),

        .o_in_ready   (in_ready),

        .o_out_data1  (out_data1),
        .o_out_data2  (out_data2),
        .o_out_data3  (out_data3),
        .o_out_data4  (out_data4),

        .o_out_addr1  (out_addr1),
        .o_out_addr2  (out_addr2),
        .o_out_addr3  (out_addr3),
        .o_out_addr4  (out_addr4),

        .o_out_valid1 (out_valid1),
        .o_out_valid2 (out_valid2),
        .o_out_valid3 (out_valid3),
        .o_out_valid4 (out_valid4),

        .o_exe_finish (exe_finish)
    );


    initial $readmemh(`INFILE,  indata_mem);
    initial $readmemh(`WFILE,   weight_mem);
    initial $readmemh(`GOLDEN,  golden_mem);


    initial clk = 1'b0;
    always #(`CYCLE/2) clk = ~clk;


    initial begin
        rst_n = 1; #(0.25 * `CYCLE);
        rst_n = 0; #((`RST_DELAY + 0.7) * `CYCLE);
        rst_n = 1; #(`MAX_CYCLE * `CYCLE);
        $display("Error! Runtime exceeded!");
        $finish;
    end


    initial begin
        stride_mode = `STRIDE_MODE;
    end


    initial begin
        cnt1 = 0;
        in_valid = 0;
        in_data  = 0;
        weight   = 72'd0;

        wait (rst_n === 1'b0);
        wait (rst_n === 1'b1);


        @(negedge clk);
        wait (in_ready === 1);


        @(negedge clk);
        weight = {weight_mem[0], weight_mem[1], weight_mem[2],
                  weight_mem[3], weight_mem[4], weight_mem[5],
                  weight_mem[6], weight_mem[7], weight_mem[8]};

        // Weight valid for 1 cycle only
        @(negedge clk);
        weight = 72'd0;

        // Send image data: assert in_valid only when in_ready is high
        while (cnt1 < 1024) begin
            @(negedge clk);
            if (in_ready) begin
                in_valid = 1;
                in_data = {indata_mem[cnt1*4], indata_mem[cnt1*4+1],
                           indata_mem[cnt1*4+2], indata_mem[cnt1*4+3]};
                cnt1 = cnt1 + 1;
            end else begin
                in_valid = 0;
                in_data  = 0;
            end
        end

        @(negedge clk);
        in_valid = 0;
        in_data  = 0;
    end

    initial begin
        error = 0;
        cnt2  = 0;

        wait (rst_n === 1'b0);
        wait (rst_n === 1'b1);

        while (!exe_finish) begin
            @(negedge clk);
            if (out_valid1) out_mem[out_addr1] = out_data1;
            if (out_valid2) out_mem[out_addr2] = out_data2;
            if (out_valid3) out_mem[out_addr3] = out_data3;
            if (out_valid4) out_mem[out_addr4] = out_data4;
        end

        @(negedge clk);
        while (cnt2 < `OUTPUTSIZE) begin
            if (golden_mem[cnt2] !== out_mem[cnt2]) begin
                $display("[ADDR %4d] Error: golden=%h, yours=%h", cnt2, golden_mem[cnt2], out_mem[cnt2]);
                error = error + 1;
            end
            cnt2 = cnt2 + 1;
        end

        $display("\n  *************************************");
        $display("  *               RESULT              *");
        $display("  *************************************");

        if (error === 0) begin
            $display("");
            $display("         #    ###############    _   _ ");
            $display("        #     #             #    *   * ");
            $display("   #   #      #   CORRECT   #      |   ");
            $display("    # #       #             #    \\___/ ");
            $display("     #        ###############          ");
            $display("");
            $display("----------------------------------------------");
            $display("       CONGRATULATION! ALL DATA PASS!       ");
            $display("----------------------------------------------\n");
        end else begin
            $display("");
            $display("    #   #     ################# ");
            $display("     # #      #               # ");
            $display("      #       #   INCORRECT   # ");
            $display("     # #      #               # ");
            $display("    #   #     ################# ");
            $display("");
            $display("----------------------------------------------");
            $display("    Wrong! Total Error for DATA: %d  ", error);
            $display("----------------------------------------------");
        end


        #(2 * `CYCLE);
        $finish;
    end

endmodule
