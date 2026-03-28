/*
 * Copyright (c) 2026 Ezra Wolf
 * SPDX-License-Identifier: Apache-2.0
 *
 * TinyMOA top level for TinyTapeout IHP0P4 experimental tapeout.
 * I/O wrapper for 8x8 DCIM core.
 *
 * Pin mapping:
 *   ui_in[7:0]   data in (weights during LOAD, activations during EXEC)
 *   uo_out[7:0]  result out during READ, zero otherwise
 *   uio_in[0]    go
 *   uio_in[1]    skip_load
 *   uio_in[3:2]  precision (bit-planes: 1, 2, or 4)
 *   uio_out[2:0] FSM state
 *   uio_out[3]   core done
 *   uio_oe       0x00 in IDLE (input for config), 0xFF otherwise (output for debug)
 */

`default_nettype none
`timescale 1ns / 1ps

module tt_um_tinymoa_ihp0p4_16x16 (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);
    localparam DIM = 8;
    localparam ACC = 6;
    localparam DIM_BITS = $clog2(DIM); // 3

    localparam IDLE = 2'd0;
    localparam LOAD = 2'd1;
    localparam EXEC = 2'd2;
    localparam READ = 2'd3;

    reg  [1:0]          state;
    reg  [DIM_BITS-1:0] count;
    reg  [2:0]          precision;
    reg                 skip;

    reg  [DIM-1:0]      din;
    reg                 wen;
    reg                 exec;
    reg  [DIM_BITS-1:0] col;
    wire [ACC-1:0]      result;
    wire                done;

    tinymoa_dcim #(.ARRAY_DIM(DIM), .ACC_WIDTH(ACC)) u_dcim (
        .clk     (clk),
        .nrst    (rst_n),
        .data_in (din),
        .wen     (wen),
        .execute (exec),
        .col_sel (col),
        .result  (result),
        .dbg_done(done)
    );

    reg [7:0] uo;
    assign uo_out  = uo;
    assign uio_out = {5'b0, done, state};
    assign uio_oe  = (state == IDLE) ? 8'h00 : 8'hFF;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            count   <= 0;
            precision  <= 3'd1;
            skip  <= 0;
            din   <= 0;
            wen   <= 0;
            exec  <= 0;
            col   <= 0;
            uo    <= 0;
        end else begin
            wen  <= 0;
            exec <= 0;

            case (state)
                IDLE: begin
                    uo  <= 0;
                    count <= 0;
                    col <= 0;
                    if (uio_in[0]) begin
                        skip  <= uio_in[1];
                        precision  <= (uio_in[3:2] == 2'b00) ? 3'd1 : {1'b0, uio_in[3:2]};
                        state <= uio_in[1] ? EXEC : LOAD;
                    end
                end

                LOAD: begin
                    din <= ui_in;
                    wen <= 1;
                    if (count == DIM[DIM_BITS-1:0] - 1) begin
                        count   <= 0;
                        state <= EXEC;
                    end else begin
                        count <= count + 1;
                    end
                end

                EXEC: begin
                    din  <= ui_in;
                    exec <= 1;
                    if (count == precision[DIM_BITS-1:0] - 1) begin
                        count   <= 0;
                        state <= READ;
                    end else begin
                        count <= count + 1;
                    end
                end

                READ: begin
                    uo  <= {{(8-ACC){1'b0}}, result};
                    col <= col + 1;
                    if (count == DIM[DIM_BITS-1:0] - 1) begin
                        state <= IDLE;
                    end else begin
                        count <= count + 1;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

    wire _unused = &{ena, 1'b0};

endmodule
