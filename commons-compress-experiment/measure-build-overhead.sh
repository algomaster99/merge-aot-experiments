#!/bin/bash
# Measure build-time overhead of tree-combine AOT cache production.
# Baseline: mvn clean test -P '!tree-merge'  (no cache produced)
# Cache:    mvn clean test -Ptree-merge       (cache.aot produced per module)
# Merge:    java -XX:AOTMode=merge ...        (tree.aot assembled)
# Output:   build-overhead.csv
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

log()  { echo -e "\033[1;32m[$(date '+%H:%M:%S')] $*\033[0m"; }
info() { echo -e "\033[1;34m  >> $*\033[0m"; }

CSV="build-overhead.csv"
echo "component,baseline_ms,cache_ms,overhead_pct" > "$CSV"
log "Output: $CSV"
log "Java: $(java -version 2>&1 | head -1)"

# Wall-clock timer; stores result in LAST_MS.
LAST_MS=0
timed() {
    local _s
    _s=$(date +%s%3N)
    "$@"
    LAST_MS=$(( $(date +%s%3N) - _s ))
}

# Measure overhead for a maven module.
# Usage: measure_mvn <label> <dir> [extra mvn args...]
measure_mvn() {
    local label="$1" dir="$2"; shift 2
    local t_base t_cache ovhd

    info "[$label] baseline"
    rm -f "$dir/cache.aot"
    timed sh -c "cd '$dir' && mvn clean test -B -Drat.skip=true -P '!tree-merge' $* || true"
    t_base=$LAST_MS

    info "[$label] cache production"
    rm -f "$dir/cache.aot"
    timed sh -c "cd '$dir' && mvn clean test -B -Drat.skip=true -Ptree-merge $* || true"
    t_cache=$LAST_MS

    [[ -f "$dir/cache.aot" ]] || log "WARN: $dir/cache.aot not produced — check for test failures"
    ovhd=$(awk "BEGIN{printf \"%.1f\", 100*($t_cache-$t_base)/$t_base}")
    echo "$label,$t_base,$t_cache,$ovhd" | tee -a "$CSV"
}

# ── Components ────────────────────────────────────────────────────────────────

measure_mvn "commons-lang"  "commons-compress-deps/commons-lang"
measure_mvn "commons-codec" "commons-compress-deps/commons-codec"
measure_mvn "commons-io"    "commons-compress-deps/apache-commons-io"
measure_mvn "commons-compress" "commons-compress"

# ── Merge step ────────────────────────────────────────────────────────────────

CACHE_PATHS=(
  "commons-compress-deps/commons-lang/cache.aot"
  "commons-compress-deps/commons-codec/cache.aot"
  "commons-compress-deps/apache-commons-io/cache.aot"
  "commons-compress/cache.aot"
)
JAR_PATHS=(
  "commons-compress-deps/commons-lang/target/classes"
  "commons-compress-deps/commons-codec/target/classes"
  "commons-compress-deps/apache-commons-io/target/classes"
  "commons-compress/target/classes"
)

for p in "${CACHE_PATHS[@]}"; do
  [[ -f "$p" ]] || { log "SKIP merge — missing $p"; exit 0; }
done

BASE_AOT="commons-compress/cache.aot"
MERGE_INPUTS="$(IFS=:; echo "${CACHE_PATHS[*]}")"
CLASSPATH="$(IFS=:; echo "${JAR_PATHS[*]}")"

info "[merge] assembling tree.aot"
rm -f tree.aot
timed java -Xlog:aot \
  -Xlog:aot=info \
  -Xlog:aot+map=trace,aot+map+oops=trace,aot=warning:file=aot.map:none:filesize=0 \
  -XX:AOTMode=merge \
  --add-modules java.instrument \
  --add-opens java.base/java.io=ALL-UNNAMED \
  --add-opens java.base/java.lang=ALL-UNNAMED \
  --add-opens java.base/java.lang.reflect=ALL-UNNAMED \
  --add-opens java.base/java.time=ALL-UNNAMED \
  --add-opens java.base/java.time.chrono=ALL-UNNAMED \
  --add-opens java.base/java.util=ALL-UNNAMED \
  -XX:AOTCache="$BASE_AOT" \
  -XX:AOTMergeInputs="$MERGE_INPUTS" \
  -XX:AOTCacheOutput=tree.aot \
  -cp "$CLASSPATH" \
  -version
echo "merge,0,$LAST_MS,N/A" | tee -a "$CSV"

# ── Summary ───────────────────────────────────────────────────────────────────

log "=== Summary ==="
awk -F, 'NR==1{print; next}
  $1!="merge"{base+=$2; cache+=$3}
  $1=="merge"{merge=$3}
  END{
    total_base=base; total_cache=cache+merge;
    printf "total baseline : %d ms\ntotal with-cache: %d ms\noverhead        : %.1f%%\n",
      total_base, total_cache, 100*(total_cache-total_base)/total_base
  }' "$CSV"
