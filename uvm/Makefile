XRUN     := /share/instsww/cadence/XCELIUM2509/tools/bin/xrun
IMC      := MDV_XLM_HOME=/share/instsww/cadence/XCELIUM2509 /share/instsww/cadence/VMANAGER2509/tools/bin/imc
XRUN_OPTS := -sv -coverage all -covoverwrite -uvm -access +rwc -timescale 1ns/1ps -64bit 

COV_WORK  ?= cov_work
COV_TEST  ?= default

.PHONY: sbinit sbinit_all sbinit_regress mbinit mbinit_all mbinit_regress mbinit_lr03_lr04 ltsm mbtrain _mbtrain_run mbtrain_regress patternwriter_lr02 cov_mbinit cov_sbinit cov_report clean regress collect_regress triage_prompt agent_triage save_regress

SBTEST ?= test_sbinit_sanity
MBTEST ?= test_mbinit_sanity
# Optional xrun args for mbinit (e.g. MBINIT_XRUN_EXTRA='+define+MBINIT_RM05_DEBUG')
MBINIT_XRUN_EXTRA ?=
# Optional xrun args for sbinit / mbtrain (mirror MBINIT_XRUN_EXTRA above).
SBINIT_XRUN_EXTRA ?=
MBTRAIN_XRUN_EXTRA ?=
# Global xrun escape hatch wired into sbinit, mbinit, and mbtrain at once
# (e.g. XRUN_DEBUG_EXTRA='+define+TRIAGE_DEBUG').
XRUN_DEBUG_EXTRA ?=

# ---- Regression triage (see docs/regression_triage.md) ----
# Output dir for the latest regression snapshot (overwritten each run).
REGRESS_OUT ?= regressions/latest
# Suites the top-level `regress` target loops over. MVP = SBINIT only; extend
# later by appending, e.g. REGRESS_SUITES = sbinit_all mbinit_all mbtrain.
REGRESS_SUITES ?= sbinit_all
PYTHON ?= python3
CLAUDE ?= claude
# All MBINIT UVM tests (see tests/mbinit/mbinit_tests.sv). Override to run a subset.
MBINIT_TESTS ?= test_mbinit_sanity test_mbinit_param_mismatch test_mbinit_param_only test_mbinit_cal test_mbinit_repairclk test_mbinit_repairclk_unrep test_mbinit_repairval_unrep test_mbinit_lr04_reversal_apply test_mbinit_lr07_reversal_trainerror test_mbinit_rm02_per_lane_reader test_mbinit_rm07_unrepairable test_mbinit_rm05_post_repair_persist
MBINIT_LOG_DIR ?= run_logs/mbinit
MBINIT_SUBMAKE ?= $(MAKE)
MBTRAINTEST ?=
#MBTRAIN_TESTS ?= test_mbtrain_valvref test_mbtrain_datavref test_mbtrain_sanity
MBTRAIN_TESTS ?= test_mbtrain_valvref test_mbtrain_datavref test_mbtrain_sanity test_mbtrain_speedidle test_mbtrain_speedidle_retrain test_mbtrain_speedidle_error test_mbtrain_rxclkcal test_mbtrain_dc2 test_mbtrain_linkspeed test_mbtrain_linkspeed_fail
MBTRAIN_LOG_DIR ?= run_logs/mbtrain
MBTRAIN_SUBMAKE ?= $(MAKE)

LTSTEST ?= test_ltsm_mbinit_repairval_trainerror

# ---- PatternWriter LR-02 (standalone, no UVM) — PERLANEID / cycles / per-lane data ----
PW_XRUN := /share/instsww/cadence/XCELIUM2509/tools/bin/xrun
patternwriter_lr02:
	$(PW_XRUN) -sv -64bit -timescale 1ns/1ps \
	  ../elab/generatedVerilog/logphy/CircularShiftRegister.sv \
	  ../elab/generatedVerilog/logphy/PatternWriter.sv \
	  ./tb/patternwriter/patternwriter_tb_lr02.sv \
	  +access+r

