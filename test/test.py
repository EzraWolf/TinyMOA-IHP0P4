import pytest
from pathlib import Path
from cocotb_test import simulator

PROJECT_DIR = Path(__file__).parent.resolve()
SRC_DIR = PROJECT_DIR.parent / "src"
SIM_BUILD = PROJECT_DIR / "sim_build"


def test_dcim_unit():
    simulator.run(
        verilog_sources=[
            str(SRC_DIR / "dcim.v"),
            str(SRC_DIR / "compressor_8.v"),
            str(PROJECT_DIR / "unit" / "dcim" / "tb_dcim.v"),
        ],
        toplevel="tb_dcim",
        module="unit.dcim.test_dcim",
        simulator="icarus",
        defines=["SINGLE_APPROX_COMPRESSOR"],
        sim_build=str(SIM_BUILD / "dcim"),
        python_search=[str(PROJECT_DIR)],
    )


def test_system_integration():
    simulator.run(
        verilog_sources=[
            str(SRC_DIR / "project.v"),
            str(SRC_DIR / "dcim.v"),
            str(SRC_DIR / "compressor_8.v"),
            str(PROJECT_DIR / "integration" / "system" / "tb_system.v"),
        ],
        toplevel="tb_system",
        module="integration.system.test_system",
        simulator="icarus",
        defines=["SINGLE_APPROX_COMPRESSOR"],
        sim_build=str(SIM_BUILD / "system"),
        python_search=[str(PROJECT_DIR)],
    )


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
