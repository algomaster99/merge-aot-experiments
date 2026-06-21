#!/usr/bin/env python3
"""Print LaTeX table rows (Size, Classes, App%) for all BioJava AOT caches.

App% = fraction of archived classes whose top-level package is not JDK-internal
(i.e. not java/jdk/sun/javax).  Run from anywhere — paths are relative to this file.
"""
import re, os, sys, argparse

PRIMITIVES = frozenset('ZBCSIFJD')
JDK = {'java', 'jdk', 'sun', 'javax', 'com.sun'} | PRIMITIVES

HERE = os.path.dirname(os.path.abspath(__file__))

ROWS = [
    ('biojava-core',      'biojava/biojava-core/cache.aot',           'biojava/biojava-core/aot.map'),
    ('biojava-alignment', 'biojava/biojava-alignment/cache.aot',       'biojava/biojava-alignment/aot.map'),
    ('biojava-aa-prop',   'biojava/biojava-aa-prop/cache.aot',         'biojava/biojava-aa-prop/aot.map'),
    ('biojava-structure', 'biojava/biojava-structure/cache.aot',       'biojava/biojava-structure/aot.map'),
    ('forester',          'biojava-deps/forester/cache.aot',           'biojava-deps/forester/aot.map'),
    ('commons-codec',     'biojava-deps/commons-codec/cache.aot',      'biojava-deps/commons-codec/aot.map'),
    ('slf4j-api',         'biojava-deps/slf4j/slf4j-api/cache.aot',   'biojava-deps/slf4j/slf4j-api/aot.map'),
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


def analyze(cache_path, map_path, debug=False):
    size_mb = os.path.getsize(os.path.join(HERE, cache_path)) / 1024 / 1024
    with open(os.path.join(HERE, map_path), 'rb') as f:
        data = f.read().decode('utf-8', errors='replace')
    jdk_cls = app_cls = 0
    for line in data.splitlines():
        m = re.match(r'.*@@ Class\s+\d+\s+(\S+)', line)
        if not m:
            continue
        raw = m.group(1)
        pkg = get_pkg(raw)
        if pkg is None:
            if debug:
                print(f'  SKIP    {raw}')
            continue
        if pkg in JDK:
            jdk_cls += 1
            if debug:
                print(f'  JDK     {raw}')
        else:
            app_cls += 1
            if debug:
                print(f'  APP     {raw}')
    return size_mb, jdk_cls, app_cls


def fmt_row(label, size_mb, jdk_cls, app_cls, bold_size=False):
    size_str = f'{size_mb:.0f}\\,MB'
    if bold_size:
        size_str = f'\\textbf{{{size_str}}}'
    jdk_str = f'{jdk_cls:>6,}'
    app_str = f'{app_cls:>6,}'
    return f'{label:<28} & --- & {size_str} & {jdk_str} & {app_str} \\\\'


parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
parser.add_argument('--debug', metavar='MAP_FILE', nargs='?', const='',
                    help='dump every classified class; omit MAP_FILE to list known maps')
args = parser.parse_args()

if args.debug is not None:
    all_rows = [(c, m) for _, c, m in ROWS + [('tree.aot', *TREE)]]
    if args.debug == '':
        print('Known map paths:')
        for _, m in all_rows:
            print(f'  {m}')
        sys.exit(0)
    match = next(((c, m) for c, m in all_rows if m == args.debug or m.endswith(args.debug)), None)
    if match is None:
        parser.error(f'no row with map path matching {args.debug!r}\nKnown:\n' +
                     '\n'.join(f'  {m}' for _, m in all_rows))
    cache_path, map_path = match
    print(f'cache: {cache_path}')
    print(f'map:   {map_path}')
    size_mb, jdk_cls, app_cls = analyze(cache_path, map_path, debug=True)
    total = jdk_cls + app_cls
    print(f'\n=> {total} classes: {jdk_cls} JDK ({jdk_cls/total*100:.1f}%), {app_cls} app ({app_cls/total*100:.1f}%), {size_mb:.2f} MB')
    sys.exit(0)

missing = [p for _, c, m in ROWS + [('', *TREE)] for p in (c, m)
           if not os.path.exists(os.path.join(HERE, p))]
if missing:
    print('ERROR: missing files:\n  ' + '\n  '.join(missing), file=sys.stderr)
    sys.exit(1)

print(r'\multicolumn{5}{@{}l}{\textit{biojava}} \\')
for i, (label, cache, mapf) in enumerate(ROWS):
    prefix = 'App:' if i == 0 else 'Dep:'
    print(fmt_row(f'{prefix} {label}', *analyze(cache, mapf)))
print(fmt_row(r'\toolname   biojava-core', *analyze(*TREE), bold_size=True))
print(r'\midrule')
