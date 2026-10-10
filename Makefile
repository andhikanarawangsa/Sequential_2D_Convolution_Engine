# Makefile - Sequential Convolution Engine

IVERILOG ?= iverilog
VVP      ?= vvp
PYTHON   ?= python3

RTL := src/conv2d_engine.v
TB  := tb/tb_conv2d.v
OUT := sim
SIM := $(OUT)/conv2d.vvp
LOG := $(OUT)/sim.log

.DEFAULT_GOAL := all

# Default: compile, simulate, and verify
all: check

# Compile the RTL and testbench
$(SIM): $(RTL) $(TB)
	@mkdir -p $(OUT)
	$(IVERILOG) -g2005 -Wall -o $@ $(RTL) $(TB)

# Run simulation and save the log
sim: $(SIM)
	$(VVP) $(SIM) | tee $(LOG)

# Compare simulation results against the Python golden model
check: sim
	$(PYTHON) scripts/golden_model.py --check $(LOG)

# Print the golden model results
golden:
	$(PYTHON) scripts/golden_model.py

# Open the generated waveform
wave:
	gtkwave $(OUT)/conv2d.vcd

# Check synthesis using Yosys (optional)
synth:
	yosys -p "read_verilog $(RTL); synth -top conv2d_engine; stat"

# Remove generated simulation artifacts
clean:
	rm -f $(SIM) $(OUT)/*.vcd $(LOG)

.PHONY: all sim check golden wave synth clean