# SPDX-FileCopyrightText: © 2026 Ezra Wolf
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles


@cocotb.test()
async def test_reset(dut):
    """Verify DCIM comes out of reset in IDLE (dbg_state = 0)."""
    clock = Clock(dut.clk, 10, units="us")
    cocotb.start_soon(clock.start())

    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 1)

    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 1)

    dbg_state = dut.uo_out.value.integer & 0x07
    assert dbg_state == 0, f"Expected IDLE (0), got {dbg_state}"
