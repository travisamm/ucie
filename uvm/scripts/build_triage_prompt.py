#!/usr/bin/env python3
"""Turn a regression summary.json into an agent-ready triage prompt.

Reads ``--regression`` (a summary.json produced by collect_regression.py) and
writes ``--out`` (triage_prompt.md): a self-contained prompt instructing a DV
regression-triage agent how to investigate the highest-impact failure cluster
for the UCIe 3.0 LogPHY UVM environment.

Pure Python standard library, Python 3.6+. Tolerates a missing/invalid
summary.json by emitting a still-valid prompt that tells the reader to run
``make sbinit_regress`` first.
"""

import argparse
import json
import os
import sys

# Suite -> (make target, test variable, xrun-extra knob) for command examples.
SUITE_CMD = {
    'sbinit': ('sbinit', 'SBTEST', 'SBINIT_XRUN_EXTRA'),
    'mbinit': ('mbinit', 'MBTEST', 'MBINIT_XRUN_EXTRA'),
    'mbtrain': ('mbtrain', 'MBTRAINTEST', 'MBTRAIN_XRUN_EXTRA'),
    'ltsm': ('ltsm', 'LTSTEST', 'XRUN_DEBUG_EXTRA'),
}

MAX_RERUNS = 5


def load_summary(path):
    try:
        with open(path, 'r', errors='replace') as fh:
            return json.load(fh)
    except (OSError, ValueError):
        return None


def rerun(suite, test):
    target, var, _ = SUITE_CMD.get(suite, (suite, suite.upper() + 'TEST', 'XRUN_DEBUG_EXTRA'))
    return 'make {} {}={}'.format(target, var, test)


def debug_rerun(suite, test):
    target, var, knob = SUITE_CMD.get(suite, (suite, suite.upper() + 'TEST', 'XRUN_DEBUG_EXTRA'))
    return "make {} {}={} {}='+define+TRIAGE_DEBUG'".format(target, var, test, knob)


def cluster_table(clusters):
    if not clusters:
        return '_No failure clusters — every collected test passed._'
    rows = ['| # | signature | category | count | suites | representative tests |',
            '|---|-----------|----------|-------|--------|----------------------|']
    for i, c in enumerate(clusters, 1):
        rows.append('| {} | `{}` | {} | {} | {} | {} |'.format(
            i, c.get('signature', '?'), c.get('category', '?'), c.get('count', 0),
            ', '.join(c.get('suites', []) or []),
            ', '.join(c.get('representative_tests', []) or [])))
    return '\n'.join(rows)


def representative_command_block(clusters):
    """Concrete rerun commands for up to MAX_RERUNS representative tests, drawn
    from the highest-impact clusters first."""
    lines = []
    seen = set()
    for c in clusters:
        suite = (c.get('suites') or ['sbinit'])[0]
        for test in c.get('representative_tests', []) or []:
            if len(seen) >= MAX_RERUNS:
                break
            if test in seen:
                continue
            seen.add(test)
            lines.append('# cluster `{}` ({})'.format(c.get('signature', '?'), c.get('category', '?')))
            lines.append(rerun(suite, test))
            lines.append(debug_rerun(suite, test))
    if not lines:
        lines.append('# no failing clusters; nothing to rerun')
    return '\n'.join(lines)


