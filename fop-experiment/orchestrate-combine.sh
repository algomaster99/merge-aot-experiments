#!/bin/bash
set -euo pipefail

log()  { echo -e "\033[1;32m[$(date '+%H:%M:%S')] $*\033[0m"; }
fail() { echo -e "\033[1;31mERROR: $*\033[0m" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

log "Java version:"
java -version

# Per-dependency cache.aot files merged into tree.aot.
#
# FOP's runtime dependency tree overlaps heavily with the batik and pdfbox
# experiments, so the dependency forks (and their `tree-merge` Maven profiles)
# are reused — only fop-core/fop-events/fop-util are new. Record each cache
# before running this script:
#
#   fop/fop-core/                    mvn test -P tree-merge   (FOP's own test suite)
#   fop-deps/batik/batik-test-old/   mvn test -P tree-merge   (reuse batik fork @ 1.18)
#   fop-deps/xmlgraphics-commons/    mvn test -P tree-merge
#   fop-deps/commons-io/             mvn test
#   fop-deps/commons-logging-workload/  java -XX:AOTCacheOutput=cache.aot ...
#   fop-deps/fontbox/                mvn test -P tree-merge   (reuse pdfbox fork)
#
CACHE_PATHS=(
  "fop/fop-core/cache.aot"
  "fop-workload.aot"
  "fop-deps/batik/batik-test-old/cache.aot"
  "fop-deps/xmlgraphics-commons/cache.aot"
  "fop-deps/commons-io/cache.aot"
  "fop-deps/qdox/cache.aot"
  "fop-deps/commons-logging-workload/cache.aot"
  "fop-deps/xml-apis-workload/cache.aot"
  "fop-deps/xml-apis-ext-workload/cache.aot"
  "fop-deps/fontbox/fontbox/cache.aot"
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
