#!/bin/bash
set -euo pipefail

log() { echo -e "\033[1;32m[$(date '+%H:%M:%S')] $*\033[0m"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log "Java version:"
java -version

MCS_JAR="$SCRIPT_DIR/mcs/target/mcs-0.9.7.jar"

CACHE_PATHS=(
  "$SCRIPT_DIR/mcs-deps/jackson-jr/jr-objects/cache.aot"
  "$SCRIPT_DIR/mcs/cache.aot"
)

MISSING=0
for cache in "${CACHE_PATHS[@]}"; do
  if [[ ! -f "$cache" ]]; then
    echo "Missing $cache" >&2
    MISSING=1
  fi
done
if [[ "$MISSING" -ne 0 ]]; then
  echo "One or more expected caches are missing. Build them first with: mvn test -Ptree-merge" >&2
  exit 1
fi

log "All expected module caches found."

BASE_AOT="${CACHE_PATHS[0]}"
OUTPUT_AOT="$SCRIPT_DIR/tree.aot"
MERGE_INPUTS="${CACHE_PATHS[1]}"

log "Creating tree.aot (base=jackson-jr/cache.aot, inputs=mcs)"
rm -f "$OUTPUT_AOT"

java -Xlog:aot \
  -XX:AOTMode=merge \
  -XX:AOTCache="$BASE_AOT" \
  -XX:AOTMergeInputs="$MERGE_INPUTS" \
  -XX:AOTCacheOutput="$OUTPUT_AOT" \
  -cp "$MCS_JAR" \
  -version

test -f "$OUTPUT_AOT"
log "tree.aot created at $OUTPUT_AOT"
