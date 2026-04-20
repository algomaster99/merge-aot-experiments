#!/bin/bash
set -euo pipefail

log() { echo -e "\033[1;32m[$(date '+%H:%M:%S')] $*\033[0m"; }
fail() { echo -e "\033[1;31mERROR: $*\033[0m" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

log "Java version:"
java -version

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

for path in "${CACHE_PATHS[@]}" "${JAR_PATHS[@]}"; do
  [[ -f "$path" ]] || fail "Missing required input: $path"
done

BASE_AOT="commons-compress/cache.aot"
OUTPUT_AOT="tree.aot"
MERGE_INPUTS="$(IFS=:; echo "${CACHE_PATHS[*]}")"
CLASSPATH="$(IFS=:; echo "${JAR_PATHS[*]}")"

rm -f "$OUTPUT_AOT"

log "Merging ${#CACHE_PATHS[@]} caches into $OUTPUT_AOT"
java -Xlog:aot \
  -XX:AOTMode=merge \
  --add-modules java.instrument \
  --add-opens java.base/java.io=ALL-UNNAMED \
  -XX:AOTCache="$BASE_AOT" \
  -XX:AOTMergeInputs="$MERGE_INPUTS" \
  -XX:AOTCacheOutput="$OUTPUT_AOT" \
  -cp "$CLASSPATH" \
  -version

[[ -f "$OUTPUT_AOT" ]] || fail "tree.aot was not created"
log "$OUTPUT_AOT created ($(du -sh "$OUTPUT_AOT" | cut -f1))"
