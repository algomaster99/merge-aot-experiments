#!/bin/bash
set -euo pipefail

log() { echo -e "\033[1;32m[$(date '+%H:%M:%S')] $*\033[0m"; }
fail() { echo -e "\033[1;31mERROR: $*\033[0m" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

log "Java version:"
java -version

CACHE_PATHS=(
  "commons-validator-deps/commons-beanutils/cache.aot"
  "commons-validator-deps/commons-digester/cache.aot"
  "commons-validator-deps/commons-logging/cache.aot"
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

for path in "${CACHE_PATHS[@]}"; do
  [[ -f "$path" ]] || fail "Missing required input: $path"
done
for path in "${JAR_PATHS[@]}"; do
  [[ -d "$path" ]] || fail "Missing required input: $path"
done

BASE_AOT="commons-validator/cache.aot"
OUTPUT_AOT="tree.aot"
MERGE_INPUTS="$(IFS=:; echo "${CACHE_PATHS[*]}")"
CLASSPATH="$(IFS=:; echo "${JAR_PATHS[*]}")"

rm -f "$OUTPUT_AOT"

log "Merging ${#CACHE_PATHS[@]} caches into $OUTPUT_AOT"
java -Xlog:aot \
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
  -XX:AOTCacheOutput="$OUTPUT_AOT" \
  -cp "$CLASSPATH" \
  -version

[[ -f "$OUTPUT_AOT" ]] || fail "tree.aot was not created"
log "$OUTPUT_AOT created ($(du -sh "$OUTPUT_AOT" | cut -f1))"
