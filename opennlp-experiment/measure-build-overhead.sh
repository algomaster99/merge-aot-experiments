#!/bin/bash
# Measure build-time overhead of tree-combine AOT cache production.
# Baseline: mvn clean test -P '!tree-merge'  (no cache produced)
# Cache:    mvn clean test -Ptree-merge       (cache.aot produced per module)
# Merge:    java -XX:AOTMode=merge ...        (tree.aot assembled)
# Output:   build-overhead.csv
#
# Prerequisite: run 'mvn install -DskipTests' in opennlp/ and opennlp-deps/morfologik/
# before running this script so inter-module dependencies are in the local Maven repo.
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

OPENNLP_DIR="opennlp"
MORFOLOGIK_DIR="opennlp-deps/morfologik"

# ── Components ────────────────────────────────────────────────────────────────

measure_mvn "opennlp-tools"          "$OPENNLP_DIR/opennlp-tools"
measure_mvn "opennlp-morfologik"     "$OPENNLP_DIR/opennlp-morfologik-addon"
measure_mvn "morfologik-fsa-builders" "$MORFOLOGIK_DIR/morfologik-fsa-builders"
measure_mvn "morfologik-stemming"    "$MORFOLOGIK_DIR/morfologik-stemming"
measure_mvn "morfologik-tools"       "$MORFOLOGIK_DIR/morfologik-tools"

# ── Merge step ────────────────────────────────────────────────────────────────

OPENNLP_MODULES=(opennlp-tools opennlp-morfologik-addon)
MORFOLOGIK_MODULES=(morfologik-fsa-builders morfologik-stemming morfologik-tools)

CACHE_PATHS=()
CLASSES_PATHS=()
for mod in "${OPENNLP_MODULES[@]}"; do
  CACHE_PATHS+=("$OPENNLP_DIR/$mod/cache.aot")
  CLASSES_PATHS+=("$OPENNLP_DIR/$mod/target/classes")
done
for mod in "${MORFOLOGIK_MODULES[@]}"; do
  CACHE_PATHS+=("$MORFOLOGIK_DIR/$mod/cache.aot")
  CLASSES_PATHS+=("$MORFOLOGIK_DIR/$mod/target/classes")
done

for p in "${CACHE_PATHS[@]}"; do
  [[ -f "$p" ]] || { log "SKIP merge — missing $p"; exit 0; }
done

# Recompile if target/classes was cleaned
NEED_COMPILE=false
for p in "${CLASSES_PATHS[@]}"; do [[ -d "$p" ]] || { NEED_COMPILE=true; break; }; done
if $NEED_COMPILE; then
    log "Recompiling (target/classes missing after clean)..."
    (cd "$OPENNLP_DIR" && mvn -q -B compile -pl "$(IFS=,; echo "${OPENNLP_MODULES[*]}")" --also-make)
    (cd "$MORFOLOGIK_DIR" && mvn -q -B compile -pl "$(IFS=,; echo "${MORFOLOGIK_MODULES[*]}")" --also-make)
fi

DEPS_DIR="${SCRIPT_DIR}/combine-deps"
mkdir -p "$DEPS_DIR"
(cd "$OPENNLP_DIR" && mvn -q -B dependency:copy-dependencies \
  -DoutputDirectory="$DEPS_DIR" -DincludeScope=compile \
  -DexcludeGroupIds=org.apache.opennlp \
  -pl "$(IFS=,; echo "${OPENNLP_MODULES[*]}")" 2>/dev/null)
(cd "$MORFOLOGIK_DIR" && mvn -q -B dependency:copy-dependencies \
  -DoutputDirectory="$DEPS_DIR" -DincludeScope=compile \
  -DexcludeGroupIds=org.carrot2 \
  -pl "$(IFS=,; echo "${MORFOLOGIK_MODULES[*]}")" 2>/dev/null)

DEP_CP="$(find "$DEPS_DIR" -name '*.jar' | sort | tr '\n' ':' | sed 's/:$//')"
CLASSES_CP="$(IFS=:; echo "${CLASSES_PATHS[*]}")"
CLASSPATH="${CLASSES_CP}:${DEP_CP}"

BASE_AOT="${CACHE_PATHS[0]}"
MERGE_INPUTS="$(IFS=:; echo "${CACHE_PATHS[*]}")"

info "[merge] assembling tree.aot"
rm -f tree.aot
timed java \
  -Xlog:aot=info \
  -Xlog:aot+map=trace,aot+map+oops=trace,aot=warning:file=aot.map:none:filesize=0 \
  --add-opens java.base/java.io=ALL-UNNAMED \
  --add-opens java.base/java.lang=ALL-UNNAMED \
  --add-opens java.base/java.lang.reflect=ALL-UNNAMED \
  --add-opens java.base/java.util=ALL-UNNAMED \
  --add-opens java.base/jdk.internal.loader=ALL-UNNAMED \
  -XX:AOTMode=merge \
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
