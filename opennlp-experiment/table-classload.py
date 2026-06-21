#!/usr/bin/env python3
"""Generate LaTeX table of class-load source counts for opennlp RQ1.

Parses classload-{workload}-{scenario}.log files produced by workload-timed.sh.

Source categories:
  'shared objects file'           → archived (JDK + APP combined)
  'file://'  /  'jrt://'          → classpath
  '__JVM_LookupDefineClass__'     → generated
  '__dynamic_proxy__'             → generated
  anything else                   → custom classloader (WARNING printed)

Output: printed LaTeX table rows.
"""
import re, os, sys, argparse

HERE = os.path.dirname(os.path.abspath(__file__))

parser = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
parser.add_argument('--logs-dir', default=os.path.join(HERE, 'workload-tmp'),
                    help='directory containing classload-*.log files (default: workload-tmp/ next to this script)')
args = parser.parse_args()
LOGS_DIR = args.logs_dir

WORKLOADS = ['train-sentdetect', 'train-postag', 'train-postag-morfologik']
SCENARIOS = [
    ('no',        'No cache'),
    ('AOTCache',  'AOTCache'),
    ('TreeCache', r'\toolname{}'),
]

GENERATED = frozenset({'__JVM_LookupDefineClass__', '__dynamic_proxy__'})


def is_classloader_source(src):
    return (src not in GENERATED
            and '://' not in src
            and src != 'shared objects file'
            and re.match(r'[a-zA-Z_$][\w.$]*$', src) is not None)


def parse(log_path):
    """Return dict with keys: archived, classpath, generated."""
    archived = classpath = generated = 0
    with open(log_path) as f:
        for line in f:
            m = re.match(r'.*\[class,load\] (\S+) source: (.+)', line.strip())
            if not m:
                continue
            cls, src = m.group(1), m.group(2).strip()
            if src == 'shared objects file':
                archived += 1
            elif src in GENERATED or is_classloader_source(src):
                generated += 1
            elif src.startswith('file:') or src.startswith('jrt:/'):
                classpath += 1
            else:
                print(f'WARNING unknown source: class={cls!r}  source={src!r}',
                      file=sys.stderr)
                classpath += 1
    return dict(archived=archived, classpath=classpath, generated=generated)


# ── collect numbers ───────────────────────────────────────────────────────────
data = {}
for wl in WORKLOADS:
    data[wl] = {}
    for sc_key, _ in SCENARIOS:
        path = os.path.join(LOGS_DIR, f'classload-{wl}-{sc_key}.log')
        if not os.path.exists(path):
            print(f'MISSING: {path}', file=sys.stderr)
            continue
        data[wl][sc_key] = parse(path)

# ── emit LaTeX ────────────────────────────────────────────────────────────────
print(r'\begin{tabular}{@{}ll rrr r@{}}')
print(r'\toprule')
print(r'\textbf{Workload} & \textbf{Scenario}'
      r' & \textbf{Archived}'
      r' & \textbf{Classpath} & \textbf{Gen.}'
      r' & \textbf{Total} \\')
print(r'\midrule')

for wl in WORKLOADS:
    first = True
    for sc_key, sc_label in SCENARIOS:
        if sc_key not in data[wl]:
            continue
        s = data[wl][sc_key]
        total = s['archived'] + s['classpath'] + s['generated']
        wl_cell = f'\\texttt{{{wl}}}' if first else ''
        first = False
        bold = sc_key == 'TreeCache'
        def fmt(n, _bold=bold):
            return f'\\textbf{{{n:,}}}' if _bold else f'{n:,}'
        print(f'{wl_cell} & {sc_label}'
              f' & {fmt(s["archived"])}'
              f' & {fmt(s["classpath"])}'
              f' & {fmt(s["generated"])}'
              f' & {fmt(total)} \\\\')
    print(r'\midrule')

print(r'\end{tabular}')
