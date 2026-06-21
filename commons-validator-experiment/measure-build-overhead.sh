#!/bin/bash
# Measure build-time overhead of tree-combine AOT cache production.
# Baseline: mvn clean test -P '!tree-merge'  (no cache produced)
# Cache:    mvn clean test -Ptree-merge       (cache.aot produced per module)
# Workload: java -jar fat.jar vs java -XX:AOTCacheOutput=... -jar fat.jar
# Merge:    java -XX:AOTMode=merge ...        (tree.aot assembled)
# Output:   build-overhead.csv
#
# NOTE: commons-validator-deps/commons-logging is a git submodule.
# It must be checked out to branch 'aotcache-setup-commons-validator' of
# algomaster99/commons-logging (currently on 'fop-experiment' by mistake).
# Run: git submodule update --remote commons-validator-deps/commons-logging
# or:  git -C commons-validator-deps/commons-logging checkout aotcache-setup-commons-validator
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

measure_mvn "commons-beanutils"   "commons-validator-deps/commons-beanutils"
measure_mvn "commons-digester"    "commons-validator-deps/commons-digester"

# commons-logging: facade with no test suite — measure java command overhead.
# The submodule must be on branch aotcache-setup-commons-validator.
# Adjust the fat jar name below once the correct branch is checked out.
LOGGING_DIR="commons-validator-deps/commons-logging"
LOGGING_AOT="$LOGGING_DIR/cache.aot"
# Try common fat-jar naming conventions
for _jar in \
    "$LOGGING_DIR/target/commons-logging-workload-fat.jar" \
    "$LOGGING_DIR/target/commons-logging-workload-1.0-SNAPSHOT.jar"; do
    if [[ -f "$_jar" ]]; then
        LOGGING_JAR="$_jar"
        break
    fi
done
if [[ -z "${LOGGING_JAR:-}" ]]; then
    log "SKIP commons-logging — fat jar not found (submodule on wrong branch?)"
else
    measure_workload "commons-logging" "$LOGGING_AOT" "$LOGGING_JAR"
fi

measure_mvn "commons-collections" "commons-validator-deps/commons-collections"
measure_mvn "commons-validator"   "commons-validator"

# ── Merge step ────────────────────────────────────────────────────────────────

CACHE_PATHS=(
  "commons-validator-deps/commons-beanutils/cache.aot"
  "commons-validator-deps/commons-digester/cache.aot"
  "$LOGGING_AOT"
  "commons-validator-deps/commons-collections/cache.aot"
  "commons-validator/cache.aot"
)
JAR_PATHS=(
  "commons-validator-deps/commons-beanutils/target/classes"
  "commons-validator-deps/commons-digester/target/classes"
  "commons-validator-deps/commons-logging/target/classes"
  "commons-validator-deps/commons-collections/target/classes"
  "commons-validator/target/classes"
)

for p in "${CACHE_PATHS[@]}"; do
  [[ -f "$p" ]] || { log "SKIP merge — missing $p"; exit 0; }
done
for p in "${JAR_PATHS[@]}"; do
  [[ -e "$p" ]] || { log "SKIP merge — missing $p"; exit 0; }
done

BASE_AOT="commons-validator/cache.aot"
MERGE_INPUTS="$(IFS=:; echo "${CACHE_PATHS[*]}")"
CLASSPATH="$(IFS=:; echo "${JAR_PATHS[*]}")"

info "[merge] assembling tree.aot"
rm -f tree.aot
timed java -Xlog:aot \
  -Xlog:aot=info \
  -Xlog:aot+link:file="aotlink-tree-create.log" \
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
    printf "total baseline : %d ms\ntotal with-cache: %d ms\noverhead        : %.1f%%\n",
      base, cache+merge, 100*(cache+merge-base)/base
  }' "$CSV"
