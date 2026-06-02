#!/usr/bin/env python3
"""Collect UVM regression results into a structured triage database.

Parses every ``<log-root>/*/.results`` file produced by the suite runners
(``make sbinit_all`` / ``mbinit_all`` / ``mbtrain``) plus the per-test logs they
reference, classifies and clusters the failures by a stable-ish signature, and
emits two artifacts under ``--out``:

  * ``summary.json``  — machine-readable regression database
  * ``failures.md``   — human-readable per-cluster + per-failure report

Design notes (see docs/regression_triage_build_plan.md):
  * STATUS in ``.results`` is the verdict. The sbinit single-test recipe ends in
    ``|| true`` so SIM_EXIT_STATUS is always 0 there; never trust exit status as
    the verdict.
  * Pure Python standard library only. Targets Python 3.6+. Every filesystem op
    is guarded; the script exits 0 and writes a valid *empty* summary even when
    no run_logs exist.
"""

import argparse
import datetime
import glob
import json
import os
import re
import subprocess
import sys

# ---------------------------------------------------------------------------
# Regexes
# ---------------------------------------------------------------------------

# Mirror of the error regex used by every suite runner in the Makefile so the
# Python verdict/classification stays in parity with the shell grep.
ERROR_RE = re.compile(
    r'^(?:UVM_ERROR|UVM_FATAL)\s+[^:]'
    r'|UVM_(?:ERROR|FATAL)\s*:\s*[1-9][0-9]*'
    r'|xrun:\s+\*E'
    r'|xmvlog:\s+\*E'
    r'|xmelab:\s+\*E'
    r'|\*E,'
)

# First bracketed UVM report ID on a UVM_ERROR/UVM_FATAL line, e.g.
#   UVM_ERROR ...(...) @ 275000: uvm_test_top.env.predictor [SBINIT_REF] ...
# captures kind ("ERROR"/"FATAL") and the ID token.
UVM_ID_RE = re.compile(r'\bUVM_(ERROR|FATAL)\b.*?\[([A-Za-z][A-Za-z0-9_]*)\]')

# SVA / assertion failure name, best-effort.
ASSERT_NAME_RE = re.compile(r'[Aa]ssertion\s+([\w.$\[\]]+)')

# Compile / elaboration error source extraction.
XMVLOG_RE = re.compile(r'xmvlog:\s+\*E[^(]*\(([^,)]+)')
XMELAB_RE = re.compile(r'xmelab:\s+\*E[,:]?\s*([\w.$]+)?')

# Leading "<lineno>:" prefix that `grep -n` puts on ERROR_EXCERPT lines.
GREP_PREFIX_RE = re.compile(r'^(\d+):(.*)$')

# Map suite name -> (make target, test variable) for exact rerun commands.
SUITE_RERUN = {
    'sbinit': ('sbinit', 'SBTEST'),
    'mbinit': ('mbinit', 'MBTEST'),
    'mbtrain': ('mbtrain', 'MBTRAINTEST'),
    'ltsm': ('ltsm', 'LTSTEST'),
}

# Tokens that make a test a good "representative" of a cluster.
PREFERRED_TOKENS = ('sanity', 'decode')
FEATURE_TOKENS = (
    'timeout', 'reset', 'backpressure', 'reversal', 'repair', 'param',
    'random', 'cal', 'speedidle', 'linkspeed', 'vref', 'rxclkcal',
)

MAX_REPRESENTATIVES = 3
EXCERPT_MAX_LINES = 12
EXCERPT_MAX_CHARS = 1500
LOG_READ_MAX_BYTES = 4 * 1024 * 1024


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def git_sha():
    """Short git SHA, or 'unknown' off a repo / on failure."""
    try:
        proc = subprocess.run(
            ['git', 'rev-parse', '--short', 'HEAD'],
            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
        )
        if proc.returncode == 0:
            sha = proc.stdout.decode('utf-8', 'replace').strip()
            if sha:
                return sha
    except Exception:
        pass
    return 'unknown'


def rerun_command(suite, test):
    target, var = SUITE_RERUN.get(suite, (suite, suite.upper() + 'TEST'))
    return 'make {} {}={}'.format(target, var, test)


