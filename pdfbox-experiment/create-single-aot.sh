#!/bin/bash
set -euo pipefail

log() { echo -e "\033[1;32m[$(date '+%H:%M:%S')] $*\033[0m"; }

log "Java version:"
java -version

SINGLE_AOT="single.aot"
SINGLE_JAR="pdfbox/app/target/pdfbox-app-3.0.7.jar"
TEST_PDF="pdfbox/test.pdf"

if [ -f "$SINGLE_AOT" ]; then
  log "single.aot already exists, skipping creation."
  exit 0
fi

log "Creating single.aot (export:text)"
rm -f "$SINGLE_AOT"

test -f "$SINGLE_JAR" || { echo "Missing $SINGLE_JAR (build app first)" >&2; exit 1; }
test -f "$TEST_PDF" || { echo "Missing $TEST_PDF" >&2; exit 1; }

java -Xlog:aot -XX:AOTCacheOutput="$SINGLE_AOT" -jar "$SINGLE_JAR" export:text -i "$TEST_PDF"

test -f "$SINGLE_AOT"
log "single.aot created."
