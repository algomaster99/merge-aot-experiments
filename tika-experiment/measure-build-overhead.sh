#!/bin/bash
# Measure build-time overhead of tree-combine AOT cache production.
# Baseline: mvn clean test -P '!tree-merge'  (no cache produced)
# Cache:    mvn clean test -Ptree-merge       (cache.aot produced per module)
# Merge:    java -XX:AOTMode=merge ...        (tree.aot assembled)
# Output:   build-overhead.csv
#
# Prerequisite: run 'mvn install -DskipTests' in tika/ before running this
# script so inter-module dependencies are in the local Maven repo.
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

TIKA_PARSERS="tika/tika-parsers/tika-parsers-standard/tika-parsers-standard-modules"

# ── Components ────────────────────────────────────────────────────────────────

measure_mvn "tika-core"          "tika/tika-core"
measure_mvn "tika-serialization" "tika/tika-serialization"
measure_mvn "tika-parser-pdf"    "$TIKA_PARSERS/tika-parser-pdf-module"
measure_mvn "tika-parser-msft"   "$TIKA_PARSERS/tika-parser-microsoft-module"
measure_mvn "tika-parser-image"  "$TIKA_PARSERS/tika-parser-image-module"
measure_mvn "tika-parser-pkg"    "$TIKA_PARSERS/tika-parser-pkg-module"
measure_mvn "tika-parser-code"   "$TIKA_PARSERS/tika-parser-code-module"
measure_mvn "tika-parser-av"     "$TIKA_PARSERS/tika-parser-audiovideo-module"
measure_mvn "tika-parser-misc"   "$TIKA_PARSERS/tika-parser-miscoffice-module"
measure_mvn "tika-parser-apple"  "$TIKA_PARSERS/tika-parser-apple-module"
measure_mvn "tika-parser-web"    "$TIKA_PARSERS/tika-parser-webarchive-module"
measure_mvn "tika-parser-crypto" "$TIKA_PARSERS/tika-parser-crypto-module"
measure_mvn "tika-parser-cad"    "$TIKA_PARSERS/tika-parser-cad-module"
measure_mvn "tika-parser-font"   "$TIKA_PARSERS/tika-parser-font-module"
measure_mvn "tika-parser-news"   "$TIKA_PARSERS/tika-parser-news-module"
measure_mvn "tika-parsers-pkg"   "tika/tika-parsers/tika-parsers-standard/tika-parsers-standard-package"

# ── Merge step ────────────────────────────────────────────────────────────────

JAR="tika/tika-app/target/tika-app-3.3.1.jar"
[[ -f "$JAR" ]] || { log "SKIP merge — $JAR not found"; exit 0; }

CACHE_PATHS=(
  "tika/tika-core/cache.aot"
  "tika/tika-serialization/cache.aot"
  "$TIKA_PARSERS/tika-parser-pdf-module/cache.aot"
  "$TIKA_PARSERS/tika-parser-microsoft-module/cache.aot"
  "$TIKA_PARSERS/tika-parser-image-module/cache.aot"
  "$TIKA_PARSERS/tika-parser-pkg-module/cache.aot"
  "$TIKA_PARSERS/tika-parser-code-module/cache.aot"
  "$TIKA_PARSERS/tika-parser-audiovideo-module/cache.aot"
  "$TIKA_PARSERS/tika-parser-miscoffice-module/cache.aot"
  "$TIKA_PARSERS/tika-parser-apple-module/cache.aot"
  "$TIKA_PARSERS/tika-parser-webarchive-module/cache.aot"
  "$TIKA_PARSERS/tika-parser-crypto-module/cache.aot"
  "$TIKA_PARSERS/tika-parser-cad-module/cache.aot"
  "$TIKA_PARSERS/tika-parser-font-module/cache.aot"
  "$TIKA_PARSERS/tika-parser-news-module/cache.aot"
  "tika/tika-parsers/tika-parsers-standard/tika-parsers-standard-package/cache.aot"
)

for p in "${CACHE_PATHS[@]}"; do
  [[ -f "$p" ]] || { log "SKIP merge — missing $p"; exit 0; }
done

BASE_AOT="${CACHE_PATHS[0]}"
MERGE_INPUTS="$(IFS=:; echo "${CACHE_PATHS[*]}")"

info "[merge] assembling tree.aot"
rm -f tree.aot
timed java \
  -Xlog:aot=info \
  -Xlog:aot+map=trace,aot+map+oops=trace,aot=warning:file=aot.map:none:filesize=0 \
  -Djava.awt.headless=true \
  -XX:AOTMode=merge \
  -XX:AOTCache="$BASE_AOT" \
  -XX:AOTMergeInputs="$MERGE_INPUTS" \
  -XX:AOTCacheOutput=tree.aot \
  -cp "$JAR" \
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
