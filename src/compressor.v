/*
 * Copyright (c) 2026 Ezra Wolf
 * SPDX-License-Identifier: Apache-2.0
 *
 * TinyMOA 16-input popcount compressor
 *
 * Three modes selected via `define at elaboration:
 *
 *   SINGLE_APPROX_COMPRESSOR (DCIM-S):
 *     1 AND/OR approx level + exact popcount of 8. Range 0-8.
 *     ~40% fewer transistors, ~4.03% RMSE.
 *
 *   DOUBLE_APPROX_COMPRESSOR (DCIM-D):
 *     2 AND/OR approx levels + exact popcount of 4. Range 0-4.
 *     ~55% fewer transistors, ~6.76% RMSE.
 *
 *   Default / DCIM-E (Exact):
 *     Full 16:5 FA tree popcount. Zero RMSE.
 *
 * AND underestimates (1+1 -> 1), OR overestimates (0+1 -> 1).
 * Alternating AND/OR pairs partially cancel these errors.
 *
 * Reference: ISSCC 2022, Wang et al.
 * "DIMC: 2219TOPS/W 2569F2/b Digital In-Memory Computing Macro
 *  in 28nm Based on Approximate Arithmetic Hardware"
 */

`default_nettype none
`timescale 1ns / 1ps

module tinymoa_compressor (
    input  [15:0] in,
    output [4:0]  out
);

`ifdef SINGLE_APPROX_COMPRESSOR // DCIM-S

    // Level 1 (approx): 8 AND/OR pairs
    // AND underestimates. OR overestimates
    // Errors partially cancel out by altering pairs
    wire l1_0 = in[0]  & in[1];
    wire l1_1 = in[2]  | in[3];
    wire l1_2 = in[4]  & in[5];
    wire l1_3 = in[6]  | in[7];
    wire l1_4 = in[8]  & in[9];
    wire l1_5 = in[10] | in[11];
    wire l1_6 = in[12] & in[13];
    wire l1_7 = in[14] | in[15];

    // Level 2 (exact): popcount of 8 -> range 0-8, zero-extended to 5 bits
    assign out = {1'b0, (4'd0 + l1_0) + l1_1 + l1_2 + l1_3
                              + l1_4  + l1_5 + l1_6 + l1_7};

`elsif DOUBLE_APPROX_COMPRESSOR // DCIM-D

    // Level 1 (approx): 8 AND/OR pairs
    wire l1_0 = in[0]  & in[1];
    wire l1_1 = in[2]  | in[3];
    wire l1_2 = in[4]  & in[5];
    wire l1_3 = in[6]  | in[7];
    wire l1_4 = in[8]  & in[9];
    wire l1_5 = in[10] | in[11];
    wire l1_6 = in[12] & in[13];
    wire l1_7 = in[14] | in[15];

    // Level 2 (approx): 4 AND/OR pairs
    wire l2_0 = l1_0 & l1_1;
    wire l2_1 = l1_2 | l1_3;
    wire l2_2 = l1_4 & l1_5;
    wire l2_3 = l1_6 | l1_7;

    // Level 3 (exact): popcount of 4 -> range 0-4, zero-extended to 5 bits
    assign out = {2'b0, (3'd0 + l2_0) + l2_1 + l2_2 + l2_3};

`else // DCIM-E (exact)

    // Full 16:5 popcount; 5'd0 widens the chain to prevent truncation
    assign out = (5'd0 + in[0]) + in[1]  + in[2]  + in[3]
                       + in[4]  + in[5]  + in[6]  + in[7]
                       + in[8]  + in[9]  + in[10] + in[11]
                       + in[12] + in[13] + in[14] + in[15];
`endif

endmodule