# ---- SBINIT ----
sbinit:
	$(XRUN) $(XRUN_OPTS) \
          +incdir+./if/sbinit +incdir+./agent/sbinit +incdir+./env/sbinit +incdir+./seq/sbinit +incdir+./tests/sbinit \
          -y ../elab/generatedVerilog/logphy +libext+.sv \
          ../elab/generatedVerilog/logphy/SBInitSM.sv \
          ./if/sbinit/sb_ctrl_if.sv \
          ./if/sbinit/sb_req_if.sv \
          ./if/sbinit/sb_rsp_if.sv \
          ./if/sbinit/sb_reset_if.sv \
          ./agent/sbinit/sbinit_event_pkg.sv \
          ./agent/sbinit/sbinit_agent_pkg.sv \
          ./env/sbinit/sbinit_env_pkg.sv \
          ./seq/sbinit/sbinit_seq_pkg.sv \
          ./tests/sbinit/sbinit_test_pkg.sv \
          ./tb/sbinit/logphy_tb_top.sv \
          ./tb/logphy_sva.sv \
          ./tb/sbinit/sbinit_stream_sva.sv \
          ./tb/sbinit/sbinit_reset_sva.sv \
          ./tb/sbinit/sbinit_persistence_sva.sv \
          $(SBINIT_XRUN_EXTRA) $(XRUN_DEBUG_EXTRA) \
          +UVM_TESTNAME=$(SBTEST) || true

SBINIT_LOG_DIR ?= run_logs/sbinit
SBINIT_SUBMAKE ?= $(MAKE)

sbinit_all:
	@mkdir -p "$(SBINIT_LOG_DIR)"; \
	tests="$(strip $(SBINIT_TESTS))"; \
	results_file="$(SBINIT_LOG_DIR)/.results"; \
	error_re='^(UVM_ERROR|UVM_FATAL)[[:space:]]+[^:]|UVM_(ERROR|FATAL)[[:space:]]*:[[:space:]]*[1-9][0-9]*|xrun:[[:space:]]+\*E|xmvlog:[[:space:]]+\*E|xmelab:[[:space:]]+\*E|\*E,'; \
	failed=0; \
	{ \
	  printf "SBINIT detailed results\n"; \
	  printf "Tests: %s\n\n" "$$tests"; \
	} > "$$results_file"; \
	printf "\nSBINIT results:\n"; \
	for test in $$tests; do \
	  log="$(SBINIT_LOG_DIR)/$$test.log"; \
	  if $(SBINIT_SUBMAKE) --no-print-directory sbinit SBTEST=$$test > "$$log" 2>&1; then \
	    sim_status=0; \
	  else \
	    sim_status=$$?; \
	  fi; \
	  if grep -Eq "$$error_re" "$$log"; then \
	    uvm_failure=1; \
	  else \
	    uvm_failure=0; \
	  fi; \
	  if [ $$sim_status -eq 0 ] && [ $$uvm_failure -eq 0 ]; then \
	    result=PASS; \
	  else \
	    result=FAIL; \
	    failed=1; \
	  fi; \
	  printf "  %-40s %s\n" "$$test" "$$result"; \
	  { \
	    printf "TEST: %s\n" "$$test"; \
	    printf "STATUS: %s\n" "$$result"; \
	    printf "LOG: %s\n" "$$log"; \
	    printf "SIM_EXIT_STATUS: %s\n" "$$sim_status"; \
	    if [ "$$result" = PASS ]; then \
	      printf "REASON: simulator exited 0 and no UVM_ERROR/UVM_FATAL lines were found\n"; \
	    else \
	      printf "REASON:"; \
	      if [ $$sim_status -ne 0 ]; then \
	        printf " simulator exited with status %s;" "$$sim_status"; \
	      fi; \
	      if [ $$uvm_failure -ne 0 ]; then \
	        printf " UVM_ERROR/UVM_FATAL present in log;"; \
	      fi; \
	      printf "\n"; \
	      error_lines="$$(grep -En "$$error_re" "$$log" | sed -n '1,80p')"; \
	      printf "ERROR_EXCERPT:\n"; \
	      if [ -n "$$error_lines" ]; then \
	        printf "%s\n" "$$error_lines"; \
	      else \
	        printf "<no UVM/Xcelium error regex matches; inspect full log for the nonzero exit cause>\n"; \
	      fi; \
	      printf "LOG_TAIL:\n"; \
	      tail -n 40 "$$log"; \
	    fi; \
	    printf "\n"; \
	  } >> "$$results_file"; \
	done; \
	printf "\nDetailed results: %s\n" "$$results_file"; \
	exit $$failed

