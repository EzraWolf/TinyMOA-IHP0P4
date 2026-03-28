/*
 * Copyright (c) 2026 Ezra Wolf
 * SPDX-License-Identifier: Apache-2.0
 *
 * TinyMOA 16x16 DCIM Core
 *
 * Based on ISSCC 2022, Wang et al.
 * "DIMC: 2219TOPS/W 2569F2/b Digital In-Memory Computing Macro
 *  in 28nm Based on Approximate Arithmetic Hardware"
 *
 * Weights stored in FFs (N cols x N bits), loaded from memory.
 * Activations read bit-serially (1 bit-plane per COMPUTE cycle).
 * Results written back with hardware signed conversion.
 * All standard cells, no ADC, no custom-drawn cells.
 *
 * Weight loading performs a runtime transpose:
 *   Memory stores weights row-major; LOAD_WEIGHTS distributes one bit
 *   per row to each column register so weight_reg[col][row] = W[row][col].
 *
 * Compressor mode selected at elaboration via `define flags:
 *   EXACT_COMPRESSOR, SINGLE_APPROX_COMPRESSOR, or double-approx (default).
 */

`default_nettype none
`timescale 1ns / 1ps

module tinymoa_dcim #(
    parameter ARRAY_DIM = 16, // NxN array
    parameter ACC_WIDTH = 9   // max val = N*(2^P-1)
)(
    input clk,
    input nrst,

    output reg        ctl_ready,
    input             ctl_write,
    input      [31:0] ctl_wdata,
    input             ctl_read,
    output reg [31:0] ctl_rdata,
    input      [5:0]  ctl_addr,

    input      [31:0] mem_rdata,
    output reg [31:0] mem_wdata,
    output reg        mem_write,
    output reg        mem_read,
    output reg [9:0]  mem_addr,

    output [2:0] dbg_state
);

    reg        cfg_start;
    reg        cfg_reload_weights;
    reg [2:0]  cfg_precision;
    reg [9:0]  cfg_weight_base;
    reg [9:0]  cfg_act_base;
    reg [9:0]  cfg_result_base;
    reg [5:0]  cfg_array_size;

    reg [1:0]  status_reg; // bit 0 = BUSY, bit 1 = DONE

    // Effectively "weight_reg[col][row] = W[row][col]" after LOAD_WEIGHTS
    reg [ARRAY_DIM-1:0] weight_reg [0:ARRAY_DIM-1];
    reg [ACC_WIDTH-1:0] shift_acc  [0:ARRAY_DIM-1];

    reg [ARRAY_DIM-1:0] act_slice;

    reg [15:0] bias_reg; // cfg_array_size * (2^cfg_precision - 1)

    // XNOR + compressor: one per column (16x16 array)
    wire [4:0] comp_out [0:ARRAY_DIM-1];
    // wire [4:0] comp_lo_out [0:ARRAY_DIM-1]; // 32x32 array
    // wire [4:0] comp_hi_out [0:ARRAY_DIM-1]; // 32x32 array
    wire [5:0] popcount [0:ARRAY_DIM-1];

    genvar col;
    generate
        for (col = 0; col < ARRAY_DIM; col = col + 1) begin : gen_col
            wire [ARRAY_DIM-1:0] xnor_bits = ~(weight_reg[col] ^ act_slice);

            tinymoa_compressor comp (
                .in  (xnor_bits[15:0]),
                .out (comp_out[col])
            );

            // tinymoa_compressor comp_lo (
            //     .in  (xnor_bits[15:0]),
            //     .out (comp_lo_out[col])
            // );

            // tinymoa_compressor comp_hi (
            //     .in  (xnor_bits[31:16]),
            //     .out (comp_hi_out[col])
            // );

            // 16x16: single compressor
            assign popcount[col] = {1'b0, comp_out[col]};

            // 32x32: sum of two compressors
            // assign popcount[col] = {1'b0, comp_lo_out[col]} + {1'b0, comp_hi_out[col]};
        end
    endgenerate

    ////////////////////

    localparam IDLE         = 3'd0;
    localparam LOAD_WEIGHTS = 3'd1;
    localparam FETCH_ACT    = 3'd2;
    localparam COMPUTE      = 3'd3;
    localparam STORE_RESULT = 3'd4;
    localparam DONE         = 3'd5;

    reg [2:0] state;
    assign dbg_state = state;

    reg [5:0] row_idx;
    reg [2:0] bit_plane;
    reg [1:0] fetch_wait;

    // Control register block (independent of FSM)
    always @(posedge clk or negedge nrst) begin
        if (!nrst) begin
            cfg_start          <= 1'b0;
            cfg_reload_weights <= 1'b1;
            cfg_precision      <= 3'd1;
            cfg_weight_base    <= 10'h180;
            cfg_act_base       <= 10'h1A0;
            cfg_result_base    <= 10'h1B0;
            cfg_array_size     <= ARRAY_DIM[5:0];
            ctl_ready          <= 1'b0;
            ctl_rdata          <= 32'd0;
        end else begin
            ctl_ready <= 1'b0;

            if (ctl_write) begin
                ctl_ready <= 1'b1;
                case (ctl_addr[5:2])
                    4'd0: {cfg_reload_weights, cfg_precision, cfg_start} <= ctl_wdata[4:0];
                    4'd2: cfg_weight_base <= ctl_wdata[9:0];
                    4'd3: cfg_act_base    <= ctl_wdata[9:0];
                    4'd4: cfg_result_base <= ctl_wdata[9:0];
                    4'd5: cfg_array_size  <= ctl_wdata[5:0];
                    default: ;
                endcase
            end

            if (ctl_read) begin
                ctl_ready <= 1'b1;
                case (ctl_addr[5:2])
                    4'd0: ctl_rdata <= {27'd0, cfg_reload_weights, cfg_precision, cfg_start};
                    4'd1: ctl_rdata <= status_reg;
                    4'd2: ctl_rdata <= {22'd0, cfg_weight_base};
                    4'd3: ctl_rdata <= {22'd0, cfg_act_base};
                    4'd4: ctl_rdata <= {22'd0, cfg_result_base};
                    4'd5: ctl_rdata <= {26'd0, cfg_array_size};
                    default: ctl_rdata <= 32'd0;
                endcase
            end

            // cfg_start self-clears once FSM leaves IDLE
            if (state != IDLE) cfg_start <= 1'b0;
        end
    end

    // Signed conversion maps raw XNOR popcount acc. to true signed dotprod
    // 2 * shift_acc[col] - bias_reg
    wire signed [16:0] store_signed =
        {2'b0, shift_acc[row_idx], 1'b0} - {1'b0, bias_reg};
    wire [31:0] store_word =
        {{15{store_signed[16]}}, store_signed};

    integer i;
    always @(posedge clk or negedge nrst) begin
        if (!nrst) begin
            state      <= IDLE;
            status_reg <= 2'b0;
            row_idx    <= 6'b0;
            bit_plane  <= 3'b0;
            bias_reg   <= 16'b0;
            fetch_wait <= 2'b0;
            mem_write  <= 1'b0;
            mem_read   <= 1'b0;
            mem_addr   <= 10'b0;
            mem_wdata  <= 32'b0;
            act_slice  <= {ARRAY_DIM{1'b0}};
            for (i = 0; i < ARRAY_DIM; i = i + 1) begin
                weight_reg[i] <= {ARRAY_DIM{1'b0}};
                shift_acc[i]  <= {ACC_WIDTH{1'b0}};
            end
        end else begin
            mem_write <= 1'b0;
            mem_read  <= 1'b0;

            case (state)
                IDLE: begin
                    if (cfg_start) begin
                        status_reg <= 2'b01; // BUSY
                        for (i = 0; i < ARRAY_DIM; i = i + 1)
                            shift_acc[i] <= {ACC_WIDTH{1'b0}};
                        bias_reg  <= cfg_array_size * ((16'd1 << cfg_precision) - 16'd1);
                        bit_plane <= cfg_precision - 3'd1;
                        row_idx   <= 6'd0;
                        state     <= cfg_reload_weights ? LOAD_WEIGHTS : FETCH_ACT;
                    end
                end

                // Pipelined weight load (2-cycle read latency):
                //   Cycle 0: issue read row 0
                //   Cycle 1: issue read row 1, row 0 registering
                //   Cycle 2: issue read row 2, latch row 0
                //   ...
                //   Total: cfg_array_size + 2 cycles
                LOAD_WEIGHTS: begin
                    if (row_idx > 6'd1) begin
                        for (i = 0; i < ARRAY_DIM; i = i + 1)
                            weight_reg[i][row_idx - 6'd2] <= mem_rdata[i];
                    end

                    if (row_idx < cfg_array_size) begin
                        mem_read <= 1'b1;
                        mem_addr <= cfg_weight_base + {4'd0, row_idx};
                        row_idx  <= row_idx + 6'd1;
                    end else if (row_idx == cfg_array_size) begin
                        row_idx <= row_idx + 6'd1;
                    end else begin
                        row_idx <= 6'd0;
                        state   <= FETCH_ACT;
                    end
                end

                // Fetch one activation bit-plane (2-cycle read latency)
                FETCH_ACT: begin
                    case (fetch_wait)
                        2'd0: begin
                            mem_read   <= 1'b1;
                            mem_addr   <= cfg_act_base + {7'd0, bit_plane};
                            fetch_wait <= 2'd1;
                        end
                        2'd1: begin
                            fetch_wait <= 2'd2;
                        end
                        2'd2: begin
                            fetch_wait <= 2'd0;
                            act_slice  <= mem_rdata[ARRAY_DIM-1:0];
                            state      <= COMPUTE;
                        end
                        default: fetch_wait <= 2'd0;
                    endcase
                end

                // Shift-accumulate
                // shift_acc[col] = (shift_acc[col] << 1) + popcount[col]
                COMPUTE: begin
                    for (i = 0; i < ARRAY_DIM; i = i + 1)
                        shift_acc[i] <= (shift_acc[i] << 1) + {{(ACC_WIDTH-6){1'b0}}, popcount[i]};

                    if (bit_plane > 3'd0) begin
                        bit_plane <= bit_plane - 3'd1;
                        state     <= FETCH_ACT;
                    end else begin
                        row_idx <= 6'd0;
                        state   <= STORE_RESULT;
                    end
                end

                // Write signed results
                // mem_wdata = 2*shift_acc[col] - bias_reg
                STORE_RESULT: begin
                    if (row_idx < cfg_array_size) begin
                        mem_wdata <= store_word;
                        mem_addr  <= cfg_result_base + {4'd0, row_idx};
                        mem_write <= 1'b1;
                        row_idx   <= row_idx + 6'd1;
                    end else begin
                        state <= DONE;
                    end
                end

                DONE: begin
                    status_reg <= 2'b10;
                    state      <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end
endmodule