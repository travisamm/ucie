# Automated Regression Triage

Infrastructure that turns a UVM regression run into a structured, agent-ready
triage package. It parses the suite `.results` files and per-test logs,
classifies and clusters the failures by a stable signature, and emits a
machine-readable database, a human report, and a triage prompt for an AI agent.

**This is infrastructure only.** Triage *diagnoses*; it never *fixes*. Nothing
here edits RTL, UVM checkers, test intent, or SVA.

> **Scope (MVP): SBINIT only.** The flow is built and proven on the SBINIT
> suite. MBINIT/MBTRAIN drop in later by appending to one Makefile variable
> (`REGRESS_SUITES`) — see [Extending to other suites](#extending-to-other-suites).

All commands run from `uvm/`.

## Quick start

```bash
# Full SBINIT regression: run the suite, collect results, build the triage prompt
make sbinit_regress

# Prompt-only: re-collect + rebuild the prompt from existing run_logs (no sim, no AI)
make triage_prompt        # alias: make collect_regress

# AI triage: build the prompt, then run the Claude CLI if it is installed
make agent_triage

# Archive a snapshot worth keeping
make save_regress NAME=new_timeout_fail
```

## Commands

| Command | What it does | Runs sim? | Runs AI? |
|---------|--------------|-----------|----------|
| `make regress` | Loops `REGRESS_SUITES`, then collects + builds prompt | yes | no |
| `make sbinit_regress` | `make regress REGRESS_SUITES=sbinit_all` (SBINIT scope) | yes | no |
| `make collect_regress` | Collect + build prompt from existing `run_logs` | no | no |
| `make triage_prompt` | Alias of `collect_regress` | no | no |
| `make agent_triage` | `collect_regress`, then run `claude` if present | no | optional |
| `make save_regress NAME=<id>` | Copy `regressions/latest` → `regressions/<id>` | no | no |

`make regress` continues past a failing suite (`$(MAKE) <suite> || true`), so one
broken suite never blocks collecting the rest.

## Outputs

Everything lands under `$(REGRESS_OUT)` (default `regressions/latest/`), which is
**overwritten every run** and is **git-ignored**:

| File | Contents |
|------|----------|
| `summary.json` | Machine-readable database: totals, per-suite counts, every failure, and clusters. |
| `failures.md` | Human report: per-cluster sections (signature, category, representative reruns, excerpt) + a per-failure table. |
| `triage_prompt.md` | Self-contained prompt for a DV triage agent, with the live cluster summary inlined. |
| `agent_triage.json` | Only when `make agent_triage` ran the Claude CLI successfully. |

There is **no automatic history**. To keep a snapshot, the agent (or you) opts in
with `make save_regress NAME=<descriptive_run_id>`, where the name is derived from
the dominant failure (e.g. `new_timeout_fail`, `sbinit_backpressure_mismatch`).

## How a verdict is decided

The suite runners (`sbinit_all`, etc.) write `run_logs/<suite>/.results` with one
block per test: `TEST / STATUS / LOG / SIM_EXIT_STATUS / REASON / ERROR_EXCERPT /
LOG_TAIL`. The collector treats **`STATUS` as the authoritative verdict**.

> The `make sbinit` recipe ends in `|| true`, so its `SIM_EXIT_STATUS` is
> *always 0*. Pass/fail for SBINIT is decided entirely by the error-regex grep
> recorded in `STATUS`. Do not trust the exit status as the verdict. (The single
> `mbinit` recipe has no `|| true` and can return nonzero — so the `nonzero_exit`
> category exists, but it rarely fires for SBINIT.)

The collector reuses the **same error regex** as the suite runners, so the Python
classification stays in parity with the shell grep.

## Classification

Each failure is bucketed into one `category`, checked in this order
(first match wins):

| Order | Category | Trigger |
|-------|----------|---------|
| 1 | `compile_error` | `xmvlog: *E` |
| 2 | `elaboration_error` | `xmelab: *E` |
| 3 | `uvm_fatal` | `UVM_FATAL` |
| 4 | `uvm_error` | `UVM_ERROR` |
| 5 | `assertion_failure` | `*E,` (SVA) / `assert` |
| 6 | `timeout` | `timeout` / `TEST_TIMEOUT` |
| 7 | `simulator_crash` | `xrun: *E` / `Segmentation` |
| 8 | `nonzero_exit` | non-zero exit, no pattern matched |
| 9 | `unknown` | fallback |

Build failures (`compile_error`, `elaboration_error`) sort first because they
block everything downstream — fix the build before chasing runtime failures.

## Signatures and clustering

Failures are grouped into **clusters** by a `signature`. The collector picks the
most useful signature available (best wins):

1. **Stable UVM ID in brackets** (preferred always) — from a line like
   `UVM_ERROR ... [SBINIT_REF] ...` → `uvm_error:SBINIT_REF`
   (or `uvm_fatal:<ID>`).
2. **SVA assertion name** → `assert:<name>`.
3. **Compile / elaboration source** → `compile:<file>` / `elab:<module>`.
4. **Normalized first error line** (fallback) — absolute paths reduced to
   basenames; timestamps, `@ <n>`, cycle counts, hex `0x...`, and line numbers
   replaced with `<T>`/`<N>`/`<HEX>`; whitespace collapsed — then
   `cat:<category>|<first 40 chars>`.

Clusters are sorted highest-impact first (largest `count`). Each cluster records
`count`, `category`, affected `suites`, `tests`, `representative_tests`, and
`logs`.

### Representative tests

Per cluster, the collector selects **≤3 representative tests** so you rerun a
focused subset instead of everything:

- prefer names containing `sanity` / `decode`, then focused feature tokens
  (`timeout`, `reset`, `backpressure`, `reversal`, `repair`, …);
- include ≥1 test from each affected suite when a cluster spans suites;
- never select *all* failing tests in a multi-test cluster.

## Rerunning representative tests

`failures.md` and `triage_prompt.md` give exact commands for each representative
test. Reproduce, then debug with the suite's `*_XRUN_EXTRA` knob:

```bash
make sbinit  SBTEST=test_sbinit_req_backpressure
make sbinit  SBTEST=test_sbinit_req_backpressure SBINIT_XRUN_EXTRA='+define+TRIAGE_DEBUG'
```

Debug knobs (all optional, default empty):

| Knob | Applies to |
|------|------------|
| `SBINIT_XRUN_EXTRA` | `make sbinit` |
| `MBINIT_XRUN_EXTRA` | `make mbinit` |
| `MBTRAIN_XRUN_EXTRA` | `make mbtrain` |
| `XRUN_DEBUG_EXTRA` | all three at once (global escape hatch) |

These append raw `xrun` arguments (e.g. extra `+define+`s) without changing any
default behavior.

## Agentic safety rules

`make agent_triage` runs the Claude CLI with `--allowedTools "Read,Grep,Glob,Bash"`.
**Bash is enabled** so the agent can run its own targeted reruns. No `Edit`/`Write`
tool is granted, but Bash can technically write files, so the no-edit rule is
enforced by the **prompt**, not a sandbox. Treat it as a residual risk; use
`make triage_prompt` (zero-AI) when you only want the prompt.

The generated prompt instructs the agent to:

- **never edit RTL/UVM/DUT source** during triage (Chisel/Scala, generated
  SystemVerilog under `elab/generatedVerilog/**`, UVM checkers/scoreboards/
  sequences, `uvm/tb/logphy_sva.sv`);
- **never run `make clean`**;
- **never rerun the full regression repeatedly** — use the representative subset;
- read only the logs/source relevant to the chosen cluster;
- output a structured Markdown report (cluster summary → root-cause hypothesis →
  chosen reruns + commands → files to inspect → next instrumentation).

## Recommendation: give UVM errors stable IDs

Clustering precision scales directly with stable, unique UVM report IDs. Vague,
shared IDs collapse unrelated failures into one cluster; unique IDs split them
cleanly. Prefer descriptive IDs over generic ones:

```systemverilog
// Weak — many unrelated mismatches share this ID:
`uvm_error("SCOREBOARD", "Mismatch detected")

// Strong — the bracketed ID becomes a precise cluster signature:
`uvm_error("MBINIT_LR04_REVERSAL_MISMATCH", $sformatf("exp=%0d act=%0d", exp, act))
```

This is a **recommendation only**. The triage tooling does **not** auto-edit any
UVM source; apply such changes deliberately as a separate, reviewed task.

## Extending to other suites

The MVP is SBINIT-only by design. To add MBINIT/MBTRAIN later, append their suite
runners to `REGRESS_SUITES` — nothing else needs to change, because the collector
already globs every `run_logs/*/.results`:

```bash
make regress REGRESS_SUITES="sbinit_all mbinit_all mbtrain"
```

or set the default in the Makefile:

```make
REGRESS_SUITES ?= sbinit_all mbinit_all mbtrain
```

The categories, signatures, and representative-test heuristics are
suite-agnostic. For sharper MBINIT/MBTRAIN clustering, stabilize those
scoreboards' UVM error IDs first (see the recommendation above).

## Files

| Path | Role |
|------|------|
| `uvm/scripts/collect_regression.py` | Parse `.results` + logs → `summary.json` + `failures.md`. |
| `uvm/scripts/build_triage_prompt.py` | `summary.json` → `triage_prompt.md`. |
| `uvm/Makefile` | `regress`, `sbinit_regress`, `collect_regress`, `triage_prompt`, `agent_triage`, `save_regress` + the `*_XRUN_EXTRA` knobs. |
| `docs/regression_triage_build_plan.md` | Authoritative build spec (decisions resolved). |

Both scripts are pure Python standard library and never crash on missing
suites/logs — with no `run_logs` they still emit a valid empty `summary.json`.