# Repurposed: run the SBINIT regression flow (suite run -> collect -> prompt).
# Was an alias for sbinit_all; now scopes the generic `regress` flow to SBINIT.
sbinit_regress:
	$(MAKE) regress REGRESS_SUITES=sbinit_all

# ---- MBINIT ----
mbinit:
	$(XRUN) $(XRUN_OPTS) \
	  +incdir+./if/mbinit +incdir+./agent +incdir+./agent/mbinit +incdir+./env/mbinit +incdir+./seq/mbinit +incdir+./tests/mbinit \
	  -y ../elab/generatedVerilog/logphy +libext+.sv \
	  ../elab/generatedVerilog/logphy/MBInitSM.sv \
	  ../elab/generatedVerilog/logphy/MBInitRequester.sv \
	  ../elab/generatedVerilog/logphy/MBInitResponder.sv \
	  ./if/logphy_if.sv \
	  ./if/mbinit/mbinit_if.sv \
	  ./agent/logphy_agent_pkg.sv \
	  ./agent/mbinit/mbinit_agent_pkg.sv \
	  ./env/mbinit/mbinit_env_pkg.sv \
	  ./seq/mbinit/mbinit_seq_pkg.sv \
	  ./tests/mbinit/mbinit_test_pkg.sv \
	  ./tb/mbinit/mbinit_bind_exports.sv \
      ./tb/logphy_sva.sv \
	  ./tb/mbinit/mbinit_tb_top.sv \
	  $(MBINIT_XRUN_EXTRA) $(XRUN_DEBUG_EXTRA) \
	  +UVM_TESTNAME=$(MBTEST)

# LR-03/04/06/07: sanity (LR-03, LR-06 on happy path), LR-04 retry, LR-07 double-fail error.
mbinit_lr03_lr04:
	$(MAKE) mbinit MBTEST=test_mbinit_sanity
	$(MAKE) mbinit MBTEST=test_mbinit_lr04_reversal_apply
	$(MAKE) mbinit MBTEST=test_mbinit_lr07_reversal_trainerror

# Run every test in $(MBINIT_TESTS); logs under $(MBINIT_LOG_DIR); exit 1 if any fail.
mbinit_all:
	@mkdir -p "$(MBINIT_LOG_DIR)"; \
	tests="$(strip $(MBINIT_TESTS))"; \
	results_file="$(MBINIT_LOG_DIR)/.results"; \
	error_re='^(UVM_ERROR|UVM_FATAL)[[:space:]]+[^:]|UVM_(ERROR|FATAL)[[:space:]]*:[[:space:]]*[1-9][0-9]*|xrun:[[:space:]]+\*E|xmvlog:[[:space:]]+\*E|xmelab:[[:space:]]+\*E|\*E,'; \
	failed=0; \
	{ \
	  printf "MBINIT detailed results\n"; \
	  printf "Tests: %s\n\n" "$$tests"; \
	} > "$$results_file"; \
	printf "\nMBINIT results:\n"; \
	for test in $$tests; do \
	  log="$(MBINIT_LOG_DIR)/$$test.log"; \
	  if $(MBINIT_SUBMAKE) --no-print-directory mbinit MBTEST=$$test > "$$log" 2>&1; then \
	    sim_status=0; \
	  else \
	    sim_status=$$?; \
	  fi; \
	  if grep -Eq "$$error_re" "$$log"; then \
	    uvm_failure=1; \
	  else \
	    uvm_failure=0; \
	  fi; \
	  if [ $$sim_status -eq 0 ] && [ $$uvm_failure -eq 0 ]; then \
	    result=PASS; \
	  else \
	    result=FAIL; \
	    failed=1; \
	  fi; \
	  printf "  %-36s %s\n" "$$test" "$$result"; \
	  { \
	    printf "TEST: %s\n" "$$test"; \
	    printf "STATUS: %s\n" "$$result"; \
	    printf "LOG: %s\n" "$$log"; \
	    printf "SIM_EXIT_STATUS: %s\n" "$$sim_status"; \
	    if [ "$$result" = PASS ]; then \
	      printf "REASON: simulator exited 0 and no UVM_ERROR/UVM_FATAL lines were found\n"; \
	    else \
	      printf "REASON:"; \
	      if [ $$sim_status -ne 0 ]; then \
	        printf " simulator exited with status %s;" "$$sim_status"; \
	      fi; \
	      if [ $$uvm_failure -ne 0 ]; then \
	        printf " UVM_ERROR/UVM_FATAL present in log;"; \
	      fi; \
	      printf "\n"; \
	      error_lines="$$(grep -En "$$error_re" "$$log" | sed -n '1,80p')"; \
	      printf "ERROR_EXCERPT:\n"; \
	      if [ -n "$$error_lines" ]; then \
	        printf "%s\n" "$$error_lines"; \
	      else \
	        printf "<no UVM/Xcelium error regex matches; inspect full log for the nonzero exit cause>\n"; \
	      fi; \
	      printf "LOG_TAIL:\n"; \
	      tail -n 40 "$$log"; \
	    fi; \
	    printf "\n"; \
	  } >> "$$results_file"; \
	done; \
	printf "\nDetailed results: %s\n" "$$results_file"; \
	exit $$failed

