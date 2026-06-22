#!/bin/bash
# Continues the iterative AOT chain from pdfbox/tools/iter.aot through the
# third-party dependency workloads, in dependency-tree order:
#
#   pdfbox-app (already in pdfbox reactor chain)
#     └─ bcpkix → bcutil  (train bcutil first, bcpkix after)
#     └─ bcprov           (independent of bcpkix/bcutil)
#     └─ commons-logging  (independent)
#     └─ commons-io       (no workload project — skipped)
#     └─ jbig2-imageio    (no workload project — skipped)
#
# Prerequisites:
#   1. Run the pdfbox reactor chain first to produce pdfbox/tools/iter.aot:
#        cd pdfbox && mvn clean test -Piterative-merge -pl io,fontbox,pdfbox,tools
#   2. Build all dep fat jars (only needed once):
#        (cd pdfbox-deps/bc-java-util-workload && mvn package -q)
#        (cd pdfbox-deps/bc-java-prov-workload  && mvn package -q)
#        (cd pdfbox-deps/bc-java-pkix-workload  && mvn package -q)
#        (cd pdfbox-deps/commons-logging-workload && mvn package -q)
#
# Usage:
#   JAVA_BIN=<aot-re-jdk>/bin/java ./create-iterative-aot-deps.sh
set -euo pipefail

log()  { echo -e "\033[1;32m[$(date '+%H:%M:%S')] $*\033[0m"; }
fail() { echo -e "\033[1;31mERROR: $*\033[0m" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

JAVA_BIN="${JAVA_BIN:-java}"
log "Java binary: $JAVA_BIN"
"$JAVA_BIN" -version

# ── Starting point: final output of the pdfbox reactor chain ──────────────────
PREV_AOT="pdfbox/tools/iter.aot"
[[ -f "$PREV_AOT" ]] || fail "Starting cache not found: $PREV_AOT — run pdfbox reactor first."

# ── Dep chain steps ───────────────────────────────────────────────────────────
# Each entry: "<dep-dir>:<artifact-id>"
# Order: dependencies before dependents
#   bcutil is a dep of bcpkix → train bcutil first via bc-java-util-workload
#   bcprov is independent but used by bcutil workload's fat jar → train next
#   bcpkix depends on bcutil + bcprov → train last among BC
#   commons-logging is independent
STEPS=(
    "pdfbox-deps/bc-java-util-workload:bc-java-util-workload-1.0-SNAPSHOT"
    "pdfbox-deps/bc-java-prov-workload:bc-java-prov-workload-1.0-SNAPSHOT"
    "pdfbox-deps/bc-java-pkix-workload:bc-java-pkix-workload-1.0-SNAPSHOT"
    "pdfbox-deps/commons-logging-workload:commons-logging-workload-1.0-SNAPSHOT"
)

for step in "${STEPS[@]}"; do
    dir="${step%%:*}"
    jar_base="${step##*:}"
    jar="$SCRIPT_DIR/$dir/target/${jar_base}.jar"
    out_aot="$SCRIPT_DIR/$dir/iter.aot"

    [[ -d "$SCRIPT_DIR/$dir" ]] || fail "Dep directory not found: $dir"
    [[ -f "$jar" ]] || fail "Fat jar not found: $jar — run 'mvn package' in $dir first"

    if [[ -f "$out_aot" ]]; then
        log "$out_aot already exists, skipping."
        PREV_AOT="$out_aot"
        continue
    fi

    log "Folding $dir (base: $PREV_AOT) → $out_aot"
    "$JAVA_BIN" \
        -XX:AOTCache="$PREV_AOT" \
        -XX:AOTCacheOutput="$out_aot" \
        -XX:+AOTClassLinking \
        -cp "$jar" \
        com.example.App

    [[ -f "$out_aot" ]] || fail "$out_aot was not created"
    log "$out_aot created ($(du -sh "$out_aot" | cut -f1))"
    PREV_AOT="$out_aot"
done

cp -f "$PREV_AOT" iterative-tree.aot
log "Final iterative cache: iterative-tree.aot ($(du -sh iterative-tree.aot | cut -f1))"