def debug_rerun_command(suite, test):
    """Same rerun, but with the suite's TRIAGE_DEBUG knob wired in."""
    target, var = SUITE_RERUN.get(suite, (suite, suite.upper() + 'TEST'))
    knob = '{}_XRUN_EXTRA'.format(suite.upper())
    return "make {} {}={} {}='+define+TRIAGE_DEBUG'".format(target, var, test, knob)


def read_text(path):
    """Read a (small) text file defensively; return '' on any failure."""
    try:
        with open(path, 'r', errors='replace') as fh:
            return fh.read(LOG_READ_MAX_BYTES)
    except OSError:
        return ''


# ---------------------------------------------------------------------------
# .results parsing
# ---------------------------------------------------------------------------

def parse_results_file(path, suite):
    """Split a suite ``.results`` file into per-test record dicts.

    Recognized fields: STATUS, LOG, SIM_EXIT_STATUS, REASON, and the multi-line
    ERROR_EXCERPT / LOG_TAIL sections. Lines before the first ``TEST:`` (the
    title / "Tests:" header) are ignored.
    """
    records = []
    cur = None
    mode = None  # None | 'excerpt' | 'log_tail'

    def flush():
        if cur is not None:
            cur['error_excerpt'] = '\n'.join(cur.pop('_excerpt', [])).strip()
            cur['log_tail'] = '\n'.join(cur.pop('_log_tail', [])).strip()
            records.append(cur)

    for raw in read_text(path).splitlines():
        line = raw.rstrip('\n')
        if line.startswith('TEST:'):
            flush()
            cur = {
                'suite': suite,
                'test': line[len('TEST:'):].strip(),
                'status': '',
                'log': '',
                'sim_exit_status': None,
                'reason': '',
                '_excerpt': [],
                '_log_tail': [],
            }
            mode = None
            continue
        if cur is None:
            continue
        if line.startswith('STATUS:'):
            cur['status'] = line[len('STATUS:'):].strip()
            mode = None
        elif line.startswith('LOG:'):
            cur['log'] = line[len('LOG:'):].strip()
            mode = None
        elif line.startswith('SIM_EXIT_STATUS:'):
            val = line[len('SIM_EXIT_STATUS:'):].strip()
            try:
                cur['sim_exit_status'] = int(val)
            except ValueError:
                cur['sim_exit_status'] = val or None
            mode = None
        elif line.startswith('REASON:'):
            cur['reason'] = line[len('REASON:'):].strip()
            mode = None
        elif line.startswith('ERROR_EXCERPT:'):
            mode = 'excerpt'
        elif line.startswith('LOG_TAIL:'):
            mode = 'log_tail'
        elif mode == 'excerpt':
            cur['_excerpt'].append(line)
        elif mode == 'log_tail':
            cur['_log_tail'].append(line)

    flush()
    return records


def resolve_log_path(log_field, log_root, suite, test):
    """Find the per-test log on disk, tolerating relative/missing paths."""
    candidates = []
    if log_field:
        candidates.append(log_field)
        candidates.append(os.path.join(os.getcwd(), log_field))
        candidates.append(os.path.join(os.path.dirname(os.path.abspath(log_root)),
                                       os.path.basename(log_field)))
    candidates.append(os.path.join(log_root, suite, test + '.log'))
    for cand in candidates:
        if cand and os.path.isfile(cand):
            return cand
    return log_field or ''


# ---------------------------------------------------------------------------
# Classification + signature
# ---------------------------------------------------------------------------

def matched_error_lines(text):
    """Return [(lineno, content), ...] for lines hitting the suite error regex."""
    out = []
    for idx, line in enumerate(text.splitlines(), 1):
        if ERROR_RE.search(line):
            out.append((idx, line.rstrip()))
    return out


def excerpt_error_lines(text):
    """Parse a ``.results`` ERROR_EXCERPT block (grep -n output) into
    [(lineno, content), ...], stripping the leading "<lineno>:" grep prefix and
    recovering the *real* log line number when present."""
    out = []
    for line in text.splitlines():
        if not line.strip():
            continue
        m = GREP_PREFIX_RE.match(line)
        if m:
            out.append((int(m.group(1)), m.group(2).rstrip()))
        else:
            out.append((None, line.rstrip()))
    return out


