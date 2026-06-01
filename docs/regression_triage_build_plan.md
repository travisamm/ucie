# Automated Regression Triage — Build Plan (SBINIT template)

> This is the **decision-resolved implementation plan** for the automated
> regression triage system. The companion file
> `docs/automated_regression_triage_implementation_plan.md` is the original
> *requirements* (essentially the prompt); this file records the concrete
> architecture decisions, what already exists, and the exact build steps.
> **SBINIT is the template.** Build and prove it on SBINIT only; the design is
> deliberately structured so MBINIT/MBTRAIN drop in by extending one variable.

## Branch / workflow context
- Implement on the **`sbinit` branch** (SBINIT env is fully established here;
  MBINIT/MBTRAIN on this branch are pre-refactor and noisier — out of scope).
- The Makefile lives in `uvm/` and all suite flows already run from `uvm/`
  (`run_logs/` and `cov_work/` are under `uvm/`). Therefore **new scripts live in
  `uvm/scripts/`** and all spec-relative paths (`scripts/...`, `run_logs`,
  `regressions/latest`) are relative to `uvm/`, matching the spec verbatim.
- Everything here is **infrastructure only**: no RTL, no UVM checker behavior, no
  test intent changes. Triage *diagnoses*; it never *fixes* during triage mode.

## What already exists (DO NOT re-add)
- `make sbinit SBTEST=<t>` — single-test run. **Recipe already ends in `|| true`**,
  so its exit code is always 0 (consequence below).
- `make sbinit_all` — runs every test in `$(SBINIT_TESTS)`, writes per-test logs
  to `run_logs/sbinit/<test>.log` **and** `run_logs/sbinit/.results` with fields
  `TEST / STATUS / LOG / SIM_EXIT_STATUS / REASON / ERROR_EXCERPT / LOG_TAIL`.
  This `.results` file is the collector's primary input — it is already a
  near-perfect machine-ish format; we just need to parse + structure + cluster.
- `SBINIT_TESTS` (10 tests): `test_sbinit_decode, test_sbinit_sanity,
  test_sbinit_partner_not_ready, test_sbinit_early_req, test_sbinit_multiple_reqs,
  test_sbinit_timeout, test_sbinit_reset, test_sbinit_random,
  test_sbinit_req_backpressure, test_sbinit_rsp_backpressure`.
- `MBINIT_XRUN_EXTRA` knob — the naming convention to mirror for SBINIT/MBTRAIN.
- The error regex used by every suite runner (reuse it in Python for parity):
  `^(UVM_ERROR|UVM_FATAL)[[:space:]]+[^:]|UVM_(ERROR|FATAL)[[:space:]]*:[[:space:]]*[1-9][0-9]*|xrun:[[:space:]]+\*E|xmvlog:[[:space:]]+\*E|xmelab:[[:space:]]+\*E|\*E,`
- Root **`CLAUDE.md`** exists and is comprehensive → **append** a triage section,
  do not recreate.
- `.gitignore` already ignores `uvm/run_logs/` and `uvm/cov_work/`.

### Two facts that shape the design
1. **`make sbinit` ends in `|| true`** ⇒ `SIM_EXIT_STATUS` in the sbinit
   `.results` is *always 0*. Pass/fail is decided by the error-regex grep, and
   the runner records the verdict in the **`STATUS:`** field. So the collector
   must treat **`STATUS` as authoritative**, not `sim_exit_status`. (The `mbinit`
   single-test recipe has **no** `|| true`, so it can return nonzero — note this
   asymmetry for the later port; `nonzero_exit` will rarely fire for sbinit.)
2. `.gitignore` covers `run_logs/`/`cov_work/` but **not** `regressions/` — we
   add it (decision below).

## Architecture decisions (locked with the user)
1. **`regress` scope (MVP):** `sbinit` only. The new regression flow is wired
   under **`sbinit_regress`** (repurposed — it was only an alias to `sbinit_all`).
   The actual suite runner stays **`sbinit_all`** (unchanged). Structure:
   - `REGRESS_SUITES ?= sbinit_all`  (MVP default; later: `sbinit_all mbinit_all mbtrain`)
   - `regress` (top-level umbrella): for each suite in `$(REGRESS_SUITES)` run
     `$(MAKE) <suite> || true`, then collect, then build prompt.
   - `sbinit_regress`: `$(MAKE) regress REGRESS_SUITES=sbinit_all` (preserves the
     name; scopes to SBINIT). Porting later = append to `REGRESS_SUITES`; the
     collector already globs `run_logs/*/.results`.