def build_prompt(summary):
    if not summary:
        return EMPTY_PROMPT

    clusters = summary.get('clusters', []) or []
    failures = summary.get('failures', []) or []
    head = []
    head.append('# DV Regression Triage — UCIe 3.0 LogPHY (UVM)')
    head.append('')
    head.append('You are a **DV regression triage agent** for an open-source UCIe 3.0 '
                'LogPHY verification environment (Chisel/Scala RTL elaborated to '
                'SystemVerilog, verified with UVM + Cadence Xcelium). Your job is to '
                'triage this regression — **diagnose, do not fix**.')
    head.append('')
    head.append('## Regression under triage')
    head.append('')
    head.append('- run_id: `{}`'.format(summary.get('run_id', '?')))
    head.append('- git_sha: `{}`'.format(summary.get('git_sha', '?')))
    head.append('- totals: **{} total / {} passed / {} failed**'.format(
        summary.get('total', 0), summary.get('passed', 0), summary.get('failed', 0)))
    suites = summary.get('suites', {}) or {}
    if suites:
        parts = ['{} ({}/{} pass)'.format(name, s.get('passed', 0), s.get('total', 0))
                 for name, s in sorted(suites.items())]
        head.append('- suites: ' + ', '.join(parts))
    head.append('')

    if not failures:
        head.append('**All collected tests passed.** There is nothing to triage. '
                    'Report a clean regression and stop.')
        head.append('')
        return '\n'.join(head) + '\n'

    body = ['']
    body.append('## Failure clusters (live, from summary.json)')
    body.append('')
    body.append(cluster_table(clusters))
    body.append('')
    body.append('## Your task')
    body.append('')
    body.append('1. Read `{}` for the full machine-readable detail, and read '
                '`regressions/latest/failures.md` for the human view.'.format(
                    'regressions/latest/summary.json'))
    body.append('2. Identify the **single highest-impact cluster** — usually the '
                'one with the largest `count` or the one that blocks the most '
                'downstream tests (a compile/elaboration break blocks everything).')
    body.append('3. **Classify the failure mode.** Distinguish **build failures** '
                '(`compile_error`, `elaboration_error` — fix the build first, they '
                'mask everything else) from **runtime failures** '
                '(`uvm_error`/`uvm_fatal` scoreboard/reference-model mismatches, '
                '`assertion_failure` SVA, `timeout`).')
    body.append('4. Form a **single root-cause hypothesis** for the chosen cluster. '
                'Use the shared `signature` as evidence that the failures have one '
                'cause. Read **only the relevant** per-test logs '
                '(`run_logs/<suite>/<test>.log`) and the relevant source '
                '(scoreboard/predictor/SVA) — do not read the whole tree.')
    body.append('5. Select **at most {} representative reruns** — prefer the '
                "cluster's `representative_tests`; prefer targeted single-test "
                'reruns over rerunning the full regression.'.format(MAX_RERUNS))
    body.append('6. Give **exact Makefile commands** to reproduce and to debug '
                '(see below).')
    body.append('7. Suggest **specific files to inspect** and **extra debug '
                'observability** to add (waves, `uvm_info` verbosity, a new '
                'assertion) — describe them; do **not** apply them.')
    body.append('')
    body.append('## Exact commands to use')
    body.append('')
    body.append('Reproduce / debug the representative tests for the top clusters:')
    body.append('')
    body.append('```bash')
    body.append(representative_command_block(clusters))
    body.append('```')
    body.append('')
    body.append('General command shapes:')
    body.append('')
    body.append('```bash')
    body.append('make sbinit  SBTEST=<test>')
    body.append('make mbinit  MBTEST=<test>')
    body.append('make mbtrain MBTRAINTEST=<test>')
    body.append("make sbinit  SBTEST=<test> SBINIT_XRUN_EXTRA='+define+TRIAGE_DEBUG'")
    body.append("# XRUN_DEBUG_EXTRA applies to every suite at once, e.g.")
    body.append("make sbinit  SBTEST=<test> XRUN_DEBUG_EXTRA='+define+TRIAGE_DEBUG'")
    body.append('```')
    body.append('')
    body.append('## Hard safety rules (triage mode)')
    body.append('')
    body.append('- **Do NOT edit RTL/UVM/DUT source** during triage — no '
                'Chisel/Scala, no generated SystemVerilog under '
                '`elab/generatedVerilog/**`, no UVM checker/scoreboard/sequence/SVA '
                'behavior, no `uvm/tb/logphy_sva.sv`. Triage diagnoses; it never '
                'fixes.')
    body.append('- **Do NOT run `make clean`.**')
    body.append('- **Do NOT rerun the full regression repeatedly.** Use targeted '
                'single-test reruns from the representative set.')
    body.append('- Read only the logs/source relevant to the chosen cluster.')
    body.append('')
    body.append('## Required output (structured Markdown)')
    body.append('')
    body.append('1. **Cluster summary** — which cluster you chose and why '
                '(impact/blast radius).')
    body.append('2. **Root-cause hypothesis** — one shared cause, with the log/'
                'source evidence.')
    body.append('3. **Chosen reruns** — the <= {} tests + exact commands.'.format(MAX_RERUNS))
    body.append('4. **Files to inspect** — specific paths.')
    body.append('5. **Next instrumentation** — debug observability to add next '
                '(described, not applied).')
    body.append('')
    body.append('## Closing step (only if the results are worth keeping)')
    body.append('')
    body.append('If this regression is worth archiving (e.g. a new, distinct '
                'failure mode), copy the snapshot to a descriptively named '
                'directory derived from the dominant failure — for example '
                '`new_timeout_fail` or `sbinit_backpressure_mismatch`:')
    body.append('')
    body.append('```bash')
    body.append('make save_regress NAME=<descriptive_run_id>')
    body.append('```')
    body.append('')
    body.append('Otherwise leave `regressions/latest/` as-is (it is overwritten on '
                'the next run).')
    body.append('')
    return '\n'.join(head) + '\n'.join(body)


EMPTY_PROMPT = """# DV Regression Triage — UCIe 3.0 LogPHY (UVM)

**No regression data found.**

There is no readable `summary.json` to triage. Generate one first:

```bash
make sbinit_regress      # run the SBINIT suite, collect results, build this prompt
# or, if run_logs/ already exist and you only want to (re)collect:
make collect_regress
```

Then re-open `regressions/latest/triage_prompt.md`.
"""


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--regression', default='regressions/latest/summary.json',
                        help='Path to summary.json (default: regressions/latest/summary.json)')
    parser.add_argument('--out', default='regressions/latest/triage_prompt.md',
                        help='Output prompt path (default: regressions/latest/triage_prompt.md)')
    args = parser.parse_args(argv)

    summary = load_summary(args.regression)
    prompt = build_prompt(summary)

    out_dir = os.path.dirname(args.out)
    if out_dir:
        try:
            os.makedirs(out_dir, exist_ok=True)
        except OSError as exc:
            sys.stderr.write('build_triage_prompt: cannot create {}: {}\n'.format(out_dir, exc))
            return 0

    try:
        with open(args.out, 'w') as fh:
            fh.write(prompt)
            if not prompt.endswith('\n'):
                fh.write('\n')
    except OSError as exc:
        sys.stderr.write('build_triage_prompt: cannot write {}: {}\n'.format(args.out, exc))
        return 0

    state = 'no data' if not summary else '{} failure(s)'.format(summary.get('failed', 0))
    sys.stderr.write('build_triage_prompt: wrote {} ({})\n'.format(args.out, state))
    return 0


if __name__ == '__main__':
    sys.exit(main())