mbinit_regress: mbinit_all

# ---- LinkTrainingSM (MBINIT + TRAINERROR SB) — sources under ./ltsm/ ----
ltsm:
	$(XRUN) $(XRUN_OPTS) \
	  +incdir+./ltsm/if +incdir+./ltsm/tb +incdir+./ltsm/tests \
	  -y ../elab/generatedVerilog/logphy +libext+.sv \
	  ../elab/generatedVerilog/logphy/LinkTrainingSM.sv \
	  ./ltsm/if/ltsm_obs_if.sv \
	  ./ltsm/tb/ltsm_fused_sb_partner.sv \
	  ./ltsm/tests/ltsm_test_pkg.sv \
	  ./ltsm/tb/ltsm_tb_top.sv \
	  +UVM_TESTNAME=$(LTSTEST)

# ---- MBTRAIN ----
mbtrain:
	@mkdir -p "$(MBTRAIN_LOG_DIR)"; \
	tests="$(if $(strip $(MBTRAINTEST)),$(strip $(MBTRAINTEST)),$(strip $(MBTRAIN_TESTS)))"; \
	results_file="$(MBTRAIN_LOG_DIR)/.results"; \
	error_re='^(UVM_ERROR|UVM_FATAL)[[:space:]]+[^:]|UVM_(ERROR|FATAL)[[:space:]]*:[[:space:]]*[1-9][0-9]*|xrun:[[:space:]]+\*E|xmvlog:[[:space:]]+\*E|xmelab:[[:space:]]+\*E|\*E,'; \
	failed=0; \
	{ \
	  printf "MBTRAIN detailed results\n"; \
	  printf "Tests: %s\n\n" "$$tests"; \
	} > "$$results_file"; \
	printf "\nMBTRAIN results:\n"; \
	for test in $$tests; do \
	  log="$(MBTRAIN_LOG_DIR)/$$test.log"; \
	  if $(MBTRAIN_SUBMAKE) --no-print-directory _mbtrain_run MBTRAINTEST=$$test > "$$log" 2>&1; then \
	    sim_status=0; \
	  else \
	    sim_status=$$?; \
	  fi; \
	  if grep -Eq "$$error_re" "$$log"; then \
	    uvm_failure=1; \
	  else \
	    uvm_failure=0; \
	  fi; \
	  if [ $$sim_status -eq 0 ] && [ $$uvm_failure -eq 0 ]; then \
	    result=PASS; \
	  else \
	    result=FAIL; \
	    failed=1; \
	  fi; \
	  printf "  %-36s %s\n" "$$test" "$$result"; \
	  { \
	    printf "TEST: %s\n" "$$test"; \
	    printf "STATUS: %s\n" "$$result"; \
	    printf "LOG: %s\n" "$$log"; \
	    printf "SIM_EXIT_STATUS: %s\n" "$$sim_status"; \
	    if [ "$$result" = PASS ]; then \
	      printf "REASON: simulator exited 0 and no UVM_ERROR/UVM_FATAL lines were found\n"; \
	    else \
	      printf "REASON:"; \
	      if [ $$sim_status -ne 0 ]; then \
	        printf " simulator exited with status %s;" "$$sim_status"; \
	      fi; \
	      if [ $$uvm_failure -ne 0 ]; then \
	        printf " UVM_ERROR/UVM_FATAL present in log;"; \
	      fi; \
	      printf "\n"; \
	      error_lines="$$(grep -En "$$error_re" "$$log" | sed -n '1,80p')"; \
	      printf "ERROR_EXCERPT:\n"; \
	      if [ -n "$$error_lines" ]; then \
	        printf "%s\n" "$$error_lines"; \
	      else \
	        printf "<no UVM/Xcelium error regex matches; inspect full log for the nonzero exit cause>\n"; \
	      fi; \
	      printf "LOG_TAIL:\n"; \
	      tail -n 40 "$$log"; \
	    fi; \
	    printf "\n"; \
	  } >> "$$results_file"; \
	done; \
	printf "\nDetailed results: %s\n" "$$results_file"; \
	exit $$failed

