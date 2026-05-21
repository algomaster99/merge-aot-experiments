#!/bin/bash
set -euo pipefail

log()  { echo -e "\033[1;32m[$(date '+%H:%M:%S')] $*\033[0m"; }
fail() { echo -e "\033[1;31mERROR: $*\033[0m" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

log "Java version:"
java -version

# All cache.aot files produced by the individual recording steps.
# Record each one before running this script:
#   batik/batik-test-old/           mvn test -P tree-merge
#   batik-deps/xmlgraphics-commons/ mvn test -P tree-merge
#   batik-deps/commons-io/          mvn test
#   batik-deps/*/cache.aot          java -XX:AOTCacheOutput=cache.aot -jar <workload>-fat.jar
# Note: Rhino (org.mozilla:rhino) is a transitive dep of batik-script/batik-bridge
# and is recorded as part of the batik-test-old cache when scripted SVG tests run.
CACHE_PATHS=(
  "batik/batik-test-old/cache.aot"
  "batik-deps/xmlgraphics-commons/cache.aot"
  "batik-deps/commons-io/cache.aot"
  "batik-deps/commons-logging-workload/cache.aot"
  "batik-deps/xml-apis-workload/cache.aot"
  "batik-deps/xml-apis-ext-workload/cache.aot"
)

FAT_JAR="benchmark/target/benchmark-fat.jar"
OUTPUT_AOT="tree.aot"

[[ -f "$FAT_JAR" ]] || fail "$FAT_JAR not found — run: cd benchmark && mvn package -DskipTests"

for path in "${CACHE_PATHS[@]}"; do
  [[ -f "$path" ]] || fail "Missing cache: $path"
done

BASE_AOT="${CACHE_PATHS[0]}"
MERGE_INPUTS="$(IFS=:; echo "${CACHE_PATHS[*]}")"

rm -f "$OUTPUT_AOT"

log "Merging ${#CACHE_PATHS[@]} caches → $OUTPUT_AOT"
java -Xlog:aot=info \
  -Xlog:aot+link:file="aotlink-tree-create.log" \
  -XX:AOTMode=merge \
  -Djava.awt.headless=true \
  -XX:AOTCache="$BASE_AOT" \
  -XX:AOTMergeInputs="$MERGE_INPUTS" \
  -XX:AOTCacheOutput="$OUTPUT_AOT" \
  -cp "$FAT_JAR" \
  -version

[[ -f "$OUTPUT_AOT" ]] || fail "tree.aot was not created"
log "$OUTPUT_AOT created ($(du -sh "$OUTPUT_AOT" | cut -f1))"
