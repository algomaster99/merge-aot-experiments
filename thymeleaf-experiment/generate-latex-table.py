#!/usr/bin/env python3
"""Print LaTeX table rows (Size, Classes, App%) for all thymeleaf AOT caches.

App% = fraction of archived classes whose top-level package is not JDK-internal
(i.e. not java/jdk/sun/javax).  Run from anywhere — paths are relative to this file.
"""
import re, os, sys

JDK = {'java', 'jdk', 'sun', 'javax'}

HERE = os.path.dirname(os.path.abspath(__file__))

ROWS = [
    ('thymeleaf',       'thymeleaf/tests/thymeleaf-tests-core/cache.aot',  'thymeleaf/tests/thymeleaf-tests-core/aot.map'),
    ('attoparser',      'thymeleaf-deps/attoparser/cache.aot',              'thymeleaf-deps/attoparser/aot.map'),
    ('ognl',            'thymeleaf-deps/ognl/cache.aot',                    'thymeleaf-deps/ognl/aot.map'),
    ('slf4j-api',       'thymeleaf-deps/slf4j/slf4j-api/cache.aot',        'thymeleaf-deps/slf4j/slf4j-api/aot.map'),
    ('unbescape',       'thymeleaf-deps/unbescape-workload/cache.aot',      'thymeleaf-deps/unbescape-workload/aot.map'),
]
TREE = ('tree.aot', 'aot.map')


def get_pkg(class_name):
    name = class_name.strip()
    while name.startswith('['):
        name = name[1:]
    if name.startswith('L') and name.endswith(';'):
        name = name[1:-1]
    if not name or '.' not in name:
        return None
    return name.split('.')[0]


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
    total = jdk_cls + app_cls
    app_pct = app_cls / total * 100 if total else 0
    return size_mb, total, app_pct


def fmt_row(label, size_mb, classes, app_pct, bold_size=False):
    size_str = f'{size_mb:.0f}\\,MB'
    if bold_size:
        size_str = f'\\textbf{{{size_str}}}'
    return f'{label:<24} & {size_str} & {classes:>6,} & {app_pct:>5.1f}\\% \\\\'


missing = [p for _, c, m in ROWS + [('', *TREE)] for p in (c, m)
           if not os.path.exists(os.path.join(HERE, p))]
if missing:
    print('ERROR: missing files:\n  ' + '\n  '.join(missing), file=sys.stderr)
    sys.exit(1)

print(r'\multicolumn{4}{@{}l}{\textit{thymeleaf}} \\')
for label, cache, mapf in ROWS:
    print(fmt_row(label, *analyze(cache, mapf)))
print(fmt_row(r'\textit{tree.aot}', *analyze(*TREE), bold_size=True))
print(r'\midrule')
