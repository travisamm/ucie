You are helping me set up automated regression triage infrastructure for a complex SystemVerilog/UVM verification environment for an open-source UCIe 3.0 LogPHY implementation.

You have full access to the codebase and are able to run existing Makefile targets e.g. make sbinit, make sbinit_all, etc. Your job is to inspect the repository, understand the existing Makefile/test structure, and implement a practical regression triage system that can later be used by Claude or another agentic AI workflow.

Important: Do **not** modify RTL/design logic or UVM checker behavior as part of this task unless absolutely necessary. This task is about infrastructure, parsing, summarization, and agent-ready triage. Do not attempt to “fix” failing tests yet.

## Current project context

This repo verifies UCIe 3.0 LogPHY behavior using UVM/SVA. The major suites include:

* SBINIT: Sideband Initialization
* MBINIT: Mainband Initialization
* MBTRAIN: Mainband Training
* LTSM / LinkTrainingSM

The existing Makefile already contains targets similar to:

* `make sbinit`
* `make sbinit_all`
* `make sbinit_regress`
* `make mbinit`
* `make mbinit_all`
* `make mbinit_regress`
* `make mbtrain`
* `make mbtrain_regress`
* `make ltsm`
* coverage targets such as `cov_sbinit`, `cov_mbinit`, and `cov_report_md`

The suite-level targets write logs under directories like:

* `run_logs/sbinit/*.log`
* `run_logs/mbinit/*.log`
* `run_logs/mbtrain/*.log`

They also write `.results` files such as:

* `run_logs/sbinit/.results`
* `run_logs/mbinit/.results`
* `run_logs/mbtrain/.results`

Those `.results` files contain fields like:

* `TEST:`
* `STATUS:`
* `LOG:`
* `SIM_EXIT_STATUS:`
* `REASON:`
* `ERROR_EXCERPT:`
* `LOG_TAIL:`

The goal is to turn this into a structured regression database plus an AI triage workflow.

## Desired final workflow

I want to be able to run something like:

```bash
make regress
```

and get:

```text
regressions/latest/summary.json
regressions/latest/failures.md
regressions/latest/triage_prompt.md
```

Then I want to be able to run something like:

```bash
make agent_triage
```

which should prepare an agent-ready triage prompt, and if a Claude CLI or another agent CLI is available, optionally run it. The flow should still be useful even if the AI CLI is not installed.

The long-term target workflow is:

1. Run full regression.
2. Parse all suite `.results` files and raw logs.
3. Produce a machine-readable `summary.json`.
4. Cluster failures by likely common root-cause signature.
5. Generate a human-readable `failures.md`.
6. Generate a Claude/agent prompt that asks the agent to:

   * identify the highest-impact failure cluster,
   * select at most ~5 representative tests to rerun,
   * explain the likely shared root cause,
   * suggest exact rerun commands,
   * suggest files to inspect,
   * suggest extra debug visibility to add,
   * avoid random full reruns,
   * avoid editing RTL/UVM source during triage mode. Do NOT edit Chisel/Scala/SystemVerilog source for the DUT.

## Implementation tasks

Please implement the following.

### 1. Inspect the current Makefile and preserve existing behavior

Before editing, inspect the Makefile carefully.

Preserve all existing targets and behavior unless there is a clear bug. Avoid breaking existing commands such as:

```bash
make sbinit_all
make mbinit_all
make mbtrain
make cov_sbinit
make cov_mbinit
```

Add new targets rather than rewriting the existing flow aggressively.

### 2. Add a top-level regression target

Add a new Makefile target:

```make
regress
```

It should run the main suites and continue even if one suite fails, so that one broken suite does not prevent collecting results from later suites.

Use a configurable output directory:

```make
REGRESS_OUT ?= regressions/latest
```

The target should roughly do:

```bash
mkdir -p $(REGRESS_OUT)
make sbinit_all || true
make mbinit_all || true
make mbtrain || true
python3 scripts/collect_regression.py --log-root run_logs --out $(REGRESS_OUT)
python3 scripts/build_triage_prompt.py --regression $(REGRESS_OUT)/summary.json --out $(REGRESS_OUT)/triage_prompt.md
```

If LTSM has only a single target and does not write `.results`, do not force it into the first version unless it is easy and safe. Prefer a robust MVP.

### 3. Add debug knobs to Makefile if missing

The Makefile already has `MBINIT_XRUN_EXTRA`.

Please add equivalent optional knobs where useful:

```make
SBINIT_XRUN_EXTRA ?=
MBTRAIN_XRUN_EXTRA ?=
XRUN_DEBUG_EXTRA ?=
```

Then wire them into the relevant xrun commands without breaking current behavior.

For example, the agent should later be able to run:

