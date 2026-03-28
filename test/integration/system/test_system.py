# SPDX-FileCopyrightText: © 2026 Ezra Wolf
# SPDX-License-Identifier: Apache-2.0
#
# System integration tests for TinyMOA 8x8 DCIM.
# Tests only touch TT pins (ui_in, uo_out, uio_in, uio_out) to simulate
# how the external FPGA sees and controls the chip.

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles

ARRAY_DIM = 8
ACC_WIDTH = 6

# uio_out bit positions
UIO_STATE_MASK = 0x03
UIO_DONE_BIT = 3

# Wrapper FSM states (from project.v)
IDLE = 0
LOAD = 1
EXEC = 2
READ = 3


async def setup(dut):
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 1)
    dut.rst_n.value = 1


def get_state(dut):
    return int(dut.uio_out.value) & UIO_STATE_MASK


def get_done(dut):
    return (int(dut.uio_out.value) >> UIO_DONE_BIT) & 1


async def start(dut, precision=1, skip_load=False):
    """Pulse go on uio_in with config. FPGA drives uio during IDLE."""
    cfg = 1  # go bit
    if skip_load:
        cfg |= 1 << 1
    cfg |= (precision & 0x3) << 2
    dut.uio_in.value = cfg
    await RisingEdge(dut.clk)
    dut.uio_in.value = 0


async def send_weights(dut, rows):
    """Send ARRAY_DIM weight bytes on ui_in, one per cycle."""
    for row in rows:
        dut.ui_in.value = row & 0xFF
        await RisingEdge(dut.clk)
    dut.ui_in.value = 0


async def send_activation(dut, *planes):
    """Send activation bit-plane(s) on ui_in, one per cycle."""
    for act in planes:
        dut.ui_in.value = act & 0xFF
        await RisingEdge(dut.clk)
    dut.ui_in.value = 0


async def read_results(dut):
    """Read ARRAY_DIM result bytes from uo_out during READ phase."""
    results = []
    for _ in range(ARRAY_DIM):
        await RisingEdge(dut.clk)
        results.append(int(dut.uo_out.value))
    return results


@cocotb.test()
async def test_reset_state(dut):
    """After reset, wrapper is IDLE, uo_out = 0."""
    await setup(dut)
    assert get_state(dut) == IDLE
    assert int(dut.uo_out.value) == 0


@cocotb.test()
async def test_all_ones(dut):
    """Load 8x 0xFF weights, act=0xFF. All results should be equal and nonzero."""
    await setup(dut)
    await start(dut, precision=1)
    await send_weights(dut, [0xFF] * ARRAY_DIM)
    await send_activation(dut, 0xFF)
    results = await read_results(dut)
    expected = results[0]
    assert expected > 0, f"expected nonzero, got {expected}"
    for c, val in enumerate(results):
        assert val == expected, f"col {c}: got {val}, expected {expected}"


@cocotb.test()
async def test_all_zeros(dut):
    """Load 8x 0x00 weights, act=0xFF. All results should be 0."""
    await setup(dut)
    await start(dut, precision=1)
    await send_weights(dut, [0x00] * ARRAY_DIM)
    await send_activation(dut, 0xFF)
    results = await read_results(dut)
    for c, val in enumerate(results):
        assert val == 0, f"col {c}: expected 0, got {val}"


@cocotb.test()
async def test_weight_reuse(dut):
    """Run inference, then skip_load with different activation."""
    await setup(dut)

    # First inference
    await start(dut, precision=1)
    await send_weights(dut, [0xFF] * ARRAY_DIM)
    await send_activation(dut, 0xFF)
    r1 = await read_results(dut)

    # Second inference, skip weight load
    await start(dut, precision=1, skip_load=True)
    await send_activation(dut, 0x00)
    r2 = await read_results(dut)

    assert r1[0] > 0
    for c, val in enumerate(r2):
        assert val == 0, f"col {c}: expected 0 for act=0x00, got {val}"


@cocotb.test()
async def test_multibit(dut):
    """precision=2. Two activation planes. Verify accumulated result > single plane."""
    await setup(dut)
    await start(dut, precision=2)
    await send_weights(dut, [0xFF] * ARRAY_DIM)
    await send_activation(dut, 0xFF, 0xFF)
    r2 = await read_results(dut)

    # Compare against single-plane
    await setup(dut)
    await start(dut, precision=1)
    await send_weights(dut, [0xFF] * ARRAY_DIM)
    await send_activation(dut, 0xFF)
    r1 = await read_results(dut)

    for c in range(ARRAY_DIM):
        assert r2[c] > r1[c], (
            f"col {c}: 2-bit result {r2[c]} should exceed 1-bit {r1[c]}"
        )


@cocotb.test()
async def test_debug_state(dut):
    """Verify uio_out reflects FSM state transitions."""
    await setup(dut)
    assert get_state(dut) == IDLE
    await start(dut, precision=1)
    await RisingEdge(dut.clk)
    assert get_state(dut) == LOAD