def classify(error_text, sim_exit_status):
    """Bucket a failure. Order: compile->elab->fatal->error->assert->timeout
    ->crash->nonzero_exit->unknown (matches the build plan)."""
    t = error_text
    if re.search(r'xmvlog:\s+\*E', t):
        return 'compile_error'
    if re.search(r'xmelab:\s+\*E', t):
        return 'elaboration_error'
    if re.search(r'\bUVM_FATAL\b', t):
        return 'uvm_fatal'
    if re.search(r'\bUVM_ERROR\b', t):
        return 'uvm_error'
    if re.search(r'\*E,', t) or re.search(r'assert', t, re.IGNORECASE):
        return 'assertion_failure'
    if re.search(r'timeout', t, re.IGNORECASE) or 'TEST_TIMEOUT' in t:
        return 'timeout'
    if re.search(r'xrun:\s+\*E', t) or 'Segmentation' in t:
        return 'simulator_crash'
    try:
        if sim_exit_status not in (0, None) and int(sim_exit_status) != 0:
            return 'nonzero_exit'
    except (TypeError, ValueError):
        pass
    return 'unknown'


def normalize_line(line):
    """Strip run-to-run noise so a fallback signature is stable."""
    s = re.sub(r'^\s*\d+:', '', line)            # drop grep -n "<lineno>:" prefix
    s = re.sub(r'0x[0-9a-fA-F]+', '<HEX>', s)    # hex literals
    s = re.sub(r'@\s*\d+', '@ <T>', s)           # @ <timestamp>
    s = re.sub(r'\(\s*\d+\s*\)', '(<N>)', s)     # (line numbers)
    # path-like tokens -> basename
    s = re.sub(r'(?:\.?/)?(?:[\w.\-]+/)+([\w.\-]+)', r'\1', s)
    s = re.sub(r'\b\d{3,}\b', '<N>', s)          # long bare numbers (cycles)
    s = re.sub(r'\s+', ' ', s).strip()
    return s


def compute_signature(category, error_lines):
    """Pick the most useful clustering signature available.

    Priority: bracketed UVM ID > SVA assertion name > compile/elab source >
    normalized first error line.
    """
    # 1. Stable UVM ID in brackets (preferred always).
    for _, content in error_lines:
        m = UVM_ID_RE.search(content)
        if m:
            kind = m.group(1).lower()
            return 'uvm_{}:{}'.format(kind, m.group(2))

    # 2. SVA assertion name.
    if category == 'assertion_failure':
        for _, content in error_lines:
            m = ASSERT_NAME_RE.search(content)
            if m:
                return 'assert:' + os.path.basename(m.group(1))

    # 3. Compile / elaboration source.
    if category == 'compile_error':
        for _, content in error_lines:
            m = XMVLOG_RE.search(content)
            if m:
                return 'compile:' + os.path.basename(m.group(1).strip())
    if category == 'elaboration_error':
        for _, content in error_lines:
            m = XMELAB_RE.search(content)
            if m and m.group(1):
                return 'elab:' + m.group(1)

    # 4. Normalized first error line.
    if error_lines:
        norm = normalize_line(error_lines[0][1])
        return 'cat:{}|{}'.format(category, norm[:40])
    return 'cat:{}|<no-error-line>'.format(category)


def build_excerpt(error_lines, log_tail):
    """A short, human-friendly excerpt for a failure."""
    if error_lines:
        lines = []
        for n, c in error_lines[:EXCERPT_MAX_LINES]:
            lines.append('{}: {}'.format(n, c) if n else c)
    elif log_tail:
        lines = log_tail.splitlines()[-EXCERPT_MAX_LINES:]
    else:
        lines = []
    text = '\n'.join(lines)
    if len(text) > EXCERPT_MAX_CHARS:
        text = text[:EXCERPT_MAX_CHARS] + '\n...[truncated]'
    return text


# ---------------------------------------------------------------------------
# Representative-test selection
# ---------------------------------------------------------------------------

def test_rank(test):
    """Lower is more preferred as a representative."""
    name = test.lower()
    for tok in PREFERRED_TOKENS:
        if tok in name:
            return 0
    for tok in FEATURE_TOKENS:
        if tok in name:
            return 1
    return 2


