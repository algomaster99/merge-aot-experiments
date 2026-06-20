#!/usr/bin/env python3
"""Print Markdown + LaTeX build-overhead table from build-overhead.tsv.

When GITHUB_STEP_SUMMARY is set, also appends the Markdown table there.
Run from the batik-experiment directory (or any directory containing build-overhead.tsv).
"""
import os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
tsv_path = os.path.join(HERE, "build-overhead.tsv")

rows = []
with open(tsv_path) as f:
    for line in f:
        parts = line.rstrip("\n").split("\t")
        module, ctype = parts[0], parts[1]
        baseline_ms, cache_ms, overhead_ms = int(parts[2]), int(parts[3]), int(parts[4])
        rows.append((module, ctype, baseline_ms, cache_ms, overhead_ms))

total_b = sum(r[2] for r in rows)
total_c = sum(r[3] for r in rows)
total_o = sum(r[4] for r in rows)


def pct(o, b):
    return f"{o/b*100:+.1f}%" if b else "—"


# ── Markdown ──────────────────────────────────────────────────────────────────

md_lines = [
    "## Build overhead of AOT cache creation\n",
    "| Module | Cache Type | Baseline (s) | With Cache (s) | Overhead (s) | % Increase |",
    "|---|---|---:|---:|---:|---:|",
]
for m, ct, b, c, o in rows:
    b_s = f"{b/1000:.1f}" if b else "—"
    md_lines.append(f"| {m} | {ct} | {b_s} | {c/1000:.1f} | {o/1000:.1f} | {pct(o, b)} |")
total_pct = pct(total_o, total_b)
md_lines.append(
    f"| **Total** | | **{total_b/1000:.1f}** | **{total_c/1000:.1f}** | **{total_o/1000:.1f}** | **{total_pct}** |"
)
md_table = "\n".join(md_lines)

print(md_table)

summary_path = os.environ.get("GITHUB_STEP_SUMMARY")
if summary_path:
    with open(summary_path, "a") as out:
        out.write(md_table + "\n\n")

# ── LaTeX ─────────────────────────────────────────────────────────────────────

latex_lines = [
    r"\begin{tabular}{llrrrr}",
    r"\toprule",
    r"Module & Cache Type & Baseline (s) & With Cache (s) & Overhead (s) & \% Increase \\",
    r"\midrule",
]
for m, ct, b, c, o in rows:
    b_s = r"\textemdash" if b == 0 else f"{b/1000:.1f}"
    pct_s = r"\textemdash" if b == 0 else f"{o/b*100:+.1f}\\%"
    latex_lines.append(f"{m} & {ct} & {b_s} & {c/1000:.1f} & {o/1000:.1f} & {pct_s} \\\\")
total_pct_latex = r"\textemdash" if total_b == 0 else f"{total_o/total_b*100:+.1f}\\%"
latex_lines += [
    r"\midrule",
    f"\\textbf{{Total}} & & {total_b/1000:.1f} & {total_c/1000:.1f} & {total_o/1000:.1f} & {total_pct_latex} \\\\",
    r"\bottomrule",
    r"\end{tabular}",
]

print("\n```latex")
print("\n".join(latex_lines))
print("```")
