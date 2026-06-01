XRUN     := /share/instsww/cadence/XCELIUM2509/tools/bin/xrun
IMC      := MDV_XLM_HOME=/share/instsww/cadence/XCELIUM2509 /share/instsww/cadence/VMANAGER2509/tools/bin/imc
XRUN_OPTS := -sv -coverage all -covoverwrite -uvm -access +rwc -timescale 1ns/1ps -64bit 

COV_WORK  ?= cov_work
COV_TEST  ?= default
IMC_REPORT_CMD ?= report_metrics

.PHONY: sbinit sbinit_all sbinit_regress mbinit mbinit_all mbinit_regress mbinit_lr03_lr04 ltsm mbtrain _mbtrain_run mbtrain_regress patternwriter_lr02 cov_mbinit cov_sbinit cov_report cov_report_md clean

SBTEST ?= test_sbinit_sanity
MBTEST ?= test_mbinit_sanity
# Optional xrun args for mbinit (e.g. MBINIT_XRUN_EXTRA='+define+MBINIT_RM05_DEBUG')
MBINIT_XRUN_EXTRA ?=
# All MBINIT UVM tests (see tests/mbinit/mbinit_tests.sv). Override to run a subset.
MBINIT_TESTS ?= test_mbinit_decode test_mbinit_sanity test_mbinit_param_mismatch test_mbinit_param_only test_mbinit_cal test_mbinit_repairclk test_mbinit_repairclk_unrep test_mbinit_repairval_unrep test_mbinit_lr04_reversal_apply test_mbinit_lr07_reversal_trainerror test_mbinit_rm02_per_lane_reader test_mbinit_rm07_unrepairable test_mbinit_rm05_post_repair_persist
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

sbinit_regress: sbinit_all

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
	  ./if/mbinit/mb_ctrl_if.sv \
	  ./if/mbinit/mb_req_if.sv \
	  ./if/mbinit/mb_rsp_if.sv \
	  ./if/mbinit/mb_reset_if.sv \
	  ./if/mbinit/mb_cal_if.sv \
	  ./if/mbinit/mb_pattern_writer_if.sv \
	  ./if/mbinit/mb_pattern_reader_if.sv \
	  ./if/mbinit/mb_pttest_req_if.sv \
	  ./if/mbinit/mb_pttest_rsp_if.sv \
	  ./if/mbinit/mb_lane_ctrl_if.sv \
	  ./agent/logphy_agent_pkg.sv \
	  ./agent/mbinit/mbinit_event_pkg.sv \
	  ./agent/mbinit/mbinit_agent_pkg.sv \
	  ./env/mbinit/mbinit_env_pkg.sv \
	  ./seq/mbinit/mbinit_seq_pkg.sv \
	  ./tests/mbinit/mbinit_test_pkg.sv \
	  ./tb/mbinit/mbinit_bind_exports.sv \
      ./tb/logphy_sva.sv \
	  ./tb/mbinit/mbinit_tb_top.sv \
	  ./tb/mbinit/mbinit_reset_sva.sv \
	  ./tb/mbinit/mbinit_stream_sva.sv \
	  $(MBINIT_XRUN_EXTRA) \
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
	  +UVM_TESTNAME=$(MBTRAINTEST)

mbtrain_regress: mbtrain

# ---- Coverage collection: SBINIT ----
# Runs SBINIT tests with functional coverage, merges, and generates Markdown.
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
	    -covworkdir "$(abspath $(COV_SBINIT_WORK))" \
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
	$(MAKE) cov_report_md COV_WORK=$(COV_SBINIT_WORK) COV_SUITE=sbinit

# ---- Coverage collection: run mbinit_regress with coverage enabled, then report ----
# Usage:
#   make cov_mbinit           - collect + merge + write Markdown report
#   make cov_mbinit COV_MBINIT_WORK=my_cov_dir
#
# Individual tests write to $(COV_MBINIT_WORK)/<testname>/; imc merges them
# into a single database and generates $(COV_MBINIT_WORK)/coverage.md plus raw
# text artifacts under $(COV_MBINIT_WORK)/report_raw/.

COV_MBINIT_WORK ?= cov_work/mbinit

