#!/bin/bash
# Same as create-single-aot.sh, but built with a configurable JAVA_BIN and
# written to single-iterjdk-{op}.aot so caches built with the iterative-AOT
# JDK build (PR 31344) don't collide with the single-{op}.aot files already
# built with the stock JDK for the original experiment.
set -euo pipefail

log() { echo -e "\033[1;32m[$(date '+%H:%M:%S')] $*\033[0m"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

JAVA_BIN="${JAVA_BIN:-java}"
BENCH_JAR="benchmark/target/original-benchmark-1.0-SNAPSHOT.jar"
DEPS_DIR="single-aot-deps"
MAIN="dev.compressexp.Main"
WORK_DIR="workload-tmp"

log "Java binary: $JAVA_BIN"
"$JAVA_BIN" -version

OPS=("gzip-roundtrip" "zip-roundtrip" "tar-roundtrip" "list-archives")

[[ -f "$BENCH_JAR" ]] || { echo "Missing $BENCH_JAR (build benchmark first)" >&2; exit 1; }

# CDS dump (record/create) rejects non-empty directory classpath entries, so
# this must use the JAR-based classpath (already downloaded by create-single-aot.sh).
CP="$BENCH_JAR:\
$DEPS_DIR/commons-compress-1.28.0.jar:\
$DEPS_DIR/commons-lang3-3.20.0.jar:\
$DEPS_DIR/commons-codec-1.21.0.jar:\
$DEPS_DIR/commons-io-2.20.0.jar"

mkdir -p "$WORK_DIR"
"$JAVA_BIN" -cp "$CP" "$MAIN" prepare "$WORK_DIR"

for op in "${OPS[@]}"; do
  aot="single-iterjdk-${op}.aot"
  conf="single-iterjdk-${op}.aotconf"
  if [ -f "$aot" ]; then
    log "$aot already exists, skipping."
    continue
  fi
  log "Creating $aot (training op: $op)"
  rm -f "$conf"
  "$JAVA_BIN" -XX:AOTMode=record -XX:AOTConfiguration="$conf" \
    -XX:+AOTClassLinking \
    -cp "$CP" "$MAIN" "$op" "$WORK_DIR"
  test -f "$conf"
  "$JAVA_BIN" -XX:AOTMode=create -XX:AOTConfiguration="$conf" \
    -XX:AOTCache="$aot" \
    -XX:+AOTClassLinking \
    -cp "$CP"
  test -f "$aot"
  log "$aot created."
done
