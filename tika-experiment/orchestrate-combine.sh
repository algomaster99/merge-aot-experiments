#!/bin/bash
set -euo pipefail

log()  { echo -e "\033[1;32m[$(date '+%H:%M:%S')] $*\033[0m"; }
fail() { echo -e "\033[1;31mERROR: $*\033[0m" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

log "Java version:"
java -version

# Fat jar — used as the classpath for the merge step.
JAR="tika/tika-app/target/tika-app-3.3.1.jar"
[[ -f "$JAR" ]] || fail "$JAR not found"

TIKA_PARSERS="tika/tika-parsers/tika-parsers-standard/tika-parsers-standard-modules"

# Component test-suite caches (produced by mvn test -Ptree-merge in each module).
CACHE_PATHS=(
  "tika/tika-core/cache.aot"
  "tika/tika-serialization/cache.aot"
  "${TIKA_PARSERS}/tika-parser-pdf-module/cache.aot"
  "${TIKA_PARSERS}/tika-parser-microsoft-module/cache.aot"
  "${TIKA_PARSERS}/tika-parser-image-module/cache.aot"
  "${TIKA_PARSERS}/tika-parser-pkg-module/cache.aot"
  "${TIKA_PARSERS}/tika-parser-code-module/cache.aot"
  "${TIKA_PARSERS}/tika-parser-audiovideo-module/cache.aot"
  "${TIKA_PARSERS}/tika-parser-miscoffice-module/cache.aot"
  "${TIKA_PARSERS}/tika-parser-apple-module/cache.aot"
  "${TIKA_PARSERS}/tika-parser-webarchive-module/cache.aot"
  "${TIKA_PARSERS}/tika-parser-crypto-module/cache.aot"
  "${TIKA_PARSERS}/tika-parser-cad-module/cache.aot"
  "${TIKA_PARSERS}/tika-parser-font-module/cache.aot"
  "${TIKA_PARSERS}/tika-parser-news-module/cache.aot"
  "tika/tika-parsers/tika-parsers-standard/tika-parsers-standard-package/cache.aot"
)

for path in "${CACHE_PATHS[@]}"; do
  [[ -f "$path" ]] || fail "Missing cache: $path — run mvn test -Ptree-merge in that module"
done

BASE_AOT="${CACHE_PATHS[0]}"
MERGE_INPUTS="$(IFS=:; echo "${CACHE_PATHS[*]}")"
OUTPUT_AOT="tree.aot"

rm -f "$OUTPUT_AOT"

log "Merging ${#CACHE_PATHS[@]} caches → $OUTPUT_AOT"
java \
  -Xlog:aot=info \
  -Xlog:aot+map=trace,aot+map+oops=trace,aot=warning:file=aot.map:none:filesize=0 \
  -Djava.awt.headless=true \
  -XX:AOTMode=merge \
  -XX:AOTCache="$BASE_AOT" \
  -XX:AOTMergeInputs="$MERGE_INPUTS" \
  -XX:AOTCacheOutput="$OUTPUT_AOT" \
  -cp "$JAR" \
  -version

[[ -f "$OUTPUT_AOT" ]] || fail "tree.aot was not created"
log "$OUTPUT_AOT created ($(du -sh "$OUTPUT_AOT" | cut -f1))"
