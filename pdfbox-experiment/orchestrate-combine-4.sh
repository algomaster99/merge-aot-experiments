#!/bin/bash
# Merge all per-artifact AOT caches into tree.aot for pdfbox-app.
# Extends orchestrate-combine-3.sh to include bcprov, bcutil, bcpkix, and commons-logging.
set -euo pipefail

log() { echo -e "\033[1;32m[$(date '+%H:%M:%S')] $*\033[0m"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

log "Java version:"
java -version

# ── Per-artifact AOT cache paths ─────────────────────────────────────────────
CACHE_PATHS=(
    # pdfbox modules (chain-built; base cache must be first in AOTMergeInputs)
    "pdfbox/io/cache.aot"
    "pdfbox/fontbox/cache.aot"
    "pdfbox/xmpbox/cache.aot"
    "pdfbox/pdfbox/cache.aot"
    "pdfbox/tools/cache.aot"
    # third-party deps (pdfbox-deps/)
    "pdfbox-deps/pdfbox-jbig2/cache.aot"
    "pdfbox-deps/apache-commons-io/cache.aot"
    "pdfbox-deps/commons-logging-workload/cache.aot"
    # BouncyCastle (recorded against per-module fat-jar workloads — see each
    # bc-java-*-workload/README.md for why Gradle's tests cannot host AOT
    # recording for this library)
    "pdfbox-deps/bc-java-prov-workload/cache.aot"
    "pdfbox-deps/bc-java-util-workload/cache.aot"
    "pdfbox-deps/bc-java-pkix-workload/cache.aot"
)

MISSING=0
for cache in "${CACHE_PATHS[@]}"; do
    if [[ ! -f "$cache" ]]; then
        echo "Missing: $cache" >&2
        MISSING=1
    fi
done
if [[ "$MISSING" -ne 0 ]]; then
    echo "One or more AOT caches are missing. Run the relevant generate-aot.sh scripts first." >&2
    exit 1
fi
log "All ${#CACHE_PATHS[@]} module caches found."

# ── Classpath (classes/JARs for every artifact) ───────────────────────────────
# BC / commons-logging entries point at the shaded workload fat jars — the
# exact jars each cache.aot was recorded against, so classes resolve by the
# same bytes HotSpot archived at record time.
CP_ENTRIES=(
    # pdfbox app fat jar covers all pdfbox module classes
    "pdfbox/app/target/pdfbox-app-3.0.7.jar"
    # third-party deps
    "pdfbox-deps/pdfbox-jbig2/target/classes"
    "pdfbox-deps/apache-commons-io/target/classes"
    "pdfbox-deps/commons-logging-workload/target/commons-logging-workload-1.0-SNAPSHOT.jar"
    # BouncyCastle
    "pdfbox-deps/bc-java-prov-workload/target/bc-java-prov-workload-1.0-SNAPSHOT.jar"
    "pdfbox-deps/bc-java-util-workload/target/bc-java-util-workload-1.0-SNAPSHOT.jar"
    "pdfbox-deps/bc-java-pkix-workload/target/bc-java-pkix-workload-1.0-SNAPSHOT.jar"
)

# ── Merge ─────────────────────────────────────────────────────────────────────
BASE_AOT="pdfbox/pdfbox/cache.aot"
OUTPUT_AOT="tree.aot"
MERGE_INPUTS="$(IFS=:; echo "${CACHE_PATHS[*]}")"
CLASSPATH="$(IFS=:; echo "${CP_ENTRIES[*]}")"

log "Creating $OUTPUT_AOT (base=pdfbox/pdfbox/cache.aot, ${#CACHE_PATHS[@]} inputs)"
rm -f "$OUTPUT_AOT"

java -Xlog:aot \
    -XX:AOTMode=merge \
    -XX:AOTCache="$BASE_AOT" \
    -XX:AOTMergeInputs="$MERGE_INPUTS" \
    -XX:AOTCacheOutput="$OUTPUT_AOT" \
    -cp "$CLASSPATH" \
    -version

test -f "$OUTPUT_AOT"
log "$OUTPUT_AOT created ($(du -sh "$OUTPUT_AOT" | cut -f1))"
