#!/bin/bash
set -euo pipefail

log() { echo -e "\033[1;32m[$(date '+%H:%M:%S')] $*\033[0m"; }

log "Java version:"
java -version

SINGLE_AOT="single.aot"
SINGLE_JAR="pdfbox/app/target/pdfbox-app-3.0.7.jar"
TEST_PDF="pdfbox/test.pdf"

test -f "$SINGLE_AOT" || { echo "Missing $SINGLE_AOT (run create-single-aot.sh first)" >&2; exit 1; }
log "single.aot found."

log "Creating tree.aot (base=pdfbox/tools/cache.aot, inputs=jbig2 cache + commons-io cache)"
rm -f tree.aot

java -Xlog:aot \
  -XX:AOTMode=merge \
  -XX:AOTCache=pdfbox/pdfbox/cache.aot \
  -XX:AOTMergeInputs="pdfbox-deps/pdfbox-jbig2/cache.aot:pdfbox-deps/apache-commons-io/cache.aot:pdfbox/io/cache.aot:pdfbox/fontbox/cache.aot:pdfbox/xmpbox/cache.aot:pdfbox/pdfbox/cache.aot:pdfbox/preflight/cache.aot:pdfbox/tools/cache.aot:pdfbox/examples/cache.aot" \
  -XX:AOTCacheOutput=tree.aot \
  -cp "pdfbox-deps/pdfbox-jbig2/target/classes/:pdfbox-deps/apache-commons-io/target/classes/:pdfbox/app/target/pdfbox-app-3.0.7.jar" \
  -version

test -f tree.aot
log "tree.aot created."
