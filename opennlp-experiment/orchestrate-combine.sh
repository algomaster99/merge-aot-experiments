#!/bin/bash
set -euo pipefail

log()  { echo -e "\033[1;32m[$(date '+%H:%M:%S')] $*\033[0m"; }
fail() { echo -e "\033[1;31mERROR: $*\033[0m" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

log "Java version:"
java -version

LIB_DIR="opennlp-cli-lib"
[[ -d "$LIB_DIR" ]] || fail "$LIB_DIR not found — run CI setup step first"

OPENNLP_MODULES=(
  "opennlp/opennlp-tools"
  "opennlp/opennlp-morfologik-addon"
)

MORFOLOGIK_MODULES=(
  "opennlp-deps/morfologik/morfologik-fsa-builders"
  "opennlp-deps/morfologik/morfologik-stemming"
  "opennlp-deps/morfologik/morfologik-tools"
)

CACHE_PATHS=()
for mod in "${OPENNLP_MODULES[@]}" "${MORFOLOGIK_MODULES[@]}"; do
  CACHE_PATHS+=("$mod/cache.aot")
done

for path in "${CACHE_PATHS[@]}"; do
  [[ -f "$path" ]] || fail "Missing cache: $path"
done

CP="$(ls "$LIB_DIR"/*.jar | tr '\n' ':')"
BASE_AOT="${CACHE_PATHS[0]}"
MERGE_INPUTS="$(IFS=:; echo "${CACHE_PATHS[*]}")"
OUTPUT_AOT="tree.aot"

rm -f "$OUTPUT_AOT"

log "Merging ${#CACHE_PATHS[@]} caches → $OUTPUT_AOT"
java \
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
  -XX:AOTCacheOutput="$OUTPUT_AOT" \
  -cp "$CP" \
  -version

[[ -f "$OUTPUT_AOT" ]] || fail "tree.aot was not created"
log "$OUTPUT_AOT created ($(du -sh "$OUTPUT_AOT" | cut -f1))"
