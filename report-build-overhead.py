#!/usr/bin/env python3
"""Print build-overhead.csv as a terminal table or LaTeX tabular.

Usage:
  python3 report-build-overhead.py [build-overhead.csv]
  python3 report-build-overhead.py --latex [build-overhead.csv]

The CSV is produced by measure-build-overhead.sh in each experiment directory.
Columns: component, baseline_ms, cache_ms, overhead_pct
"""
import csv, sys, argparse, os

parser = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
parser.add_argument('csv_file', nargs='?', default='build-overhead.csv')
parser.add_argument('--latex', action='store_true', help='emit LaTeX tabular instead')
args = parser.parse_args()

if not os.path.exists(args.csv_file):
    print(f'ERROR: {args.csv_file} not found — run measure-build-overhead.sh first', file=sys.stderr)
    sys.exit(1)

with open(args.csv_file) as f:
    rows = list(csv.DictReader(f))

def ms_to_s(ms_str):
    return int(ms_str) / 1000

# Totals (exclude merge row)
build_rows = [r for r in rows if r['component'] != 'merge']
merge_rows  = [r for r in rows if r['component'] == 'merge']

total_base  = sum(int(r['baseline_ms']) for r in build_rows)
total_cache = sum(int(r['cache_ms'])    for r in build_rows)
merge_ms    = int(merge_rows[0]['cache_ms']) if merge_rows else 0
total_with_merge = total_cache + merge_ms
total_overhead   = 100 * (total_with_merge - total_base) / total_base if total_base else 0

if args.latex:
    print(r'\begin{tabular}{@{}l r r r@{}}')
    print(r'\toprule')
    print(r'\textbf{Component} & \textbf{Baseline (s)} & \textbf{Cache prod. (s)} & \textbf{Overhead (\%)} \\')
    print(r'\midrule')
    for r in build_rows:
        base_s  = ms_to_s(r['baseline_ms'])
        cache_s = ms_to_s(r['cache_ms'])
        ovhd    = r['overhead_pct']
        sign    = '+' if float(ovhd) >= 0 else ''
        print(f"  {r['component']:<28} & {base_s:>8.1f} & {cache_s:>8.1f} & {sign}{ovhd} \\\\")
    if merge_rows:
        print(r'\midrule')
        print(f"  {'merge step':<28} & {'---':>8} & {ms_to_s(merge_rows[0]['cache_ms']):>8.1f} & {'N/A':>6} \\\\")
    print(r'\midrule')
    sign = '+' if total_overhead >= 0 else ''
    print(f"  {'\\textbf{{Total}}':<28} & {total_base/1000:>8.1f} & {total_with_merge/1000:>8.1f} & {sign}{total_overhead:.1f} \\\\")
    print(r'\bottomrule')
    print(r'\end{tabular}')
else:
    # Terminal table
    col_w = [max(len('Component'), max(len(r['component']) for r in rows)),
             max(len('Baseline (s)'), 12),
             max(len('Cache prod. (s)'), 15),
             max(len('Overhead (%)'), 12)]

    sep = '+' + '+'.join('-' * (w + 2) for w in col_w) + '+'
    def row_line(cells):
        return '| ' + ' | '.join(str(c).ljust(col_w[i]) for i, c in enumerate(cells)) + ' |'

    print(sep)
    print(row_line(['Component', 'Baseline (s)', 'Cache prod. (s)', 'Overhead (%)']))
    print(sep)
    for r in build_rows:
        base_s  = f"{ms_to_s(r['baseline_ms']):.1f}"
        cache_s = f"{ms_to_s(r['cache_ms']):.1f}"
        ovhd    = r['overhead_pct']
        sign    = '+' if float(ovhd) >= 0 else ''
        print(row_line([r['component'], base_s, cache_s, f'{sign}{ovhd}%']))
    if merge_rows:
        print(sep)
        print(row_line(['merge step', '---', f"{ms_to_s(merge_rows[0]['cache_ms']):.1f}", 'N/A']))
    print(sep)
    sign = '+' if total_overhead >= 0 else ''
    print(row_line(['TOTAL', f'{total_base/1000:.1f}', f'{total_with_merge/1000:.1f}',
                    f'{sign}{total_overhead:.1f}%']))
    print(sep)
