#!/bin/bash
set -euo pipefail

log()  { echo -e "\033[1;32m[$(date '+%H:%M:%S')] $*\033[0m"; }
fail() { echo -e "\033[1;31mERROR: $*\033[0m" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Cache recorded by: cd checkstyle && mvn clean test -P tree-merge -Dmaven.test.failure.ignore=true
CACHE_PATHS=(
  "checkstyle/cache.aot"
)

BENCH_JAR="benchmark/target/benchmark-fat.jar"
CHECKSTYLE_CORE="checkstyle/target/classes"
CP="$BENCH_JAR:$CHECKSTYLE_CORE"
OUTPUT_AOT="tree.aot"

[[ -f "$BENCH_JAR" ]] || fail "$BENCH_JAR not found — run: cd benchmark && mvn package -DskipTests"
[[ -d "$CHECKSTYLE_CORE" ]] || fail "$CHECKSTYLE_CORE not found — build checkstyle first"
for path in "${CACHE_PATHS[@]}"; do
  [[ -f "$path" ]] || fail "Missing cache: $path"
done

BASE_AOT="${CACHE_PATHS[0]}"
MERGE_INPUTS="$(IFS=:; echo "${CACHE_PATHS[*]}")"

rm -f "$OUTPUT_AOT"

log "Merging ${#CACHE_PATHS[@]} cache(s) → $OUTPUT_AOT"
java -Xlog:aot=info \
  -Xlog:aot+map=trace,aot+map+oops=trace,aot=warning:file=aot.map:none:filesize=0 \
  -XX:AOTMode=merge \
  -XX:AOTCache="$BASE_AOT" \
  -XX:AOTMergeInputs="$MERGE_INPUTS" \
  -XX:AOTCacheOutput="$OUTPUT_AOT" \
  -cp "$CP" \
  -version

[[ -f "$OUTPUT_AOT" ]] || fail "tree.aot was not created"
log "$OUTPUT_AOT created ($(du -sh "$OUTPUT_AOT" | cut -f1))"
