#!/bin/bash
# Measures the extra time that AOT cache generation adds to each build step.
# For each module: runs the baseline build, then reruns with -Ptree-merge (or
# equivalent), and records (baseline_ms, cache_ms, overhead_ms) in a TSV.
# Workload-only modules (no test suite) record only the recording step time.
# Finally times orchestrate-combine.sh and prints a Markdown + LaTeX summary.
#
# Usage:
#   ./measure-build-overhead.sh [--output FILE]   (default: build-overhead.tsv)
#
# Prerequisites:
#   - Custom JDK (with AOT merge) on PATH
#   - batik modules already installed into local Maven repo:
#       cd batik && mvn install -DskipTests -q
#   - benchmark fat jar built:
#       cd benchmark && mvn package -DskipTests -q

set -euo pipefail

log()  { echo -e "\033[1;32m[$(date '+%H:%M:%S')] $*\033[0m"; }
sep()  { echo -e "\033[0;90m$(printf '─%.0s' {1..72})\033[0m"; }
fail() { echo -e "\033[1;31mERROR: $*\033[0m" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

TSV_FILE="build-overhead.tsv"
if [[ "${1:-}" == "--output" && -n "${2:-}" ]]; then
  TSV_FILE="$2"
fi

> "$TSV_FILE"

# ---------------------------------------------------------------------------
# Helper: time a command, append result to TSV
#   record_time <module> <cache_type> <col: baseline|cache|overhead> <ms>
# We accumulate into parallel arrays then write one row per module at the end.
# ---------------------------------------------------------------------------

# time_cmd <label> <dir> <cmd...>
# Returns elapsed ms in variable ELAPSED_MS
time_cmd() {
  local label="$1" dir="$2"; shift 2
  log "$label"
  local t0
  t0=$(date +%s%3N)
  (cd "$dir" && "$@")
  ELAPSED_MS=$(( $(date +%s%3N) - t0 ))
}

# ---------------------------------------------------------------------------
# test-suite modules: baseline vs tree-merge
# ---------------------------------------------------------------------------

measure_test_suite() {
  local module="$1" dir="$2" mvn_args="${3:--pl .}"
  sep
  log "[$module] baseline (mvn clean test)"
  time_cmd "$module baseline" "$dir" mvn clean test $mvn_args -Drat.skip -q
  local baseline_ms=$ELAPSED_MS

  log "[$module] with tree-merge cache (mvn clean test -Ptree-merge)"
  find "$dir" -name "*.aot" -type f -delete
  time_cmd "$module tree-merge" "$dir" mvn clean test -Ptree-merge $mvn_args -Drat.skip -q
  local cache_ms=$ELAPSED_MS

  local overhead_ms=$(( cache_ms - baseline_ms ))
  printf '%s\ttest-suite (mvn test)\t%d\t%d\t%d\n' \
    "$module" "$baseline_ms" "$cache_ms" "$overhead_ms" >> "$TSV_FILE"
  log "$module: baseline=${baseline_ms}ms  cache=${cache_ms}ms  overhead=${overhead_ms}ms"
}

measure_test_suite "batik-test-old"        "batik/batik-test-old"
measure_test_suite "xmlgraphics-commons"   "batik-deps/xmlgraphics-commons"

sep
log "[commons-io] baseline (mvn clean test)"
time_cmd "commons-io baseline" "batik-deps/commons-io" mvn clean test -Drat.skip -q
baseline_ms=$ELAPSED_MS
log "[commons-io] with tree-merge cache (mvn clean test -Ptree-merge)"
find batik-deps/commons-io -name "*.aot" -type f -delete
time_cmd "commons-io cache" "batik-deps/commons-io" mvn clean test -Ptree-merge -Drat.skip -q
cache_ms=$ELAPSED_MS
overhead_ms=$(( cache_ms - baseline_ms ))
printf 'commons-io\ttest-suite (mvn test)\t%d\t%d\t%d\n' \
  "$baseline_ms" "$cache_ms" "$overhead_ms" >> "$TSV_FILE"
log "commons-io: baseline=${baseline_ms}ms  cache=${cache_ms}ms  overhead=${overhead_ms}ms"

# ---------------------------------------------------------------------------
# workload-only modules (no test suite): mvn package baseline vs +java record
# ---------------------------------------------------------------------------

measure_workload() {
  local module="$1" dir="$2" jar="$3" extra_java_args="${4:-}"
  sep
  log "[$module] baseline (mvn package -DskipTests)"
  time_cmd "$module baseline" "$dir" mvn package -DskipTests -q
  local baseline_ms=$ELAPSED_MS

  log "[$module] with AOT recording (mvn package + java -XX:AOTCacheOutput)"
  time_cmd "$module record" "$dir" bash -c "
    mvn package -DskipTests -q
    java -Xlog:aot+map=trace,aot+map+oops=trace,aot=warning:file=aot.map:none:filesize=0 \
      $extra_java_args -XX:AOTCacheOutput=cache.aot -jar $jar
  "
  local cache_ms=$ELAPSED_MS
  local overhead_ms=$(( cache_ms - baseline_ms ))
  printf '%s\tworkload (mvn pkg + java record)\t%d\t%d\t%d\n' \
    "$module" "$baseline_ms" "$cache_ms" "$overhead_ms" >> "$TSV_FILE"
  log "$module: baseline=${baseline_ms}ms  cache=${cache_ms}ms  overhead=${overhead_ms}ms"
}

measure_workload "commons-logging" "batik-deps/commons-logging-workload" \
  "target/commons-logging-workload-fat.jar"
measure_workload "xml-apis"        "batik-deps/xml-apis-workload" \
  "target/xml-apis-workload-fat.jar"
measure_workload "xml-apis-ext"    "batik-deps/xml-apis-ext-workload" \
  "target/xml-apis-ext-workload-fat.jar"

# ---------------------------------------------------------------------------
# orchestrate-combine.sh — purely additive, no baseline equivalent
# ---------------------------------------------------------------------------

sep
log "[tree-merge] orchestrate-combine.sh"
time_cmd "orchestrate-combine" "$SCRIPT_DIR" bash orchestrate-combine.sh
combine_ms=$ELAPSED_MS
printf 'tree-merge (orchestrate-combine)\tAOT merge\t0\t%d\t%d\n' \
  "$combine_ms" "$combine_ms" >> "$TSV_FILE"
log "tree-merge: ${combine_ms}ms"

# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------

sep
python3 - <<'PYEOF'
import os, sys

tsv_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "build-overhead.tsv")