_mbtrain_run:
	$(XRUN) $(XRUN_OPTS) \
	  +incdir+./if/mbtrain +incdir+./agent +incdir+./agent/mbtrain +incdir+./env/mbtrain +incdir+./seq/mbtrain +incdir+./tests/mbtrain \
	  -y ../elab/generatedVerilog/logphy +libext+.sv \
	  ../elab/generatedVerilog/logphy/MBTrainSM.sv \
	  ./if/logphy_if.sv \
	  ./if/mbtrain/mbtrain_if.sv \
	  ./agent/logphy_agent_pkg.sv \
	  ./agent/mbtrain/mbtrain_agent_pkg.sv \
	  ./env/mbtrain/mbtrain_env_pkg.sv \
	  ./seq/mbtrain/mbtrain_seq_pkg.sv \
	  ./tests/mbtrain/mbtrain_test_pkg.sv \
	  ./tb/mbtrain/mbtrain_tb_top.sv \
	  $(MBTRAIN_XRUN_EXTRA) $(XRUN_DEBUG_EXTRA) \
	  +UVM_TESTNAME=$(MBTRAINTEST)

mbtrain_regress: mbtrain

# ---- Coverage collection: SBINIT ----
# Runs all 5 SBINIT tests with functional coverage, merges, and generates an HTML report.
# test_sbinit_timeout covers the error path; it may run long but is included for completeness.
# Note: cp_fsm_error.error will remain 0 until the RTL hardcode in SBInit.scala is fixed.
#
# Usage:
#   make cov_sbinit
#   make cov_sbinit COV_SBINIT_WORK=my_dir

SBINIT_TESTS ?= test_sbinit_decode test_sbinit_sanity test_sbinit_partner_not_ready test_sbinit_early_req test_sbinit_multiple_reqs test_sbinit_timeout test_sbinit_reset test_sbinit_random test_sbinit_req_backpressure test_sbinit_rsp_backpressure
COV_SBINIT_WORK ?= cov_work/sbinit