def pick_representatives(suite_to_tests):
    """<=3 representatives: >=1 per affected suite, prefer focused names,
    never every failing test."""
    reps = []
    # Guarantee coverage: best test from each affected suite.
    for suite in sorted(suite_to_tests):
        ranked = sorted(set(suite_to_tests[suite]), key=lambda t: (test_rank(t), t))
        if ranked and ranked[0] not in reps:
            reps.append(ranked[0])
    # Fill remaining slots with the next-best tests overall.
    all_tests = []
    for suite in sorted(suite_to_tests):
        all_tests.extend(suite_to_tests[suite])
    for test in sorted(set(all_tests), key=lambda t: (test_rank(t), t)):
        if len(reps) >= MAX_REPRESENTATIVES:
            break
        if test not in reps:
            reps.append(test)
    total = len(set(all_tests))
    # Never select *all* failing tests when there is more than one.
    if total > 1 and len(reps) >= total:
        reps = reps[:max(1, total - 1)]
    return reps[:MAX_REPRESENTATIVES]


# ---------------------------------------------------------------------------
# Collection
# ---------------------------------------------------------------------------

def collect(log_root):
    suites = {}
    failures = []

    results_files = sorted(glob.glob(os.path.join(log_root, '*', '.results')))
    for results_path in results_files:
        suite = os.path.basename(os.path.dirname(results_path))
        records = parse_results_file(results_path, suite)
        s = suites.setdefault(suite, {'total': 0, 'passed': 0, 'failed': 0})
        for rec in records:
            s['total'] += 1
            if rec['status'] == 'PASS':
                s['passed'] += 1
                continue
            s['failed'] += 1

            # Prefer the live per-test log; fall back to the .results excerpt.
            log_path = resolve_log_path(rec['log'], log_root, suite, rec['test'])
            log_text = read_text(log_path) if log_path else ''
            error_lines = matched_error_lines(log_text)
            if not error_lines and rec['error_excerpt']:
                # Fall back to the runner's ERROR_EXCERPT (grep -n output): it is
                # already the matched error lines, so keep them all and recover
                # their real log line numbers from the grep prefix.
                error_lines = excerpt_error_lines(rec['error_excerpt'])

            error_text = '\n'.join(c for _, c in error_lines) or rec['error_excerpt'] or rec['reason']
            category = classify(error_text, rec['sim_exit_status'])
            signature = compute_signature(category, error_lines)
            first_line = error_lines[0][0] if error_lines and error_lines[0][0] else None

            failures.append({
                'suite': suite,
                'test': rec['test'],
                'status': rec['status'] or 'FAIL',
                'log': rec['log'] or log_path,
                'sim_exit_status': rec['sim_exit_status'],
                'reason': rec['reason'],
                'signature': signature,
                'category': category,
                'first_error_line': first_line,
                'excerpt': build_excerpt(error_lines, rec['log_tail']),
            })

    return suites, failures


def cluster_failures(failures):
    by_sig = {}
    order = []
    for fail in failures:
        sig = fail['signature']
        if sig not in by_sig:
            by_sig[sig] = {
                'signature': sig,
                'category': fail['category'],
                'count': 0,
                'suites': [],
                'tests': [],
                'representative_tests': [],
                'logs': [],
                '_suite_tests': {},
            }
            order.append(sig)
        c = by_sig[sig]
        c['count'] += 1
        if fail['suite'] not in c['suites']:
            c['suites'].append(fail['suite'])
        if fail['test'] not in c['tests']:
            c['tests'].append(fail['test'])
        if fail['log'] and fail['log'] not in c['logs']:
            c['logs'].append(fail['log'])
        c['_suite_tests'].setdefault(fail['suite'], []).append(fail['test'])

    clusters = []
    for sig in order:
        c = by_sig[sig]
        c['representative_tests'] = pick_representatives(c.pop('_suite_tests'))
        c['suites'].sort()
        clusters.append(c)
    # Largest / highest-impact clusters first.
    clusters.sort(key=lambda c: (-c['count'], c['signature']))
    return clusters


# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------

def write_summary(out_dir, suites, failures, clusters):
    total = sum(s['total'] for s in suites.values())
    passed = sum(s['passed'] for s in suites.values())
    failed = sum(s['failed'] for s in suites.values())
    now = datetime.datetime.now(datetime.timezone.utc)
    sha = git_sha()
    summary = {
        'run_id': '{}_{}'.format(now.strftime('%Y%m%dT%H%M%SZ'), sha),
        'timestamp': now.replace(microsecond=0).isoformat(),
        'git_sha': sha,
        'total': total,
        'passed': passed,
        'failed': failed,
        'suites': suites,
        'failures': failures,
        'clusters': clusters,
    }
    path = os.path.join(out_dir, 'summary.json')
    with open(path, 'w') as fh:
        json.dump(summary, fh, indent=2, sort_keys=False)
        fh.write('\n')
    return summary