2. **Output layout:** overwrite `regressions/latest/` every run. **No automatic
   history.** After the run, the *agent* decides whether the results are worth
   keeping and, if so, copies `regressions/latest` →
   `regressions/<descriptive_run_id>` where the name is derived from the dominant
   new failure (e.g. `new_timeout_fail`). Provide a convenience target
   `save_regress NAME=...` so the agent (Bash-enabled) can do it in one line.
3. **Git tracking:** **gitignore `regressions/`** (transient build output, like
   `run_logs/`).
4. **`agent_triage` safety:** **Bash-enabled by default** —
   `allowedTools = "Read,Grep,Glob,Bash"` so the agent can run representative
   reruns itself. No `Edit`/`Write` granted. The prompt explicitly forbids editing
   DUT/UVM source (Bash *could* technically write files; the prohibition is in the
   prompt and documented as a residual risk). `triage_prompt` is the safe
   prompt-only alternative that calls no AI tool.

## Files to create / change

### A. `uvm/scripts/collect_regression.py` (new, stdlib-only)
CLI: `python3 scripts/collect_regression.py --log-root run_logs --out regressions/latest`
- **Discover suites:** glob `<log-root>/*/.results`. Tolerate none → emit a valid
  *empty* summary (total/passed/failed = 0, empty lists). Never crash on missing
  dirs/files.
