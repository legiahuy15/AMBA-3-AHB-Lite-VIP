# ==============================================================================
# File        : Makefile
# Project     : AMBA 3 AHB-Lite VIP
# Author      : Huy Le
# Description : QuestaSim flow: compile, run, parallel regression, coverage
#               merge and HTML report. Requires a POSIX shell.
# ==============================================================================

SHELL        := /bin/bash

# ==============================================================================
# 1. Path Definitions & File List
# ==============================================================================
SRC_DIR      = ../src
REPORT_DIR   = ./report
LOG_DIR      = $(REPORT_DIR)/logs
COV_DIR      = $(REPORT_DIR)/coverage
COV_HTML_DIR = $(REPORT_DIR)/cov_html

# Sources in compile order
SV_SOURCES = \
    $(SRC_DIR)/ahb_if.sv \
    $(SRC_DIR)/ahb_pkg.sv \
    $(SRC_DIR)/ahb_seq_pkg.sv \
    $(SRC_DIR)/ahb_test_pkg.sv \
    $(SRC_DIR)/sva/ahb_sva.sv \
    $(SRC_DIR)/tb_top.sv

# ==============================================================================
# 2. Configurable Variables (command-line overridable)
# ==============================================================================
TESTNAME      ?= ahb_read_after_write_test
# 'random' or an integer
SEED          ?= random
UVM_VERBOSITY ?= UVM_LOW
# Number of iterations per test in regression
NUM_RUNS      ?= 5
# 1: collect coverage, 0: disable
USE_COVERAGE  ?= 1

# Extra plusargs (e.g. PLUSARGS="+TIMEOUT_NS=2000000")
PLUSARGS      += +DUMP_VCD

# Regression test list
TEST_LIST     ?= ahb_sanity_test ahb_single_transfer_test ahb_incr_burst_test \
                 ahb_wrap_burst_test ahb_undefined_burst_test \
                 ahb_error_response_test ahb_reset_test ahb_busy_test \
                 ahb_idle_test ahb_wait_state_test ahb_read_after_write_test \
                 ahb_transfer_size_test ahb_byte_lane_test \
                 ahb_back_to_back_test ahb_passive_test \
                 ahb_random_stress_test

# ==============================================================================
# 3. Simulator Flags & Conditional Options
# ==============================================================================
VLOG_FLAGS = -sv -work work -timescale 1ns/1ps +incdir+$(SRC_DIR) -l $(LOG_DIR)/compile.log
VOPT_FLAGS = +acc -work work -l $(LOG_DIR)/optimize.log
VSIM_BASE_FLAGS = -c -work work
VSIM_FLAGS = $(VSIM_BASE_FLAGS) -l $(LOG_DIR)/run.log

# Coverage
ifeq ($(USE_COVERAGE),1)
    VLOG_FLAGS += -cover sbcet
    VOPT_FLAGS += -cover sbcet
    VSIM_BASE_FLAGS += -coverage
endif

# Random seed (shuf, else $RANDOM). ':=' so -sv_seed matches the .ucdb name
ifeq ($(SEED),random)
    GEN_SEED := $(shell shuf -i 1-99999999 -n 1 2>/dev/null || echo $$(( ($$RANDOM * 32768 + $$RANDOM) % 99999999 + 1 )))
else
    GEN_SEED := $(SEED)
endif

# ==============================================================================
# 4. Main Targets
# ==============================================================================
.PHONY: help compile optimize run regress merge_cov cov_report gui clean

help:
	@echo "========================================================================"
	@echo "                    AHB-Lite VIP Simulation Makefile                    "
	@echo "========================================================================"
	@echo "Usage:"
	@echo "  make run             - Run a single simulation (CLI mode)"
	@echo "  make gui             - Run a single simulation (GUI mode with wave window)"
	@echo "  make regress         - Run multiple simulation runs in parallel"
	@echo "  make merge_cov       - Merge all coverage databases (.ucdb)"
	@echo "  make cov_report      - Merge and generate HTML coverage report"
	@echo "  make clean           - Remove all generated files & simulation libraries"
	@echo ""
	@echo "Variables (Override via command line, e.g., 'make run TESTNAME=my_test'):"
	@echo "  TESTNAME=<name>      - Set UVM test name (default: $(TESTNAME))"
	@echo "  SEED=<int/random>    - Set simulation seed (default: $(SEED))"
	@echo "  UVM_VERBOSITY=<val>  - Set verbosity level (default: $(UVM_VERBOSITY))"
	@echo "  NUM_RUNS=<int>       - Iterations per test in regression (default: $(NUM_RUNS))"
	@echo "  USE_COVERAGE=<0/1>   - Enable/disable code coverage (default: $(USE_COVERAGE))"
	@echo "  PLUSARGS=\"...\"       - Extra plusargs, e.g. +TIMEOUT_NS=2000000"
	@echo "  TEST_LIST=\"t1 t2\"    - List of tests for regression (default: \"$(TEST_LIST)\")"
	@echo "========================================================================"

# Compile phase
compile:
	@mkdir -p $(LOG_DIR)
	@echo "[COMPILE] Creating library and compiling sources..."
	@vlib work
	@vmap work work
	vlog $(VLOG_FLAGS) $(SV_SOURCES)

