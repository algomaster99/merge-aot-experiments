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
#
#   thymeleaf/tests/thymeleaf-tests-core/   mvn test -Ptree-merge
#   thymeleaf-deps/attoparser/               mvn test -Ptree-merge
#   thymeleaf-deps/ognl/                     mvn test -Ptree-merge
#   thymeleaf-deps/slf4j/                    mvn test -Ptree-merge -pl slf4j-api
#   thymeleaf-deps/unbescape-workload/       mvn package && java -XX:AOTCacheOutput=cache.aot -jar target/unbescape-workload-fat.jar
CACHE_PATHS=(
  "thymeleaf/tests/thymeleaf-tests-core/cache.aot"
  "thymeleaf-deps/attoparser/cache.aot"
  "thymeleaf-deps/ognl/cache.aot"
  "thymeleaf-deps/slf4j/slf4j-api/cache.aot"
  "thymeleaf-deps/unbescape-workload/cache.aot"
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