cov_sbinit:
	@mkdir -p "$(COV_SBINIT_WORK)"
	@tests="$(strip $(SBINIT_TESTS))"; \
	for test in $$tests; do \
	  echo "=== Coverage run: $$test ==="; \
	  $(XRUN) $(XRUN_OPTS) \
	    -coverage u \
	    -covworkdir $(abspath $(COV_SBINIT_WORK)) \
	    -covtest $$test \
	    +incdir+./if/sbinit +incdir+./agent/sbinit +incdir+./env/sbinit +incdir+./seq/sbinit +incdir+./tests/sbinit \
	    -y ../elab/generatedVerilog/logphy +libext+.sv \
	    ../elab/generatedVerilog/logphy/SBInitSM.sv \
	    ./if/sbinit/sb_ctrl_if.sv \
	    ./if/sbinit/sb_req_if.sv \
	    ./if/sbinit/sb_rsp_if.sv \
	    ./if/sbinit/sb_reset_if.sv \
	    ./agent/sbinit/sbinit_event_pkg.sv \
	    ./agent/sbinit/sbinit_agent_pkg.sv \
	    ./env/sbinit/sbinit_env_pkg.sv \
	    ./seq/sbinit/sbinit_seq_pkg.sv \
	    ./tests/sbinit/sbinit_test_pkg.sv \
	    ./tb/sbinit/logphy_tb_top.sv \
	    ./tb/logphy_sva.sv \
	    ./tb/sbinit/sbinit_stream_sva.sv \
	    ./tb/sbinit/sbinit_reset_sva.sv \
	    ./tb/sbinit/sbinit_persistence_sva.sv \
	    +UVM_TESTNAME=$$test || true; \
	done
	$(MAKE) cov_report COV_WORK=$(COV_SBINIT_WORK)

# ---- Coverage collection: run mbinit_regress with coverage enabled, then report ----
# Usage:
#   make cov_mbinit           — collect + merge + open HTML report
#   make cov_mbinit COV_WORK=my_cov_dir
#
# Individual tests write to $(COV_WORK)/<testname>/; imc merges them into a
# single database and generates an HTML report under $(COV_WORK)/report/.
#
# The HTML report index is at $(COV_WORK)/report/index.html — open in a browser.

COV_MBINIT_WORK ?= cov_work/mbinit

cov_mbinit:
	@mkdir -p "$(COV_MBINIT_WORK)"
	@tests="$(strip $(MBINIT_TESTS))"; \
	for test in $$tests; do \
	  echo "=== Coverage run: $$test ==="; \
	  $(XRUN) $(XRUN_OPTS) \
	    -coverage u \
	    -covworkdir $(abspath $(COV_MBINIT_WORK)) \
	    -covtest $$test \
	    +incdir+./if/mbinit +incdir+./agent +incdir+./agent/mbinit +incdir+./env/mbinit +incdir+./seq/mbinit +incdir+./tests/mbinit \
	    -y ../elab/generatedVerilog/logphy +libext+.sv \
	    ../elab/generatedVerilog/logphy/MBInitSM.sv \
	    ../elab/generatedVerilog/logphy/MBInitRequester.sv \
	    ../elab/generatedVerilog/logphy/MBInitResponder.sv \
	    ./if/logphy_if.sv \
	    ./if/mbinit/mbinit_if.sv \
	    ./agent/logphy_agent_pkg.sv \
	    ./agent/mbinit/mbinit_agent_pkg.sv \
	    ./env/mbinit/mbinit_env_pkg.sv \
	    ./seq/mbinit/mbinit_seq_pkg.sv \
	    ./tests/mbinit/mbinit_test_pkg.sv \
	    ./tb/mbinit/mbinit_bind_exports.sv \
	    ./tb/logphy_sva.sv \
	    ./tb/mbinit/mbinit_tb_top.sv \
	    +UVM_TESTNAME=$$test || true; \
	done
	$(MAKE) cov_report COV_WORK=$(COV_MBINIT_WORK)

cov_report:
	$(eval ABS_COV := $(abspath $(COV_WORK)))
	$(eval SCOPE_DIR := $(ABS_COV)/scope)
	$(eval MERGED := $(ABS_COV)/merged)
	@echo "=== Merging all runs via runfile ==="
	@first=""; \
	ls $(SCOPE_DIR) | grep "^test_" | while read d; do echo "$(SCOPE_DIR)/$$d"; done \
	  > $(ABS_COV)/runfile.txt; \
	first=$$(head -1 $(ABS_COV)/runfile.txt); \
	$(IMC) -load "$$first" \
	  -execcmd "merge -runfile $(ABS_COV)/runfile.txt -out $(SCOPE_DIR)/merged_all -overwrite; exit"
	@echo "=== Generating HTML report from merged_all ==="
	@mkdir -p $(ABS_COV)/report
	$(IMC) -load $(SCOPE_DIR)/merged_all \
	  -execcmd "exclude -type mbinit_state_sync_sva -metrics assertion -comment {Intentionally unbound: XC-03 property too tight for RTL substate timing}; report_metrics -overwrite -out $(ABS_COV)/report; exit"
	@echo ""
	@echo "Coverage report: $(ABS_COV)/report/index.html"

