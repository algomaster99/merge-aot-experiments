#!/bin/bash
# Measure build-time overhead of tree-combine AOT cache production.
# Baseline: mvn clean test -P '!tree-merge'  (no cache produced)
# Cache:    mvn clean test -Ptree-merge       (cache.aot produced per module)
# Workload: java -jar fat.jar vs java -XX:AOTCacheOutput=... -jar fat.jar
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

LAST_MS=0
timed() {
    local _s
    _s=$(date +%s%3N)
    "$@"
    LAST_MS=$(( $(date +%s%3N) - _s ))
}

measure_mvn() {
    local label="$1" dir="$2"; shift 2
    local t_base t_cache ovhd

    info "[$label] warmup (populate Maven local repo)"
    sh -c "cd '$dir' && mvn clean test -B -Drat.skip=true -P '!tree-merge' $* || true"

    info "[$label] baseline"
    rm -f "$dir/cache.aot"
    timed sh -c "cd '$dir' && mvn clean test -B -Drat.skip=true -P '!tree-merge' $* || true"
    t_base=$LAST_MS

    info "[$label] cache production"
    rm -f "$dir/cache.aot"
    timed sh -c "cd '$dir' && mvn clean test -B -Drat.skip=true -Ptree-merge $* || true"
    t_cache=$LAST_MS

    [[ -f "$dir/cache.aot" ]] || log "WARN: $dir/cache.aot not produced"
    ovhd=$(awk "BEGIN{printf \"%.1f\", 100*($t_cache-$t_base)/$t_base}")
    echo "$label,$t_base,$t_cache,$ovhd" | tee -a "$CSV"
}

# Workload-only component (no test suite — just time the java command).
# Usage: measure_workload <label> <aot_out_path> <fat_jar> [extra_java_args...]
measure_workload() {
    local label="$1" aot_out="$2" fat_jar="$3"; shift 3
    local t_base t_cache ovhd

    [[ -f "$fat_jar" ]] || { log "SKIP $label — fat jar not found: $fat_jar"; return; }

    info "[$label] warmup (populate filesystem cache)"
    java "$@" -jar "$fat_jar" || true

    info "[$label] baseline"
    timed java "$@" -jar "$fat_jar" || true
    t_base=$LAST_MS

    info "[$label] cache production"
    rm -f "$aot_out"
    timed java "$@" -XX:AOTCacheOutput="$aot_out" -jar "$fat_jar" || true
    t_cache=$LAST_MS

    [[ -f "$aot_out" ]] || log "WARN: $aot_out not produced"
    ovhd=$(awk "BEGIN{printf \"%.1f\", 100*($t_cache-$t_base)/$t_base}")
    echo "$label,$t_base,$t_cache,$ovhd" | tee -a "$CSV"
}

# ── Components ────────────────────────────────────────────────────────────────

measure_mvn "commons-lang"        "commons-configuration-deps/commons-lang"
measure_mvn "commons-text"        "commons-configuration-deps/commons-text"
measure_mvn "commons-beanutils"   "commons-configuration-deps/commons-beanutils"
measure_mvn "commons-collections" "commons-configuration-deps/commons-collections"

# commons-logging: no test suite; use workload jar
LOGGING_DIR="commons-configuration-deps/commons-logging-workload"
LOGGING_JAR="$LOGGING_DIR/target/commons-logging-workload-1.0-SNAPSHOT.jar"
LOGGING_AOT="$LOGGING_DIR/cache.aot"
measure_workload "commons-logging" "$LOGGING_AOT" "$LOGGING_JAR"

measure_mvn "commons-configuration" "commons-configuration"

# ── Merge step ────────────────────────────────────────────────────────────────

CACHE_PATHS=(
    "commons-configuration-deps/commons-lang/cache.aot"
    "commons-configuration-deps/commons-text/cache.aot"
    "commons-configuration-deps/commons-beanutils/cache.aot"
    "commons-configuration-deps/commons-collections/cache.aot"
    "$LOGGING_AOT"
    "commons-configuration/cache.aot"
)
CP_ENTRIES=(
    "commons-configuration-deps/commons-lang/target/classes"
    "commons-configuration-deps/commons-text/target/classes"
    "commons-configuration-deps/commons-beanutils/target/classes"
    "commons-configuration-deps/commons-collections/target/classes"
    "$LOGGING_JAR"
    "commons-configuration/target/classes"
)

for p in "${CACHE_PATHS[@]}"; do
  [[ -f "$p" ]] || { log "SKIP merge — missing $p"; exit 0; }
done

BASE_AOT="commons-configuration/cache.aot"
MERGE_INPUTS="$(IFS=:; echo "${CACHE_PATHS[*]}")"
CLASSPATH="$(IFS=:; echo "${CP_ENTRIES[*]}")"

info "[merge] assembling tree.aot"
rm -f tree.aot
timed java -Xlog:aot \
    -Xlog:aot=info \
    -Xlog:aot+map=trace,aot+map+oops=trace,aot=warning:file=aot.map:none:filesize=0 \
    -XX:AOTMode=merge \
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
    printf "total baseline : %d ms\ntotal with-cache: %d ms\noverhead        : %.1f%%\n",
      base, cache+merge, 100*(cache+merge-base)/base
  }' "$CSV"
