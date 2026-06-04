#!/usr/bin/env python3
"""UpSet plot: pairwise APP class overlap between TreeCache and each per-dep cache.

Shows only bars where TreeCache and exactly one dep cache both contain a class.
Sets      = TreeCache + all per-dep caches.
Output: upset-tree-overlap.pdf
"""
import re, os
import pandas as pd
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import numpy as np
from upsetplot import UpSet

# JVM primitive type one-letter descriptors (B=byte, C=char, D=double, etc.)
PRIMITIVES = frozenset('ZBCSIFJD')
# Top-level package prefixes that identify JDK-internal classes to exclude from app counts
JDK = {'java', 'jdk', 'sun', 'javax', 'com.sun'} | PRIMITIVES

HERE = os.path.dirname(os.path.abspath(__file__))

# (label, path-relative-to-HERE) for each per-dep aot.map file
DEPS = [
    ('thymeleaf',           'thymeleaf/tests/thymeleaf-tests-core/aot.map'),
    ('attoparser',          'thymeleaf-deps/attoparser/aot.map'),
    ('ognl',                'thymeleaf-deps/ognl/aot.map'),
    ('slf4j',               'thymeleaf-deps/slf4j/slf4j-api/aot.map'),
    ('unbescape',           'thymeleaf-deps/unbescape-workload/aot.map'),
]
# The tree-merged map lives at the experiment root (produced by orchestrate-combine.sh)
TREE_MAP = 'aot.map'
OUT = os.path.join(HERE, 'upset-tree-overlap.pdf')


def get_pkg(class_name):
    """Return the root package of a JVM class name, stripping array/object descriptor syntax.

    Returns None for anonymous primitives; excludes classes where the package
    cannot be determined (e.g. bare primitive array descriptors).
    """
    name = class_name.strip()
    # Strip leading '[' array descriptor characters (e.g. [[B → B, [Ljava/Foo; → Ljava/Foo;)
    while name.startswith('['):
        name = name[1:]
    # Unwrap object descriptors: Lorg.Foo; → org.Foo
    if name.startswith('L') and name.endswith(';'):
        name = name[1:-1]
    if not name:
        return None
    # No dot → bare primitive or unnamed; skip unless it's a known primitive letter
    if '.' not in name:
        return name if name in PRIMITIVES else None
    parts = name.split('.')
    # com.* has a two-level canonical root (e.g. com.sun, com.google)
    if parts[0] == 'com' and len(parts) >= 2:
        return parts[0] + '.' + parts[1]
    return parts[0]


def normalize(raw):
    """Strip JVM array ('[') and object ('L...;') descriptor wrappers from a class name."""
    name = raw
    while name.startswith('['):
        name = name[1:]
    if name.startswith('L') and name.endswith(';'):
        name = name[1:-1]
    return name


def extract_app_classes(map_path):
    """Parse an aot.map log file and return the set of non-JDK class names.

    The map format emits '@@ Class <id> <descriptor>' lines; we parse those,
    normalize the descriptor, and drop anything whose root package is JDK-owned.
    """
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


# --- load sets ---
print('Loading APP class sets...')
contents = {'TreeCache': extract_app_classes(TREE_MAP)}
print(f'  {"TreeCache":<26}  {len(contents["TreeCache"]):>6} APP classes')
for label, path in DEPS:
    s = extract_app_classes(path)
    print(f'  {label:<26}  {len(s):>6} APP classes')
    contents[label] = s

# --- build pairwise-exclusive Series explicitly (preserves zero-count bars) ---
# For each dep, count classes in TreeCache AND that dep but in NO other dep.
# Using an explicit MultiIndex series keeps bars with zero overlap visible in the plot.
dep_labels = [label for label, _ in DEPS]
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

# --- colours: one per dep, matching bar + dot row ---
palette = plt.cm.tab10(np.linspace(0, 0.6, len(dep_labels)))

upset = UpSet(filtered,
              subset_size='sum',
              show_counts=True,
              sort_by='cardinality',
              totals_plot_elements=0,   # remove set-size bar chart on the left
              other_dots_color='#b8cce4',  # soft blue instead of gray
              element_size=32)

for label, color in zip(dep_labels, palette):
    upset.style_subsets(present=label, facecolor=color, edgecolor='none')

axes_dict = upset.plot()
fig = plt.gcf()
# let upsetplot auto-size width; only constrain height
fig.set_size_inches(fig.get_size_inches()[0], 3.6)
fig.savefig(OUT, bbox_inches='tight', pad_inches=0.05)
print(f'\nWritten {OUT}')
