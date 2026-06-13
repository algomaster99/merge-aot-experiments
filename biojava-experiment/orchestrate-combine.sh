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
# biojava's distributable artifacts are its own sibling modules plus a thin
# tail of third-party libs. The log4j binding is excluded (see benchmark/pom.xml)
# so no module-info-bearing JAR is on the runtime path; slf4j is handled by the
# existing slf4j fork (its MR-JAR module-info is stripped, same as thymeleaf).
# Record each cache before running this script:
#
#   biojava/biojava-core/       mvn test -P tree-merge   (biojava fork, log4j excluded)
#   biojava/biojava-alignment/  mvn test -P tree-merge
#   biojava-deps/forester/      custom workload (no usable test suite; no module-info)
#   biojava-deps/commons-codec/ mvn test                 (forester's dep; reuse fork)
#   biojava-deps/slf4j/slf4j-api/  reuse slf4j fork (module-info stripped)
#
CACHE_PATHS=(
  "biojava/biojava-core/cache.aot"
  "biojava/biojava-alignment/cache.aot"
  "biojava-deps/forester/cache.aot"
  "biojava-deps/commons-codec/cache.aot"
  "biojava-deps/slf4j/slf4j-api/cache.aot"
)

FAT_JAR="benchmark/target/benchmark-fat.jar"
OUTPUT_AOT="tree.aot"

[[ -f "$FAT_JAR" ]] || fail "$FAT_JAR not found — run: cd benchmark && mvn package -DskipTests"

for path in "${CACHE_PATHS[@]}"; do
  [[ -f "$path" ]] || fail "Missing cache: $path"
done

MERGE_INPUTS="$(IFS=:; echo "${CACHE_PATHS[*]}")"

rm -f "$OUTPUT_AOT"

log "Merging ${#CACHE_PATHS[@]} caches → $OUTPUT_AOT"
java -Xlog:aot=info \
  -Xlog:aot+link:file="aotlink-tree-create.log" \
  -XX:AOTMode=merge \
  -XX:AOTMergeInputs="$MERGE_INPUTS" \
  -XX:AOTCacheOutput="$OUTPUT_AOT" \
  -cp "$FAT_JAR" \
  -version

[[ -f "$OUTPUT_AOT" ]] || fail "tree.aot was not created"
log "$OUTPUT_AOT created ($(du -sh "$OUTPUT_AOT" | cut -f1))"
