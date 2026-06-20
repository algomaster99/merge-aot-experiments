#!/usr/bin/env python3
"""Print LaTeX table rows (Size, Classes, App%) for all detekt AOT caches."""
import re, os, sys

PRIMITIVES = frozenset('ZBCSIFJD')
JDK = {'java', 'jdk', 'sun', 'javax', 'com.sun'} | PRIMITIVES

HERE = os.path.dirname(os.path.abspath(__file__))

MODULES = [
    'detekt-rules-complexity',
    'detekt-rules-style',
    'detekt-rules-naming',
    'detekt-rules-errorprone',
    'detekt-rules-coroutines',
    'detekt-rules-exceptions',
    'detekt-rules-empty',
    'detekt-rules-performance',
    'detekt-rules-documentation',
    'detekt-core',
    'detekt-parser',
]

ROWS = [
    (mod, f'detekt/{mod}/cache.aot', f'detekt/{mod}/aot.map')
    for mod in MODULES
]
TREE = ('tree.aot', 'aot.map')


def get_pkg(class_name):
    name = class_name.strip()
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


def analyze(cache_path, map_path):
    size_mb = os.path.getsize(os.path.join(HERE, cache_path)) / 1024 / 1024
    with open(os.path.join(HERE, map_path), 'rb') as f:
        data = f.read().decode('utf-8', errors='replace')
    jdk_cls = app_cls = 0
    for line in data.splitlines():
        m = re.match(r'.*@@ Class\s+\d+\s+(\S+)', line)
        if not m:
            continue
        pkg = get_pkg(m.group(1))
        if pkg is None:
            continue
        if pkg in JDK:
            jdk_cls += 1
        else:
            app_cls += 1
    return size_mb, jdk_cls, app_cls


def fmt_row(label, size_mb, jdk_cls, app_cls, bold_size=False):
    size_str = f'{size_mb:.0f}\\,MB'
    if bold_size:
        size_str = f'\\textbf{{{size_str}}}'
    total = jdk_cls + app_cls
    jdk_pct = jdk_cls / total * 100 if total else 0
    app_pct = app_cls / total * 100 if total else 0
    return (f'{label:<32} & {size_str} & '
            f'{jdk_cls:>6,} ({jdk_pct:>5.1f}\\%) & '
            f'{app_cls:>6,} ({app_pct:>5.1f}\\%) \\\\')


missing = [p for _, c, m in ROWS + [('', *TREE)] for p in (c, m)
           if not os.path.exists(os.path.join(HERE, p))]
if missing:
    print('ERROR: missing files:\n  ' + '\n  '.join(missing), file=sys.stderr)
    sys.exit(1)

print(r'\multicolumn{4}{@{}l}{\textit{detekt}} \\')
for label, cache, mapf in ROWS:
    print(fmt_row(label, *analyze(cache, mapf)))
print(fmt_row(r'\toolname', *analyze(*TREE), bold_size=True))
print(r'\midrule')
