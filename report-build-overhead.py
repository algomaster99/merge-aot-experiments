#!/usr/bin/env python3
"""Print build-overhead CSV(s) as a terminal table or a combined LaTeX table.

Usage (terminal, one experiment):
  python3 report-build-overhead.py build-overhead.csv

Usage (LaTeX, one or more experiments combined):
  python3 report-build-overhead.py --latex \\
      batik-experiment/build-overhead.csv \\
      thymeleaf-experiment/build-overhead.csv

  Optional: --caption TEXT  --label TEXT

The CSV is produced by measure-build-overhead.sh in each experiment directory.
Columns: component, baseline_ms, cache_ms, overhead_pct
"""
import csv, sys, argparse, os

parser = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
parser.add_argument('csv_files', nargs='+', metavar='CSV')
parser.add_argument('--latex',   action='store_true', help='emit LaTeX table environment')
parser.add_argument('--caption', default=r'Build time overhead of \toolname{} cache production.',
                    help='LaTeX caption text')
parser.add_argument('--label',   default='tab:rq1-overhead', help='LaTeX label')
args = parser.parse_args()


def load(path):
    with open(path) as f:
        return list(csv.DictReader(f))

def ms_to_s(ms_str):
    return int(ms_str) / 1000

def group_name(path):
    """Derive a short group name from a CSV path, e.g. 'batik-experiment/build-overhead.csv' → 'batik'."""
    d = os.path.basename(os.path.dirname(os.path.abspath(path)))
    return d.removesuffix('-experiment')

def fmt_ovhd(ovhd_str):
    v = float(ovhd_str)
    sign = '+' if v >= 0 else ''
    return f'{sign}{ovhd_str}'


if args.latex:
    print(r'\begin{table}[t]')
    print(r'\centering')
    print(f'\\caption{{{args.caption}}}')
    print(f'\\label{{{args.label}}}')
    print(r'\resizebox{\columnwidth}{!}{%')
    print(r'\begin{tabular}{@{}l r r r@{}}')
    print(r'\toprule')
    print(r'\textbf{Module} & \textbf{Baseline (s)} & \textbf{Cache prod. (s)} & \textbf{Overhead (\%)} \\')
    print(r'\midrule')

    for i, path in enumerate(args.csv_files):
        if not os.path.exists(path):
            print(f'% ERROR: {path} not found', file=sys.stderr)
            continue
        rows = load(path)
        build_rows = [r for r in rows if r['component'] != 'merge']
        merge_rows  = [r for r in rows if r['component'] == 'merge']

        print(f'\\multicolumn{{4}}{{@{{}}l}}{{\\textit{{{group_name(path)}}}}} \\\\')
        for r in build_rows:
            base_s  = f"{ms_to_s(r['baseline_ms']):.1f}"
            cache_s = f"{ms_to_s(r['cache_ms']):.1f}"
            print(f"  {r['component']:<24} & {base_s:>7} & {cache_s:>7} & {fmt_ovhd(r['overhead_pct'])} \\\\")
        if merge_rows:
            merge_s = f"{ms_to_s(merge_rows[0]['cache_ms']):.1f}"
            print(f"  {'merge step':<24} & {'---':>7} & {merge_s:>7} & {'N/A'} \\\\")

        if i < len(args.csv_files) - 1:
            print(r'\midrule')

    print(r'\bottomrule')
    print(r'\end{tabular}%')
    print(r'}')
    print(r'\end{table}')

else:
    for path in args.csv_files:
        if not os.path.exists(path):
            print(f'ERROR: {path} not found — run measure-build-overhead.sh first', file=sys.stderr)
            continue
        rows = load(path)
        build_rows = [r for r in rows if r['component'] != 'merge']
        merge_rows  = [r for r in rows if r['component'] == 'merge']

        total_base        = sum(int(r['baseline_ms']) for r in build_rows)
        total_cache       = sum(int(r['cache_ms'])    for r in build_rows)
        merge_ms          = int(merge_rows[0]['cache_ms']) if merge_rows else 0
        total_with_merge  = total_cache + merge_ms
        total_overhead    = 100 * (total_with_merge - total_base) / total_base if total_base else 0

        col_w = [max(len('Module'), max(len(r['component']) for r in rows)),
                 max(len('Baseline (s)'), 12),
                 max(len('Cache prod. (s)'), 15),
                 max(len('Overhead (%)'), 12)]

        sep = '+' + '+'.join('-' * (w + 2) for w in col_w) + '+'
        def row_line(cells):
            return '| ' + ' | '.join(str(c).ljust(col_w[i]) for i, c in enumerate(cells)) + ' |'

        if len(args.csv_files) > 1:
            print(f'\n=== {group_name(path)} ===')
        print(sep)
        print(row_line(['Module', 'Baseline (s)', 'Cache prod. (s)', 'Overhead (%)']))
        print(sep)
        for r in build_rows:
            print(row_line([r['component'],
                            f"{ms_to_s(r['baseline_ms']):.1f}",
                            f"{ms_to_s(r['cache_ms']):.1f}",
                            f"{fmt_ovhd(r['overhead_pct'])}%"]))
        if merge_rows:
            print(sep)
            print(row_line(['merge step', '---', f"{ms_to_s(merge_rows[0]['cache_ms']):.1f}", 'N/A']))
        print(sep)
        sign = '+' if total_overhead >= 0 else ''
        print(row_line(['TOTAL', f'{total_base/1000:.1f}', f'{total_with_merge/1000:.1f}',
                        f'{sign}{total_overhead:.1f}%']))
        print(sep)