- **Parse each `.results`:** split into per-test records on `TEST:` blocks; pull
  `STATUS`, `LOG`, `SIM_EXIT_STATUS`, `REASON`, `ERROR_EXCERPT`, `LOG_TAIL`.
  STATUS is the verdict (fact #1). Suite name = parent dir of `.results`.
- **Read per-test log when available** (path from `LOG:`), bounded read (e.g. tail
  N KB + the `ERROR_EXCERPT` lines) to find the first error line + a short
  excerpt. Tolerate missing/relative log paths (resolve against `--log-root`'s
  parent / cwd).
- **Classify** each failure into a `category`:
  `compile_error` (`xmvlog: *E`), `elaboration_error` (`xmelab: *E`),
  `uvm_fatal` (`UVM_FATAL`), `uvm_error` (`UVM_ERROR`),
  `assertion_failure` (`*E,` SVA / `ASSERT` / `assertion`), `timeout`
  (`timeout`/`TEST_TIMEOUT`), `simulator_crash` (`xrun: *E` / `Segmentation`),
  `nonzero_exit` (status≠0 with no matched pattern), `unknown` (fallback).
  Order matters: check compile→elab→fatal→error→assert→timeout→crash→exit.
- **Signature** (for clustering), best available wins:
  1. Stable UVM ID in brackets: `UVM_ERROR ... [SOME_ID] ...` →
     `uvm_error:SOME_ID` (and `uvm_fatal:SOME_ID`). Prefer this always.
  2. SVA assertion name if present → `assert:<name>`.
  3. Compile/elab → `compile:<file>` / `elab:<module>` from the `*E` line.
  4. Fallback: take the first error line, **normalize** noise — strip absolute
     paths to basenames, replace timestamps/`@ <n>`/cycle counts/hex `0x...`/
     decimal line numbers with placeholders (`<T>`,`<N>`,`<HEX>`), collapse
     whitespace — then `cat:<category>|<normalized-first-40-chars>`.
- **Cluster:** group failures by `signature`; each cluster carries
  `count, category, suites[], tests[], representative_tests[], logs[]`.
- **Representative tests per cluster** (≤3): prefer names containing `sanity` /
  `decode` / focused feature tokens; include ≥1 test from each affected suite if
  the cluster spans suites; never select all failing tests.
- **Emit `summary.json`** with the schema from the requirements doc
  (`run_id, timestamp, git_sha, total, passed, failed, suites{}, failures[],
  clusters[]`). `run_id` = `<UTCtimestamp>_<git_sha8>`; `git_sha` via
  `git rev-parse --short HEAD` (tolerate non-git / failure → `"unknown"`).
- **Emit `failures.md`** — human-readable: header counts, a per-cluster section
  (signature, category, count, affected suites, representative tests + exact
  rerun commands, a trimmed excerpt), then a compact per-failure table.
- Robustness: pure stdlib (`argparse, json, os, re, glob, subprocess, datetime`);
  every file op guarded; exit 0 even with zero results.

### B. `uvm/scripts/build_triage_prompt.py` (new, stdlib-only)
CLI: `python3 scripts/build_triage_prompt.py --regression regressions/latest/summary.json --out regressions/latest/triage_prompt.md`
- Load `summary.json` (tolerate missing → write a prompt that says "no regression
  data found; run `make sbinit_regress` first").
- Emit `triage_prompt.md` — a self-contained agent prompt that states:
  - role = **DV regression triage agent** for a UCIe 3.0 LogPHY UVM env;
  - read `regressions/latest/summary.json` + only the relevant logs/source;
  - identify the **highest-impact cluster** (largest count / blocks the most);
  - distinguish **compile/elab** (fix-the-build) from **runtime
    scoreboard/assertion** failures;
  - select **≤5 representative reruns** (use the cluster's
    `representative_tests`); prefer targeted reruns over full regression;
  - give **exact Makefile commands** (`make sbinit SBTEST=<t>`; debug variant
    `make sbinit SBTEST=<t> SBINIT_XRUN_EXTRA='+define+TRIAGE_DEBUG'`);
  - suggest **files to inspect** and **extra debug observability** to add;
  - **do NOT edit RTL/UVM/DUT source** (Chisel/Scala/SystemVerilog) during
    triage; **do NOT `make clean`**; **do NOT rerun full regression repeatedly**;
  - **output a structured Markdown report** (cluster summary → root-cause
    hypothesis → chosen reruns + commands → files to inspect → next
    instrumentation);
  - **closing step:** if results are worth keeping, copy
    `regressions/latest` → `regressions/<descriptive_run_id>` (name from the
    dominant new failure, e.g. `new_timeout_fail`) via
    `make save_regress NAME=<descriptive_run_id>`.
  - Inline the live cluster summary from `summary.json` so the prompt is useful
    even pasted into a chat with no file access.

### C. `uvm/Makefile` (conservative additions only)
- Add knobs near `MBINIT_XRUN_EXTRA`:
  `SBINIT_XRUN_EXTRA ?=`, `MBTRAIN_XRUN_EXTRA ?=`, `XRUN_DEBUG_EXTRA ?=`.
  Wire `$(SBINIT_XRUN_EXTRA) $(XRUN_DEBUG_EXTRA)` into the `sbinit:` xrun
  (before `+UVM_TESTNAME`, after the SVA files, **keeping the trailing
  `|| true`**). Wire `$(MBTRAIN_XRUN_EXTRA) $(XRUN_DEBUG_EXTRA)` into
  `_mbtrain_run`, and `$(XRUN_DEBUG_EXTRA)` alongside the existing
  `$(MBINIT_XRUN_EXTRA)` in `mbinit:`. (`XRUN_DEBUG_EXTRA` = global escape hatch
  applied to all three.)
- Add vars: `REGRESS_OUT ?= regressions/latest`, `REGRESS_SUITES ?= sbinit_all`,
  `PYTHON ?= python3`, `CLAUDE ?= claude`.
- Add `.PHONY` entries: `regress sbinit_regress triage_prompt collect_regress
  agent_triage save_regress`.
- **`regress`:** `mkdir -p $(REGRESS_OUT)`; loop `$(REGRESS_SUITES)` with
  `$(MAKE) <suite> || true`; then `$(PYTHON) scripts/collect_regression.py
  --log-root run_logs --out $(REGRESS_OUT)`; then
  `$(PYTHON) scripts/build_triage_prompt.py --regression
  $(REGRESS_OUT)/summary.json --out $(REGRESS_OUT)/triage_prompt.md`.
- **`sbinit_regress`** (repurposed): `$(MAKE) regress REGRESS_SUITES=sbinit_all`.
- **`collect_regress` / `triage_prompt`** (prompt-only, no suite run, no AI):
  just run the two Python scripts against existing `run_logs`. (`triage_prompt`
  = alias of `collect_regress` for discoverability.)
- **`agent_triage`:** depends on `collect_regress`; if `command -v $(CLAUDE)` then
  run `$(CLAUDE) --bare -p "$$(cat $(REGRESS_OUT)/triage_prompt.md)"
  --allowedTools "Read,Grep,Glob,Bash" --output-format json
  > $(REGRESS_OUT)/agent_triage.json` (and/or `agent_triage.md`); else print a helpful
  message pointing at `triage_prompt.md`. **Never fail** if `claude` is absent or
  unauthenticated.
- **`save_regress`:** `cp -r $(REGRESS_OUT) regressions/$(NAME)` (guard empty
  `NAME`). Convenience for the agent's "worth keeping" step.

### D. `.gitignore` (repo root) — add `regressions/`.

### E. Docs
- **`docs/regression_triage.md`** (new): how to run full regression
  (`make sbinit_regress`), prompt-only (`make triage_prompt`), AI
  (`make agent_triage`); output locations; how clustering/signatures work; how to
  rerun representative tests; the descriptive-run-id save convention
  (`make save_regress NAME=...`); agentic safety rules. Include the
  **recommendation** (do *not* auto-apply) to give UVM errors **stable IDs** —
  e.g. `` `uvm_error("SCOREBOARD", "Mismatch detected") `` →
  `` `uvm_error("MBINIT_LR04_REVERSAL_MISMATCH", $sformatf(...)) `` — because
  bracketed IDs make `signature` clustering precise. Note the MVP is SBINIT-only
  and how to extend (`REGRESS_SUITES`).
- **`CLAUDE.md`** (append section): regression/triage commands, log locations,
  triage rules (no RTL/UVM edits in triage; no `make clean`; no repeated full
  reruns; cluster by first useful signature; pick representative tests; always
  give exact rerun commands), and the generated-RTL path convention.

## Validation (cheap, no full sim needed)
1. `cd uvm && python3 scripts/collect_regression.py --log-root run_logs --out regressions/latest`
   — with whatever `.results` exist (or none) → must produce valid
   `summary.json` + `failures.md` (empty-but-valid if no data).
2. `python3 scripts/build_triage_prompt.py --regression regressions/latest/summary.json --out regressions/latest/triage_prompt.md`.
3. `make -n regress`, `make -n sbinit_regress`, `make -n triage_prompt`,
   `make -n agent_triage` — confirm Makefile syntax / wiring.
4. Optional, only if quick: `make sbinit SBTEST=test_sbinit_sanity` to confirm
   the new `SBINIT_XRUN_EXTRA`/`XRUN_DEBUG_EXTRA` wiring didn't break the recipe.
5. Hand-craft a tiny synthetic `run_logs/sbinit/.results` with 1 PASS + 1 FAIL
   (e.g. a fake `[SB_TIMEOUT]` UVM_ERROR) to exercise classification + clustering
   + representative selection without running Xcelium.

## Acceptance (MVP)
- New targets: `regress`, `sbinit_regress` (repurposed), `triage_prompt`
  (+`collect_regress`), `agent_triage`, `save_regress`.
- New scripts: `uvm/scripts/{collect_regression,build_triage_prompt}.py`.
- Outputs on run: `regressions/latest/{summary.json,failures.md,triage_prompt.md}`.
- Docs: `docs/regression_triage.md` + appended `CLAUDE.md` section.
- Robust to: missing suites/logs, failing tests, absent `claude`, partial logs.
- Existing targets untouched in behavior: `sbinit_all`, `mbinit_all`, `mbtrain`,
  `cov_sbinit`, `cov_mbinit`, `cov_report`.

## Portability to MBINIT/MBTRAIN (next pass, not now)
- Add suites to `REGRESS_SUITES` (`sbinit_all mbinit_all mbtrain`); collector
  already globs all `run_logs/*/.results`. Representative-test heuristics and
  categories are suite-agnostic.
- Optionally add suite-name → feature-token hints for better representative
  selection.
- Recommend (separately) stabilizing UVM error IDs across MBINIT/MBTRAIN
  scoreboards to sharpen clustering.

## Assumptions / limitations
- SBINIT `SIM_EXIT_STATUS` is always 0 (recipe `|| true`); STATUS is the verdict.
- Clustering is heuristic; precision scales with stable UVM IDs (documented
  recommendation, not auto-applied).
- `agent_triage` Bash can technically write files; the no-edit rule is enforced by
  prompt instruction, not sandbox. `triage_prompt` is the zero-AI safe path.
- No history retention by default; the agent opts in via `save_regress`.