```bash
make sbinit SBTEST=test_sbinit_req_backpressure SBINIT_XRUN_EXTRA='+define+TRIAGE_DEBUG'
make mbinit MBTEST=test_mbinit_lr04_reversal_apply MBINIT_XRUN_EXTRA='+define+TRIAGE_DEBUG'
make mbtrain MBTRAINTEST=test_mbtrain_speedidle MBTRAIN_XRUN_EXTRA='+define+TRIAGE_DEBUG'
```

If there is already a cleaner convention in the Makefile, follow that.

### 4. Create `scripts/collect_regression.py`

Create a Python 3 script:

```bash
python3 scripts/collect_regression.py --log-root run_logs --out regressions/latest
```

It should:

* parse all known suite `.results` files under `run_logs/*/.results`,
* tolerate missing suites/directories,
* read per-test logs when available,
* produce `summary.json`,
* produce `failures.md`,
* cluster failures by a stable-ish failure signature.

The JSON should include at least:

```json
{
  "run_id": "...",
  "timestamp": "...",
  "git_sha": "...",
  "total": 0,
  "passed": 0,
  "failed": 0,
  "suites": {
    "sbinit": {
      "total": 0,
      "passed": 0,
      "failed": 0
    }
  },
  "failures": [
    {
      "suite": "mbinit",
      "test": "test_name",
      "status": "FAIL",
      "log": "run_logs/...",
      "sim_exit_status": 1,
      "reason": "...",
      "signature": "...",
      "category": "...",
      "first_error_line": 123,
      "excerpt": "..."
    }
  ],
  "clusters": [
    {
      "signature": "...",
      "category": "...",
      "count": 5,
      "suites": ["mbinit"],
      "tests": ["..."],
      "representative_tests": ["..."],
      "logs": ["..."]
    }
  ]
}
```

The script should classify failures into categories such as:

* `compile_error`
* `elaboration_error`
* `uvm_fatal`
* `uvm_error`
* `assertion_failure`
* `timeout`
* `simulator_crash`
* `nonzero_exit`
* `unknown`

Use practical regexes for Xcelium and UVM, including patterns like:

```text
UVM_ERROR
UVM_FATAL
xrun: *E
xmvlog: *E
xmelab: *E
*E,
ASSERT
assertion
timeout
```

Cluster by the most useful signature available. Prefer stable UVM IDs if present. For example, if a line contains:

```text
UVM_ERROR @ ... reporter [MBINIT_LR04_REVERSAL_MISMATCH] ...
```

the signature should be something like:

```text
uvm_error:MBINIT_LR04_REVERSAL_MISMATCH
```

If there is no stable ID, normalize noisy values like timestamps, cycle counts, hex values, absolute paths, and line numbers.

The script should choose representative tests per cluster. Use heuristics like:

* at most 3 representative tests per cluster,
* prefer tests with names containing `sanity`, `decode`, or focused feature names,
* include tests from each affected suite if the cluster spans suites,
* avoid selecting every failing test.

### 5. Create `scripts/build_triage_prompt.py`

Create a Python 3 script:

```bash
python3 scripts/build_triage_prompt.py --regression regressions/latest/summary.json --out regressions/latest/triage_prompt.md
```

It should generate a prompt for an AI agent.

The prompt should tell the agent:

* it is a DV regression triage agent,
* it should read `summary.json`,
* it should inspect only the relevant logs/source files,
* it should identify the highest-impact failure cluster,
* it should select at most ~20 representative reruns,
* it should prefer targeted reruns over full regression reruns,
* it should distinguish compile/elab failures from runtime scoreboard/assertion failures,
* it should suggest exact Makefile commands,
* it should suggest files to inspect,
* it should suggest additional debug observability,
* it should not edit RTL/UVM source files unless explicitly asked,
* it should output a structured Markdown report.

The generated prompt should include project-specific command examples, such as:

```bash
make sbinit SBTEST=<test>
make mbinit MBTEST=<test>
make mbtrain MBTRAINTEST=<test>
```

and debug examples such as:

```bash
make mbinit MBTEST=<test> MBINIT_XRUN_EXTRA='+define+TRIAGE_DEBUG'
```

### 6. Add an optional `ai_triage` Makefile target

Add:

```make
ai_triage
```

It should depend on, or at least invoke, the regression collection/prompt generation flow.

If `claude` is available in `PATH`, it may run something like:

```bash
claude --bare -p "$$(cat $(REGRESS_OUT)/triage_prompt.md)" \
  --allowedTools "Read,Grep,Glob,Bash" \
  --output-format json \
  > $(REGRESS_OUT)/ai_triage.json
```

But do this defensively:

* If `claude` is not installed, print a helpful message telling me where the generated prompt is.
* Do not fail the whole target just because Claude is unavailable.
* Do not require an API key for the infrastructure to be useful.
* Consider also writing an `ai_triage.md` if the output is Markdown rather than JSON.