rows = []
with open(tsv_path) as f:
    for line in f:
        parts = line.rstrip("\n").split("\t")
        module, ctype, baseline_ms, cache_ms, overhead_ms = \
            parts[0], parts[1], int(parts[2]), int(parts[3]), int(parts[4])
        rows.append((module, ctype, baseline_ms, cache_ms, overhead_ms))

total_baseline = sum(r[2] for r in rows)
total_cache    = sum(r[3] for r in rows)
total_overhead = sum(r[4] for r in rows)

# Markdown
print("\n## Build overhead of AOT cache creation\n")
print("| Module | Cache Type | Baseline (s) | With Cache (s) | Overhead (s) |")
print("|---|---|---:|---:|---:|")
for module, ctype, b, c, o in rows:
    b_s = f"{b/1000:.1f}" if b else "—"
    print(f"| {module} | {ctype} | {b_s} | {c/1000:.1f} | {o/1000:.1f} |")
print(f"| **Total** | | **{total_baseline/1000:.1f}** | **{total_cache/1000:.1f}** | **{total_overhead/1000:.1f}** |")

# LaTeX
print("\n```latex")
print(r"\begin{tabular}{llrrr}")
print(r"\toprule")
print(r"Module & Cache Type & Baseline (s) & With Cache (s) & Overhead (s) \\")
print(r"\midrule")
for module, ctype, b, c, o in rows:
    b_s = r"\textemdash" if b == 0 else f"{b/1000:.1f}"
    print(f"{module} & {ctype} & {b_s} & {c/1000:.1f} & {o/1000:.1f} \\\\")
print(r"\midrule")
print(f"\\textbf{{Total}} & & {total_baseline/1000:.1f} & {total_cache/1000:.1f} & {total_overhead/1000:.1f} \\\\")
print(r"\bottomrule")
print(r"\end{tabular}")
print("```")
PYEOF
