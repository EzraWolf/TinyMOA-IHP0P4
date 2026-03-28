/*
 * Copyright (c) 2026 Ezra Wolf
 * SPDX-License-Identifier: Apache-2.0
 *
 * TinyMOA 8-input popcount compressor
 *
 * Three modes selected via `define at elaboration:
 *
 *   SINGLE_APPROX_COMPRESSOR (DCIM-S):
 *     1 AND/OR approx level + exact popcount of 4. Range 0-4.
 *
 *   DOUBLE_APPROX_COMPRESSOR (DCIM-D):
 *     2 AND/OR approx levels + exact popcount of 2. Range 0-2.
 *     Very lossy at 8 inputs — use with caution.
 *
 *   Default / DCIM-E (Exact):
 *     Full 8:4 popcount. Zero RMSE.
 *
 * Reference: ISSCC 2022, Wang et al.
 * "DIMC: 2219TOPS/W 2569F2/b Digital In-Memory Computing Macro
 *  in 28nm Based on Approximate Arithmetic Hardware"
 */

`default_nettype none
`timescale 1ns / 1ps

module tinymoa_compressor_8 (
    input  [7:0] in,
    output [3:0] out
);

`ifdef SINGLE_APPROX_COMPRESSOR // DCIM-S

    wire lvl1_0 = in[0] & in[1];
    wire lvl1_1 = in[2] | in[3];
    wire lvl1_2 = in[4] & in[5];
    wire lvl1_3 = in[6] | in[7];

    // Level 2 (exact): popcount of 4 -> range 0-4, zero-extended to 4 bits
    assign out = (4'd0 + lvl1_0) + lvl1_1 + lvl1_2 + lvl1_3;

`elsif DOUBLE_APPROX_COMPRESSOR // DCIM-D

    wire lvl1_0 = in[0] & in[1];
    wire lvl1_1 = in[2] | in[3];
    wire lvl1_2 = in[4] & in[5];
    wire lvl1_3 = in[6] | in[7];

    wire lvl2_0 = lvl1_0 & lvl1_1;
    wire lvl2_1 = lvl1_2 | lvl1_3;

    // Level 3 (exact): popcount of 2 -> range 0-2, zero-extended to 4 bits
    assign out = {2'b0, (2'd0 + lvl2_0) + lvl2_1};

`else // DCIM-E (exact)

    // Full 8:4 popcount; 4'd0 widens the chain to prevent truncation
    assign out = (4'd0 + in[0]) + in[1] + in[2] + in[3]
                       + in[4] + in[5] + in[6] + in[7];
`endif

endmodule
