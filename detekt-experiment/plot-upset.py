#!/usr/bin/env python3
"""UpSet plot: pairwise APP class overlap between tree.aot and each detekt module cache."""
import re, os
import pandas as pd
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import numpy as np
from upsetplot import UpSet

PRIMITIVES = frozenset('ZBCSIFJD')
JDK = {'java', 'jdk', 'sun', 'javax', 'com.sun'} | PRIMITIVES

HERE = os.path.dirname(os.path.abspath(__file__))

MODULES = [
    ('detekt-rules-complexity',    'detekt/detekt-rules-complexity/aot.map'),
    ('detekt-rules-style',         'detekt/detekt-rules-style/aot.map'),
    ('detekt-rules-naming',        'detekt/detekt-rules-naming/aot.map'),
    ('detekt-rules-errorprone',    'detekt/detekt-rules-errorprone/aot.map'),
    ('detekt-rules-coroutines',    'detekt/detekt-rules-coroutines/aot.map'),
    ('detekt-rules-exceptions',    'detekt/detekt-rules-exceptions/aot.map'),
    ('detekt-rules-empty',         'detekt/detekt-rules-empty/aot.map'),
    ('detekt-rules-performance',   'detekt/detekt-rules-performance/aot.map'),
    ('detekt-rules-documentation', 'detekt/detekt-rules-documentation/aot.map'),
    ('detekt-core',                'detekt/detekt-core/aot.map'),
    ('detekt-parser',              'detekt/detekt-parser/aot.map'),
]
TREE_MAP = 'aot.map'
OUT = os.path.join(HERE, 'upset-tree-overlap.pdf')


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


def normalize(raw):
    name = raw
    while name.startswith('['):
        name = name[1:]
    if name.startswith('L') and name.endswith(';'):
        name = name[1:-1]
    return name


def extract_app_classes(map_path):
    with open(os.path.join(HERE, map_path), 'rb') as f:
        data = f.read().decode('utf-8', errors='replace')
    classes = set()
    for line in data.splitlines():
        m = re.match(r'.*@@ Class\s+\d+\s+(\S+)', line)
        if not m:
            continue
        raw = m.group(1)
        pkg = get_pkg(raw)
        if pkg is None or pkg in JDK:
            continue
        classes.add(normalize(raw))
    return classes


print('Loading APP class sets...')
contents = {'TreeCache': extract_app_classes(TREE_MAP)}
print(f'  {"TreeCache":<32}  {len(contents["TreeCache"]):>6} APP classes')
for label, path in MODULES:
    s = extract_app_classes(path)
    print(f'  {label:<32}  {len(s):>6} APP classes')
    contents[label] = s

dep_labels = [label for label, _ in MODULES]
all_labels = ['TreeCache'] + dep_labels
rows_idx, rows_val = [], []
print('\nPairwise exclusive overlap with TreeCache:')
for dep in dep_labels:
    key = tuple(lbl == 'TreeCache' or lbl == dep for lbl in all_labels)
    others_union = set().union(*(contents[d] for d in dep_labels if d != dep))
    count = len(contents['TreeCache'] & contents[dep] - others_union)
    rows_idx.append(key)
    rows_val.append(count)
    print(f'  TreeCache ∩ {dep} (exclusive): {count}')

midx = pd.MultiIndex.from_tuples(rows_idx, names=all_labels)
filtered = pd.Series(rows_val, index=midx)

palette = plt.cm.tab10(np.linspace(0, 1.0, len(dep_labels)))

upset = UpSet(filtered,
              subset_size='sum',
              show_counts=True,
              sort_by='cardinality',
              totals_plot_elements=0,
              other_dots_color='#b8cce4',
              element_size=28)

for label, color in zip(dep_labels, palette):
    upset.style_subsets(present=label, facecolor=color, edgecolor='none')

upset.plot()
fig = plt.gcf()
fig.set_size_inches(fig.get_size_inches()[0], 4.2)
fig.savefig(OUT, bbox_inches='tight', pad_inches=0.05)
print(f'\nWritten {OUT}')
