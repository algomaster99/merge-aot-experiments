#!/usr/bin/env python3
"""Generate LaTeX table of class-load source counts for commons-configuration RQ1.

Parses classload-{workload}-{scenario}.log files.

Source categories:
  'shared objects file'           → archive
  'file://'  /  'jrt://'          → classpath
  '__JVM_LookupDefineClass__'     → generated
  '__dynamic_proxy__'             → generated
  anything else                   → custom classloader (WARNING printed)

Archive classes are further split into JDK / APP by package name.

Output: printed LaTeX table rows (commons-configuration only).
"""
import re, os, sys, argparse

HERE = os.path.dirname(os.path.abspath(__file__))

parser = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
parser.add_argument('--logs-dir', default=os.path.join(HERE, 'workload-tmp'),
                    help='directory containing classload-*.log files (default: workload-tmp/ next to this script)')
args = parser.parse_args()
LOGS_DIR = args.logs_dir

WORKLOADS = ['properties-read', 'xml-read', 'composite-read', 'interpolation']
SCENARIOS = [
    ('no',        'No cache'),
    ('AOTCache',  'AOTCache'),
    ('TreeCache', r'\toolname{}'),
]

PRIMITIVES = frozenset('ZBCSIFJD')
JDK_PKGS   = {'java', 'jdk', 'sun', 'javax', 'com.sun'} | PRIMITIVES
GENERATED  = frozenset({'__JVM_LookupDefineClass__', '__dynamic_proxy__'})


def get_pkg(name):
    while name.startswith('['):
        name = name[1:]
    if name.startswith('L') and name.endswith(';'):
        name = name[1:-1]
    if not name:
        return None
    if '.' not in name:
        return name if name in PRIMITIVES else None
    parts = name.split('.')
    if parts[0] == 'com' and len(parts) >= 2:
        return parts[0] + '.' + parts[1]
    return parts[0]


def is_jdk(name):
    pkg = get_pkg(name)
    return (pkg in JDK_PKGS) if pkg else True


def is_classloader_source(src):
    """True if source is a Java class name acting as a custom classloader.

    These arise for lambda/anonymous classes defined at runtime by their
    enclosing class (e.g., 'org.foo.Bar$$Lambda/0x... source: org.foo.Bar').
    A class-name source has no '://' or spaces and looks like a dotted identifier.
    """
    return (src not in GENERATED
            and '://' not in src
            and src != 'shared objects file'
            and re.match(r'[a-zA-Z_$][\w.$]*$', src) is not None)


def parse(log_path):
    """Return dict with keys: arch_jdk, arch_app, classpath, generated."""
    arch_jdk = arch_app = classpath = generated = 0
    with open(log_path) as f:
        for line in f:
            m = re.match(r'.*\[class,load\] (\S+) source: (.+)', line.strip())
            if not m:
                continue
            cls, src = m.group(1), m.group(2).strip()
            if src == 'shared objects file':
                if is_jdk(cls):
                    arch_jdk += 1
                else:
                    arch_app += 1
            elif src in GENERATED or is_classloader_source(src):
                generated += 1
            elif src.startswith('file:') or src.startswith('jrt:/'):
                classpath += 1
            else:
                print(f'WARNING unknown source: class={cls!r}  source={src!r}',
                      file=sys.stderr)
                classpath += 1   # treat as not-from-archive
    return dict(arch_jdk=arch_jdk, arch_app=arch_app,
                classpath=classpath, generated=generated)


# ── collect numbers ───────────────────────────────────────────────────────────
data = {}   # data[workload][scenario_key] = stats dict
for wl in WORKLOADS:
    data[wl] = {}
    for sc_key, _ in SCENARIOS:
        path = os.path.join(LOGS_DIR, f'classload-{wl}-{sc_key}.log')
        if not os.path.exists(path):
            print(f'MISSING: {path}', file=sys.stderr)
            continue
        data[wl][sc_key] = parse(path)

# ── emit LaTeX ────────────────────────────────────────────────────────────────
# Column layout:
#   Workload | Scenario | Arch-JDK | Arch-APP | Classpath | Generated | Total
print(r'\begin{tabular}{@{}ll rrrr r@{}}')
print(r'\toprule')
print(r'\textbf{Workload} & \textbf{Scenario}'
      r' & \textbf{Arch-JDK} & \textbf{Arch-APP}'
      r' & \textbf{Classpath} & \textbf{Gen.}'
      r' & \textbf{Total} \\')
print(r'\midrule')

for wl in WORKLOADS:
    first = True
    for sc_key, sc_label in SCENARIOS:
        if sc_key not in data[wl]:
            continue
        s = data[wl][sc_key]
        total = s['arch_jdk'] + s['arch_app'] + s['classpath'] + s['generated']
        wl_cell = f'\\texttt{{{wl}}}' if first else ''
        first = False
        bold = sc_key == 'TreeCache'
        def fmt(n):
            return f'\\textbf{{{n:,}}}' if bold else f'{n:,}'
        print(f'{wl_cell} & {sc_label}'
              f' & {fmt(s["arch_jdk"])}'
              f' & {fmt(s["arch_app"])}'
              f' & {fmt(s["classpath"])}'
              f' & {fmt(s["generated"])}'
              f' & {fmt(total)} \\\\')
    print(r'\midrule')

print(r'\end{tabular}')
