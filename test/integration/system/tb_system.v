`default_nettype none
`timescale 1ns / 1ps

module tb_system ();
    `ifdef COCOTB_SIM
    initial begin
        $dumpfile("tb_system.fst");
        $dumpvars(0, tb_system);
        #1;
    end
    `endif

    reg        clk;
    reg        rst_n;
    reg        ena;
    reg  [7:0] ui_in;
    reg  [7:0] uio_in;
    wire [7:0] uo_out;
    wire [7:0] uio_out;
    wire [7:0] uio_oe;

    tt_um_tinymoa_ihp0p4_16x16 dut (
        .ui_in   (ui_in),
        .uo_out  (uo_out),
        .uio_in  (uio_in),
        .uio_out (uio_out),
        .uio_oe  (uio_oe),
        .ena     (ena),
        .clk     (clk),
        .rst_n   (rst_n)
    );
endmodule
