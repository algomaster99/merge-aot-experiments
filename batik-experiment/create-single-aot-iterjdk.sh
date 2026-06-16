#!/bin/bash
# Same as create-single-aot.sh, but built with a configurable JAVA_BIN and
# written to single-iterjdk-{op}.aot so caches built with the iterative-AOT
# JDK build (PR 31344) don't collide with the single-{op}.aot files already
# built with the stock JDK for the original experiment.
set -euo pipefail

log()  { echo -e "\033[1;32m[$(date '+%H:%M:%S')] $*\033[0m"; }
fail() { echo -e "\033[1;31mERROR: $*\033[0m" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

JAVA_BIN="${JAVA_BIN:-java}"
FAT_JAR="benchmark/target/benchmark-fat.jar"
MAIN="dev.batikexp.Main"
WORK_DIR="workload-tmp"
OPS=(svg-parse svg-to-png svg-to-jpeg svg-generate)
JAVA_ARGS=(-Djava.awt.headless=true -cp "$FAT_JAR")

log "Java binary: $JAVA_BIN"
"$JAVA_BIN" -version

[[ -f "$FAT_JAR" ]] || fail "$FAT_JAR not found — run: cd benchmark && mvn package -DskipTests"

mkdir -p "$WORK_DIR"
log "Preparing workload inputs"
"$JAVA_BIN" "${JAVA_ARGS[@]}" "$MAIN" prepare "$WORK_DIR"

for op in "${OPS[@]}"; do
  aot="single-iterjdk-${op}.aot"
  conf="single-iterjdk-${op}.aotconf"
  if [[ -f "$aot" ]]; then
    log "$aot already exists, skipping."
    continue
  fi
  log "Creating $aot (training op: $op)"
  rm -f "$conf"
  "$JAVA_BIN" -XX:AOTMode=record -XX:AOTConfiguration="$conf" \
    -XX:+AOTClassLinking \
    "${JAVA_ARGS[@]}" "$MAIN" "$op" "$WORK_DIR"
  [[ -f "$conf" ]] || fail "AOT configuration file was not produced for op=$op"
  "$JAVA_BIN" -XX:AOTMode=create \
    -XX:AOTConfiguration="$conf" \
    -XX:AOTCache="$aot" \
    -XX:+AOTClassLinking \
    "${JAVA_ARGS[@]}"
  [[ -f "$aot" ]] || fail "$aot was not created"
  log "$aot created ($(du -sh "$aot" | cut -f1))"
done
