# SPDX-FileCopyrightText: © 2026 Ezra Wolf
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles

ARRAY_DIM = 8
ACC_WIDTH = 6


async def setup(dut):
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    dut.data_in.value = 0
    dut.wen.value = 0
    dut.execute.value = 0
    dut.acc_clear.value = 0
    dut.col_sel.value = 0
    dut.nrst.value = 0
    await ClockCycles(dut.clk, 1)
    dut.nrst.value = 1


async def load_weights(dut, rows):
    for row in rows:
        dut.data_in.value = row
        dut.wen.value = 1
        await RisingEdge(dut.clk)
    dut.wen.value = 0
    dut.data_in.value = 0
    await RisingEdge(dut.clk)


async def do_execute(dut, activation):
    dut.data_in.value = activation
    dut.execute.value = 1
    await RisingEdge(dut.clk)
    dut.execute.value = 0
    dut.data_in.value = 0
    await RisingEdge(dut.clk)


async def read_all(dut):
    results = []
    for c in range(ARRAY_DIM):
        dut.col_sel.value = c
        await RisingEdge(dut.clk)
        results.append(int(dut.result.value))
    return results


@cocotb.test()
async def test_reset(dut):
    await setup(dut)
    for c in range(ARRAY_DIM):
        dut.col_sel.value = c
        await RisingEdge(dut.clk)
        assert int(dut.result.value) == 0, f"col {c} not zero after reset"


@cocotb.test()
async def test_all_ones(dut):
    """weights=0xFF, act=0xFF. All XNOR bits = 1."""
    await setup(dut)
    await load_weights(dut, [0xFF] * ARRAY_DIM)
    await do_execute(dut, 0xFF)
    results = await read_all(dut)
    expected = results[0]
    assert expected > 0, f"expected nonzero, got {expected}"
    for c, val in enumerate(results):
        assert val == expected, f"col {c}: got {val}, expected {expected}"


@cocotb.test()
async def test_all_zeros(dut):
    """weights=0x00, act=0xFF. All XNOR bits = 0, popcount = 0."""
    await setup(dut)
    await load_weights(dut, [0x00] * ARRAY_DIM)
    await do_execute(dut, 0xFF)
    results = await read_all(dut)
    for c, val in enumerate(results):
        assert val == 0, f"col {c}: expected 0, got {val}"


@cocotb.test()
async def test_identity(dut):
    """Identity weight matrix with exact expected values per column.
    XNOR(weight_reg[col], 0xFF) has exactly 1 bit set per column.
    DCIM-S pairs: in[0]&in[1], in[2]|in[3], in[4]&in[5], in[6]|in[7].
    AND pair with one 1-bit: 0 if partner is 0. OR pair with one 1-bit: 1.
    bit 0 -> AND pair -> 0    bit 4 -> AND pair -> 0
    bit 1 -> AND pair -> 0    bit 5 -> AND pair -> 0
    bit 2 -> OR pair  -> 1    bit 6 -> OR pair  -> 1
    bit 3 -> OR pair  -> 1    bit 7 -> OR pair  -> 1
    """
    await setup(dut)
    await load_weights(dut, [1 << i for i in range(ARRAY_DIM)])
    await do_execute(dut, 0xFF)
    results = await read_all(dut)
    expected = [0, 0, 1, 1, 0, 0, 1, 1]
    for c in range(ARRAY_DIM):
        assert results[c] == expected[c], (
            f"col {c}: got {results[c]}, expected {expected[c]}"
        )


@cocotb.test()
async def test_multibit(dut):
    """Two executes. Verify shift-accumulate."""
    await setup(dut)
    await load_weights(dut, [0xFF] * ARRAY_DIM)
    await do_execute(dut, 0xFF)
    r1 = await read_all(dut)
    await do_execute(dut, 0xFF)
    r2 = await read_all(dut)
    for c in range(ARRAY_DIM):
        expected = (r1[c] << 1) + r1[c]
        assert r2[c] == expected, f"col {c}: got {r2[c]}, expected {expected}"


@cocotb.test()
async def test_weight_reuse(dut):
    """Same weights, different activations."""
    await setup(dut)
    await load_weights(dut, [0xFF] * ARRAY_DIM)
    await do_execute(dut, 0xFF)
    r1 = await read_all(dut)

    # Clear accumulators only, reuse cached weights
    dut.acc_clear.value = 1
    await ClockCycles(dut.clk, 1)
    dut.acc_clear.value = 0
    await do_execute(dut, 0x00)
    r2 = await read_all(dut)

    assert r1[0] > 0
    for c in range(ARRAY_DIM):
        assert r2[c] == 0, f"col {c}: expected 0 for act=0x00, got {r2[c]}"
