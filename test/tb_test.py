# Minimal cocotb smoke test for TT CI (make-based flow).
# Full test suite runs via pytest (test/test.py).

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles


@cocotb.test()
async def test_reset(dut):
    """Verify chip comes out of reset with uo_out = 0."""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 1)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 1)
    assert int(dut.uo_out.value) == 0