# Optimize phase (vopt)
optimize: compile
	@echo "[OPTIMIZE] Generating optimized model 'opt_tb_top'..."
	vopt $(VOPT_FLAGS) tb_top -o opt_tb_top

# Single run (batch)
run: optimize
	@mkdir -p $(LOG_DIR) $(COV_DIR)
	@echo "[RUN] Executing: $(TESTNAME) | SEED=$(GEN_SEED)"
	vsim $(VSIM_FLAGS) -sv_seed $(GEN_SEED) \
		+UVM_TESTNAME=$(TESTNAME) \
		+UVM_VERBOSITY=$(UVM_VERBOSITY) \
		$(PLUSARGS) \
		-do "coverage save -onexit $(COV_DIR)/$(TESTNAME)_seed_$(GEN_SEED).ucdb; run -all; quit -f" \
		opt_tb_top

# Single run (GUI, wave.do)
gui: optimize
	@mkdir -p $(LOG_DIR)
	@echo "[GUI] Launching QuestaSim GUI for: $(TESTNAME)"
	vsim -gui -work work \
		+UVM_TESTNAME=$(TESTNAME) \
		+UVM_VERBOSITY=$(UVM_VERBOSITY) \
		$(PLUSARGS) \
		-do "do wave.do; run -all" \
		opt_tb_top &

# ==============================================================================
# 5. Regression (parallel with 'make -jN regress')
# ==============================================================================
# Targets <test>_run_<n>
REGRESS_TARGETS = $(foreach test,$(TEST_LIST),$(foreach idx,$(shell seq 1 $(NUM_RUNS)),$(test)_run_$(idx)))

regress: optimize
	@echo "[REGRESS] Starting parallel regression for tests: $(TEST_LIST)"
	@echo "          Running $(NUM_RUNS) iterations per test..."
	@mkdir -p $(LOG_DIR) $(COV_DIR)
	@$(MAKE) $(REGRESS_TARGETS)
	@echo "[REGRESS] Parallel regression complete! Run 'make cov_report' to generate coverage."

# One regression run; FAILED if UVM_ERROR or UVM_FATAL count is non-zero
$(REGRESS_TARGETS):
	@test_name=$(word 1,$(subst _run_, ,$@)); \
	run_idx=$(word 2,$(subst _run_, ,$@)); \
	seed=$$(shuf -i 1-99999999 -n 1 2>/dev/null || echo $$(( ($$RANDOM * 32768 + $$RANDOM) % 99999999 + 1 ))); \
	log_file=$(LOG_DIR)/$${test_name}_run_$${run_idx}_seed_$${seed}.log; \
	ucdb_file=$(COV_DIR)/$${test_name}_run_$${run_idx}_seed_$${seed}.ucdb; \
	echo "[REGRESS-RUN] $$test_name | Iteration: $$run_idx | Seed: $$seed"; \
	vsim $(VSIM_BASE_FLAGS) -sv_seed $$seed \
		+UVM_TESTNAME=$$test_name \
		+UVM_VERBOSITY=$(UVM_VERBOSITY) \
		$(PLUSARGS) \
		-l $$log_file \
		-do "coverage save -onexit $$ucdb_file; run -all; quit -f" \
		opt_tb_top; \
	if grep -q -E "UVM_ERROR\s*:\s*[1-9]" $$log_file || grep -q -E "UVM_FATAL\s*:\s*[1-9]" $$log_file; then \
		echo "              ==> $$test_name (Run $$run_idx) [FAILED] - Log: $$log_file"; \
	else \
		echo "              ==> $$test_name (Run $$run_idx) [PASSED]"; \
	fi

# ==============================================================================
# 6. Coverage Post-Processing
# ==============================================================================
# Merge UCDBs
merge_cov:
	@echo "[COV] Merging all coverage databases in $(COV_DIR) into $(COV_DIR)/merged.ucdb..."
	@mkdir -p $(COV_DIR)
	@if [ "$$(ls -A $(COV_DIR)/*.ucdb 2>/dev/null)" ]; then \
		vcover merge $(COV_DIR)/merged.ucdb $(COV_DIR)/*.ucdb; \
		echo "[COV] Coverage databases successfully merged."; \
	else \
		echo "[COV] ERROR: No .ucdb files found in $(COV_DIR) to merge!"; \
		exit 1; \
	fi

# HTML report
cov_report: merge_cov
	@echo "[COV] Generating HTML coverage report in $(COV_HTML_DIR)..."
	@mkdir -p $(COV_HTML_DIR)
	vcover report -html -htmldir $(COV_HTML_DIR) -verbose $(COV_DIR)/merged.ucdb
	@echo "========================================================================"
	@echo "[COV] HTML Report successfully generated!"
	@echo "      Open in browser: $(COV_HTML_DIR)/index.html"
	@echo "========================================================================"

# ==============================================================================
# 7. Clean up
# ==============================================================================
clean:
	@echo "[CLEAN] Removing all simulation outputs and libraries..."
	rm -rf work transcript vsim.wlf vsim_stacktrace.vstf modelsim.ini
	rm -rf $(REPORT_DIR)
	rm -rf *.vcd *.ucdb
