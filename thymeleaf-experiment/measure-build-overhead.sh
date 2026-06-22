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

measure_mvn "thymeleaf"   "thymeleaf/tests/thymeleaf-tests-core"
measure_mvn "attoparser"  "thymeleaf-deps/attoparser"
measure_mvn "ognl"        "thymeleaf-deps/ognl"

# slf4j: multi-module repo, only slf4j-api is needed
# Note: slf4j-api's tree-merge profile has <activation><jdk>[17,)</jdk></activation>
# so '-P !tree-merge' is required for the baseline to suppress auto-activation.
# slf4j parent POM defaults reuseForks=false; match tree-merge behaviour with -DreuseForks=true.
info "[slf4j-api] warmup (populate Maven local repo)"
sh -c "cd 'thymeleaf-deps/slf4j' && mvn clean test -B -Drat.skip=true -DforkCount=1 -DreuseForks=true -P '!tree-merge' -pl slf4j-api || true"
timed sh -c "cd 'thymeleaf-deps/slf4j' && mvn clean test -B -Drat.skip=true -DforkCount=1 -DreuseForks=true -P '!tree-merge' -pl slf4j-api || true"
t_base_slf4j=$LAST_MS
rm -f "thymeleaf-deps/slf4j/slf4j-api/cache.aot"
timed sh -c "cd 'thymeleaf-deps/slf4j' && mvn clean test -B -Drat.skip=true -Ptree-merge -pl slf4j-api || true"
t_cache_slf4j=$LAST_MS
[[ -f "thymeleaf-deps/slf4j/slf4j-api/cache.aot" ]] || log "WARN: slf4j-api/cache.aot not produced"
ovhd_slf4j=$(awk "BEGIN{printf \"%.1f\", 100*($t_cache_slf4j-$t_base_slf4j)/$t_base_slf4j}")
echo "slf4j-api,$t_base_slf4j,$t_cache_slf4j,$ovhd_slf4j" | tee -a "$CSV"

# unbescape: no test suite; use workload jar
measure_workload "unbescape" \
    "thymeleaf-deps/unbescape-workload/cache.aot" \
    "thymeleaf-deps/unbescape-workload/target/unbescape-workload-fat.jar" \
    --add-opens java.base/java.lang=ALL-UNNAMED \
    --add-opens java.base/java.util=ALL-UNNAMED

# ── Merge step ────────────────────────────────────────────────────────────────

CACHE_PATHS=(
  "thymeleaf/tests/thymeleaf-tests-core/cache.aot"
  "thymeleaf-deps/attoparser/cache.aot"
  "thymeleaf-deps/ognl/cache.aot"
  "thymeleaf-deps/slf4j/slf4j-api/cache.aot"
  "thymeleaf-deps/unbescape-workload/cache.aot"
)

FAT_JAR="benchmark/target/benchmark-fat.jar"
[[ -f "$FAT_JAR" ]] || { log "SKIP merge — fat jar not found: $FAT_JAR"; exit 0; }
for p in "${CACHE_PATHS[@]}"; do
  [[ -f "$p" ]] || { log "SKIP merge — missing $p"; exit 0; }
done

BASE_AOT="${CACHE_PATHS[0]}"
MERGE_INPUTS="$(IFS=:; echo "${CACHE_PATHS[*]}")"

info "[merge] assembling tree.aot"
rm -f tree.aot
timed java -Xlog:aot=info \
  -Xlog:aot+map=trace,aot+map+oops=trace,aot=warning:file=aot.map:none:filesize=0 \
  --add-opens java.base/java.lang=ALL-UNNAMED \
  --add-opens java.base/java.util=ALL-UNNAMED \
  -XX:AOTMode=merge \
  -XX:AOTCache="$BASE_AOT" \
  -XX:AOTMergeInputs="$MERGE_INPUTS" \
  -XX:AOTCacheOutput=tree.aot \
  -cp "$FAT_JAR" \
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