# ---- Regression triage ----
# Full flow:    make regress              (run suites -> collect -> prompt)
# SBINIT only:  make sbinit_regress       (= make regress REGRESS_SUITES=sbinit_all)
# Prompt only:  make triage_prompt        (collect + prompt from existing run_logs, no sim, no AI)
# AI triage:    make agent_triage         (collect + prompt, then run claude if available)
# Archive:      make save_regress NAME=<id>
# Outputs land in $(REGRESS_OUT)/{summary.json,failures.md,triage_prompt.md}.

# Top-level umbrella: run each suite in REGRESS_SUITES (continue past failures),
# then collect + build the triage prompt. Extend by appending to REGRESS_SUITES.
regress:
	@mkdir -p $(REGRESS_OUT)
	@for suite in $(REGRESS_SUITES); do \
	  echo "=== regress: $$suite ==="; \
	  $(MAKE) $$suite || true; \
	done
	$(PYTHON) scripts/collect_regression.py --log-root run_logs --out $(REGRESS_OUT)
	$(PYTHON) scripts/build_triage_prompt.py --regression $(REGRESS_OUT)/summary.json --out $(REGRESS_OUT)/triage_prompt.md
	@echo "Regression artifacts: $(REGRESS_OUT)/{summary.json,failures.md,triage_prompt.md}"

# Prompt-only: rebuild summary.json/failures.md/triage_prompt.md from whatever
# run_logs already exist. No simulation, no AI. triage_prompt is an alias.
collect_regress:
	@mkdir -p $(REGRESS_OUT)
	$(PYTHON) scripts/collect_regression.py --log-root run_logs --out $(REGRESS_OUT)
	$(PYTHON) scripts/build_triage_prompt.py --regression $(REGRESS_OUT)/summary.json --out $(REGRESS_OUT)/triage_prompt.md
	@echo "Triage prompt: $(REGRESS_OUT)/triage_prompt.md"

triage_prompt: collect_regress

# Optional AI triage. Builds the prompt, then runs the Claude CLI IF present.
# Never fails when claude is absent or unauthenticated — it points at the prompt.
agent_triage: collect_regress
	@if command -v $(CLAUDE) >/dev/null 2>&1; then \
	  echo "=== agent_triage: running '$(CLAUDE)' ==="; \
	  if $(CLAUDE) --bare -p "$$(cat $(REGRESS_OUT)/triage_prompt.md)" \
	       --allowedTools "Read,Grep,Glob,Bash" \
	       --output-format json \
	       > $(REGRESS_OUT)/agent_triage.json 2> $(REGRESS_OUT)/agent_triage.err; then \
	    echo "agent_triage: wrote $(REGRESS_OUT)/agent_triage.json"; \
	  else \
	    echo "agent_triage: '$(CLAUDE)' returned nonzero (unauthenticated?); see $(REGRESS_OUT)/agent_triage.err"; \
	    echo "agent_triage: the prompt is ready at $(REGRESS_OUT)/triage_prompt.md — paste it into Claude Code / ChatGPT."; \
	  fi; \
	else \
	  echo "agent_triage: '$(CLAUDE)' not found on PATH; skipping AI step."; \
	  echo "agent_triage: the prompt is ready at $(REGRESS_OUT)/triage_prompt.md — paste it into Claude Code / ChatGPT,"; \
	  echo "agent_triage: or install the Claude CLI and re-run 'make agent_triage'."; \
	fi

# Archive the latest snapshot under a descriptive name (the agent's opt-in step).
save_regress:
	@if [ -z "$(strip $(NAME))" ]; then \
	  echo "save_regress: set NAME=<descriptive_run_id>, e.g. make save_regress NAME=new_timeout_fail"; \
	  exit 1; \
	fi
	cp -r $(REGRESS_OUT) regressions/$(NAME)
	@echo "Saved $(REGRESS_OUT) -> regressions/$(NAME)"

clean:
	rm -rf *.log *.history INCA_libs xcelium.d run_logs cov_work