If you think allowing Bash is too broad, document that risk and optionally provide a safer “prompt-only” target.

### 7. Add a prompt-only target

Add a target like:

```make
triage_prompt
```

or:

```make
collect_regress
```

that only creates:

```text
summary.json
failures.md
triage_prompt.md
```

without calling any AI tool.

This is important because I may want to paste the prompt manually into Claude Code or ChatGPT.

### 8. Add documentation

Create a concise doc, probably:

```text
docs/regression_triage.md
```

or:

```text
docs/ai_regression_triage.md
```

Document:

* how to run the full regression,
* how to generate the triage prompt,
* how to run Claude triage,
* where outputs are written,
* how failure clustering works,
* how to add better UVM error IDs,
* how to rerun representative tests,
* safety rules for agentic workflows.

Also mention that stable UVM error IDs make clustering much better. Recommend changing vague messages like:

```systemverilog
`uvm_error("SCOREBOARD", "Mismatch detected")
```

into stable IDs like:

```systemverilog
`uvm_error("MBINIT_LR04_REVERSAL_MISMATCH", $sformatf(...))
```

Do not make those UVM changes automatically unless they are trivial and clearly safe. Just document the recommendation.

### 9. Optional: add or update `CLAUDE.md`

If the repo does not already have a `CLAUDE.md`, create one.

If it exists, append a section for regression triage.

It should include:

* project overview,
* main suites,
* common commands,
* log locations,
* triage rules,
* do-not-edit rules,
* representative rerun strategy,
* known generated RTL path convention.

Example content:

```md
# UCIe LogPHY Verification Agent Guide

## Regression commands

- `make regress`
- `make triage_prompt`
- `make ai_triage`
- `make sbinit SBTEST=<test>`
- `make mbinit MBTEST=<test>`
- `make mbtrain MBTRAINTEST=<test>`

## Logs

- `run_logs/sbinit/*.log`
- `run_logs/mbinit/*.log`
- `run_logs/mbtrain/*.log`
- `run_logs/*/.results`

## Agent rules

- Do not edit RTL or UVM source in triage mode.
- Do not run `make clean` unless explicitly asked.
- Do not rerun the full regression repeatedly.
- Cluster failures by first useful signature.
- Choose representative tests.
- Always provide exact rerun commands.
```

### 10. Add a minimal smoke test

Do not run the full regression unless it is cheap and safe.

At minimum, validate the Python scripts by creating or using existing `run_logs/*/.results` files if present.

Run commands like:

```bash
python3 scripts/collect_regression.py --log-root run_logs --out regressions/latest
python3 scripts/build_triage_prompt.py --regression regressions/latest/summary.json --out regressions/latest/triage_prompt.md
```

Also run:

```bash
make -n regress
make -n triage_prompt
```

or equivalent dry-runs to confirm the Makefile syntax is valid.

If `run_logs` does not exist, the scripts should still produce a valid empty summary rather than crashing.

## Acceptance criteria

When done, I should have:

1. New Makefile targets:

   * `regress`
   * `triage_prompt` or `collect_regress`
   * `ai_triage`

2. New scripts:

   * `scripts/collect_regression.py`
   * `scripts/build_triage_prompt.py`

3. New output files when run:

   * `regressions/latest/summary.json`
   * `regressions/latest/failures.md`
   * `regressions/latest/triage_prompt.md`

4. Documentation:

   * `docs/regression_triage.md` or similar
   * optionally `CLAUDE.md`

5. The flow should work even if:

   * some suite logs are missing,
   * some tests fail,
   * Claude CLI is unavailable,
   * only partial logs exist.

6. The agent-generated prompt should be good enough that I can paste it into Claude Code and have it perform a focused Apple-style regression triage:

   * summarize failure clusters,
   * select representative tests,
   * propose rerun commands,
   * narrow likely root cause,
   * suggest next debug instrumentation.

## Style requirements

Keep the implementation simple, readable, and robust.

Prefer Python standard library only.

Avoid adding heavy dependencies.

Be conservative with Makefile changes.

At the end, provide a summary of:

* files changed,
* targets added,
* how to run the new flow,
* any assumptions or limitations,
* next recommended improvements.

  **VERY IMPORTANT:** Begin with only triage on SBINIT, do not put extra effort into including MBINIT and MBTRAIN during this pass. Once we have the SBINIT triage MVP created and working properly, we will expand the triage to include MBINIT and MBTRAIN tests. If it does not take extra work, you may include MBINIT and MBTRAIN, but only if it requires less work than if you were to not include them. Choose the path of least resistance, whether that's leaving MBTRAIN and MBINIT for next pass, or including them now.