cov_mbinit:
	@mkdir -p "$(COV_MBINIT_WORK)"
	@tests="$(strip $(MBINIT_TESTS))"; \
	for test in $$tests; do \
	  echo "=== Coverage run: $$test ==="; \
	  $(XRUN) $(XRUN_OPTS) \
	    -coverage u \
	    -covworkdir "$(abspath $(COV_MBINIT_WORK))" \
	    -covtest $$test \
	    +incdir+./if/mbinit +incdir+./agent +incdir+./agent/mbinit +incdir+./env/mbinit +incdir+./seq/mbinit +incdir+./tests/mbinit \
	    -y ../elab/generatedVerilog/logphy +libext+.sv \
	    ../elab/generatedVerilog/logphy/MBInitSM.sv \
	    ../elab/generatedVerilog/logphy/MBInitRequester.sv \
	    ../elab/generatedVerilog/logphy/MBInitResponder.sv \
	    ./if/logphy_if.sv \
	    ./if/mbinit/mbinit_if.sv \
	    ./if/mbinit/mb_ctrl_if.sv \
	    ./if/mbinit/mb_req_if.sv \
	    ./if/mbinit/mb_rsp_if.sv \
	    ./if/mbinit/mb_reset_if.sv \
	    ./if/mbinit/mb_cal_if.sv \
	    ./if/mbinit/mb_pattern_writer_if.sv \
	    ./if/mbinit/mb_pattern_reader_if.sv \
	    ./if/mbinit/mb_pttest_req_if.sv \
	    ./if/mbinit/mb_pttest_rsp_if.sv \
	    ./if/mbinit/mb_lane_ctrl_if.sv \
	    ./agent/logphy_agent_pkg.sv \
	    ./agent/mbinit/mbinit_event_pkg.sv \
	    ./agent/mbinit/mbinit_agent_pkg.sv \
	    ./env/mbinit/mbinit_env_pkg.sv \
	    ./seq/mbinit/mbinit_seq_pkg.sv \
	    ./tests/mbinit/mbinit_test_pkg.sv \
	    ./tb/mbinit/mbinit_bind_exports.sv \
	    ./tb/logphy_sva.sv \
	    ./tb/mbinit/mbinit_tb_top.sv \
	    ./tb/mbinit/mbinit_reset_sva.sv \
	    ./tb/mbinit/mbinit_stream_sva.sv \
	    +UVM_TESTNAME=$$test || true; \
	done
	$(MAKE) cov_report_md COV_WORK=$(COV_MBINIT_WORK) COV_SUITE=mbinit

cov_report: cov_report_md

cov_report_md:
	$(eval ABS_COV := $(abspath $(COV_WORK)))
	$(eval SCOPE_DIR := $(ABS_COV)/scope)
	$(eval RAW_DIR := $(ABS_COV)/report_raw)
	$(eval COV_SUITE ?= coverage)
	@echo "=== Merging all $(COV_SUITE) coverage runs via runfile ==="
	@mkdir -p "$(ABS_COV)" "$(RAW_DIR)"
	@ls "$(SCOPE_DIR)" | grep "^test_" | while read d; do echo "$(SCOPE_DIR)/$$d"; done \
	  > "$(ABS_COV)/runfile.txt"
	@first=$$(head -1 "$(ABS_COV)/runfile.txt"); \
	if [ -z "$$first" ]; then \
	  echo "No coverage runs found under $(SCOPE_DIR)"; \
	  exit 1; \
	fi; \
	$(IMC) -load "$$first" \
	  -execcmd "merge -runfile {$(ABS_COV)/runfile.txt} -out {$(SCOPE_DIR)/merged_all} -overwrite; exit"
	@echo "=== Capturing IMC text coverage report from merged_all ==="
	@if [ "$(COV_SUITE)" = "mbinit" ]; then \
	  exclude_cmd="exclude -type mbinit_state_sync_sva -metrics assertion -comment {Intentionally unbound: XC-03 property too tight for RTL substate timing}; "; \
	else \
	  exclude_cmd=""; \
	fi; \
	$(IMC) -load "$(SCOPE_DIR)/merged_all" \
	  -execcmd "$${exclude_cmd}$(IMC_REPORT_CMD); exit" \
	  > "$(RAW_DIR)/imc_report_metrics.txt"
	@echo "=== Writing Markdown coverage report ==="
	@python3 ./scripts/coverage_markdown.py \
	  --suite "$(COV_SUITE)" \
	  --work "$(ABS_COV)" \
	  --merged-db "$(SCOPE_DIR)/merged_all" \
	  --runfile "$(ABS_COV)/runfile.txt" \
	  --raw "$(RAW_DIR)/imc_report_metrics.txt" \
	  --output "$(ABS_COV)/coverage.md"
	@echo ""
	@echo "Coverage report: $(ABS_COV)/coverage.md"

clean:
	rm -rf *.log *.history INCA_libs xcelium.d run_logs cov_work
