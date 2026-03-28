/*
 * Copyright (c) 2026 Ezra Wolf
 * SPDX-License-Identifier: Apache-2.0
 *
 * TinyMOA top level for TinyTapeout IHP0P4 experimental tapeout.
 */

`default_nettype none
`timescale 1ns / 1ps

module tt_um_tinymoa_ihp0p4 (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);

    wire        ctl_ready;
    wire [31:0] ctl_rdata;
    wire [31:0] mem_wdata;
    wire        mem_write;
    wire        mem_read;
    wire [9:0]  mem_addr;
    wire [2:0]  dbg_state;

    // ui_in[7] = ctl_write, [6] = ctl_read, [5:0] = ctl_addr
    // uio_in[7:0] = mem_rdata / ctl_wdata low byte
    wire [31:0] stub_mem_rdata  = {24'd0, uio_in};
    wire [31:0] stub_ctl_wdata = {24'd0, uio_in};

    tinymoa_dcim #(
        .ARRAY_DIM (16),
        .ACC_WIDTH (9)
    ) u_dcim (
        .clk       (clk),
        .nrst      (rst_n),

        .ctl_ready (ctl_ready),
        .ctl_write (ui_in[7]),
        .ctl_wdata (stub_ctl_wdata),
        .ctl_read  (ui_in[6]),
        .ctl_rdata (ctl_rdata),
        .ctl_addr  (ui_in[5:0]),

        .mem_rdata (stub_mem_rdata),
        .mem_wdata (mem_wdata),
        .mem_write (mem_write),
        .mem_read  (mem_read),
        .mem_addr  (mem_addr),

        .dbg_state (dbg_state)
    );

    assign uo_out  = {mem_addr[1:0], mem_read, mem_write, ctl_ready, dbg_state};
    assign uio_out = ctl_rdata[7:0] | mem_wdata[7:0];
    assign uio_oe  = 8'hFF;

    wire _unused = &{ena, ctl_rdata[31:8], mem_wdata[31:8], mem_addr[9:2], 1'b0};

endmodule
