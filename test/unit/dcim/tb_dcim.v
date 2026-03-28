`default_nettype none
`timescale 1ns / 1ps

module tb_dcim (
    input  clk,
    input  nrst,

    input  [7:0] data_in,
    input        wen,
    input        execute,

    input  [2:0] col_sel,
    output [5:0] result,
    output       dbg_done
);
    `ifdef COCOTB_SIM
    initial begin
        $dumpfile("tb_dcim.fst");
        $dumpvars(0, tb_dcim);
        #1;
    end
    `endif

    tinymoa_dcim dut (
        .clk      (clk),
        .nrst     (nrst),
        .data_in  (data_in),
        .wen      (wen),
        .execute  (execute),
        .col_sel  (col_sel),
        .result   (result),
        .dbg_done (dbg_done)
    );

endmodule