def write_failures_md(out_dir, summary):
    lines = []
    lines.append('# Regression Failures')
    lines.append('')
    lines.append('- run_id: `{}`'.format(summary['run_id']))
    lines.append('- timestamp: {}'.format(summary['timestamp']))
    lines.append('- git_sha: `{}`'.format(summary['git_sha']))
    lines.append('- totals: **{} total / {} passed / {} failed**'.format(
        summary['total'], summary['passed'], summary['failed']))
    lines.append('')

    if summary['suites']:
        lines.append('## Suites')
        lines.append('')
        lines.append('| suite | total | passed | failed |')
        lines.append('|-------|-------|--------|--------|')
        for name in sorted(summary['suites']):
            s = summary['suites'][name]
            lines.append('| {} | {} | {} | {} |'.format(
                name, s['total'], s['passed'], s['failed']))
        lines.append('')

    if not summary['failures']:
        if summary['total'] == 0:
            lines.append('_No regression data found. Run `make sbinit_regress` first._')
        else:
            lines.append('All {} tests passed. No failures to triage.'.format(summary['total']))
        lines.append('')
        _write(os.path.join(out_dir, 'failures.md'), lines)
        return

    lines.append('## Failure clusters ({})'.format(len(summary['clusters'])))
    lines.append('')
    for i, c in enumerate(summary['clusters'], 1):
        lines.append('### {}. `{}`'.format(i, c['signature']))
        lines.append('')
        lines.append('- category: **{}**'.format(c['category']))
        lines.append('- count: {} test(s)'.format(c['count']))
        lines.append('- affected suites: {}'.format(', '.join(c['suites'])))
        lines.append('- tests: {}'.format(', '.join(c['tests'])))
        lines.append('')
        lines.append('Representative reruns:')
        lines.append('')
        for test in c['representative_tests']:
            suite = _suite_for_test(summary, c, test)
            lines.append('- `{}`'.format(rerun_command(suite, test)))
            lines.append('  - debug: `{}`'.format(debug_rerun_command(suite, test)))
        lines.append('')
        excerpt = _cluster_excerpt(summary, c)
        if excerpt:
            lines.append('Excerpt:')
            lines.append('')
            lines.append('```')
            lines.append(excerpt)
            lines.append('```')
            lines.append('')

    lines.append('## All failures')
    lines.append('')
    lines.append('| suite | test | category | signature | log |')
    lines.append('|-------|------|----------|-----------|-----|')
    for f in summary['failures']:
        lines.append('| {} | {} | {} | `{}` | {} |'.format(
            f['suite'], f['test'], f['category'], f['signature'], f['log']))
    lines.append('')
    _write(os.path.join(out_dir, 'failures.md'), lines)


def _suite_for_test(summary, cluster, test):
    for f in summary['failures']:
        if f['test'] == test and f['signature'] == cluster['signature']:
            return f['suite']
    return cluster['suites'][0] if cluster['suites'] else 'sbinit'


def _cluster_excerpt(summary, cluster):
    for f in summary['failures']:
        if f['signature'] == cluster['signature'] and f['excerpt']:
            return f['excerpt']
    return ''


def _write(path, lines):
    with open(path, 'w') as fh:
        fh.write('\n'.join(lines))
        if not lines or lines[-1] != '':
            fh.write('\n')


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--log-root', default='run_logs',
                        help='Directory holding <suite>/.results (default: run_logs)')
    parser.add_argument('--out', default='regressions/latest',
                        help='Output directory (default: regressions/latest)')
    args = parser.parse_args(argv)

    try:
        os.makedirs(args.out, exist_ok=True)
    except OSError as exc:
        sys.stderr.write('collect_regression: cannot create {}: {}\n'.format(args.out, exc))
        return 0  # never crash

    suites, failures = collect(args.log_root)
    clusters = cluster_failures(failures)
    summary = write_summary(args.out, suites, failures, clusters)
    write_failures_md(args.out, summary)

    sys.stderr.write(
        'collect_regression: {} suites, {} tests, {} failed, {} cluster(s) -> {}\n'.format(
            len(suites), summary['total'], summary['failed'], len(clusters), args.out))
    return 0


if __name__ == '__main__':
    sys.exit(main())