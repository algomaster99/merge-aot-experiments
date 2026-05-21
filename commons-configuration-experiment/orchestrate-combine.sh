#!/bin/bash
# Merge all per-artifact AOT caches into tree.aot for the commons-configuration benchmark.
set -euo pipefail

log()  { echo -e "\033[1;32m[$(date '+%H:%M:%S')] $*\033[0m"; }
fail() { echo -e "\033[1;31mERROR: $*\033[0m" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

log "Java version:"
java -version

# ── Per-artifact AOT cache paths ─────────────────────────────────────────────
CACHE_PATHS=(
    "commons-configuration-deps/commons-lang/cache.aot"
    "commons-configuration-deps/commons-text/cache.aot"
    "commons-configuration-deps/commons-beanutils/cache.aot"
    "commons-configuration-deps/commons-collections/cache.aot"
    "commons-configuration-deps/commons-logging-workload/cache.aot"
    "commons-configuration/cache.aot"
)

# ── Classpath entries ─────────────────────────────────────────────────────────
# commons-logging uses the shaded workload fat jar (no test suite — workload jar
# is what cache.aot was recorded against). All others use target/classes.
CP_ENTRIES=(
    "commons-configuration-deps/commons-lang/target/classes"
    "commons-configuration-deps/commons-text/target/classes"
    "commons-configuration-deps/commons-beanutils/target/classes"
    "commons-configuration-deps/commons-collections/target/classes"
    "commons-configuration-deps/commons-logging-workload/target/commons-logging-workload-1.0-SNAPSHOT.jar"
    "commons-configuration/target/classes"
)

MISSING=0
for path in "${CACHE_PATHS[@]}"; do
    [[ -f "$path" ]] || { echo "Missing cache: $path" >&2; MISSING=1; }
done
for path in "${CP_ENTRIES[@]}"; do
    [[ -e "$path" ]] || { echo "Missing classpath entry: $path" >&2; MISSING=1; }
done
[[ "$MISSING" -eq 0 ]] || exit 1
log "All ${#CACHE_PATHS[@]} module caches found."

BASE_AOT="commons-configuration/cache.aot"
OUTPUT_AOT="tree.aot"
MERGE_INPUTS="$(IFS=:; echo "${CACHE_PATHS[*]}")"
CLASSPATH="$(IFS=:; echo "${CP_ENTRIES[*]}")"

rm -f "$OUTPUT_AOT"

log "Creating $OUTPUT_AOT (base=$BASE_AOT, ${#CACHE_PATHS[@]} inputs)"
java -Xlog:aot \
    -Xlog:aot=info \
    -Xlog:aot+link:file="aotlink-tree-create.log" \
    -XX:AOTMode=merge \
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
