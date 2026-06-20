#!/bin/bash
# Creates one single-{op}.aot per workload for the cross-workload experiment.
set -euo pipefail

log()  { echo -e "\033[1;32m[$(date '+%H:%M:%S')] $*\033[0m"; }
fail() { echo -e "\033[1;31mERROR: $*\033[0m" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

BENCH_JAR="benchmark/target/benchmark-fat.jar"
CHECKSTYLE_CORE="checkstyle/target/classes"
CP="$BENCH_JAR:$CHECKSTYLE_CORE"
MAIN="dev.checkstyleexp.Main"
CONFIGS_DIR="$SCRIPT_DIR/configs"
SOURCES_DIR="$SCRIPT_DIR/sources"
OPS=(sun google javadoc naming sizes)
JAVA_BIN="${JAVA_BIN:-java}"

[[ -f "$BENCH_JAR" ]] || fail "$BENCH_JAR not found — run: cd benchmark && mvn package -DskipTests"
[[ -d "$CHECKSTYLE_CORE" ]] || fail "$CHECKSTYLE_CORE not found — run: cd checkstyle && mvn compile -DskipTests"

for op in "${OPS[@]}"; do
  aot="single-${op}.aot"
  conf="single-${op}.aotconf"
  if [[ -f "$aot" ]]; then
    log "$aot already exists, skipping."
    continue
  fi
  log "Creating $aot (training op: $op)"
  rm -f "$conf"
  "$JAVA_BIN" -XX:AOTMode=record -XX:AOTConfiguration="$conf" \
    -XX:+AOTClassLinking \
    -cp "$CP" "$MAIN" "$op" "$CONFIGS_DIR" "$SOURCES_DIR"
  [[ -f "$conf" ]] || fail "AOT configuration file was not produced for op=$op"
  "$JAVA_BIN" -XX:AOTMode=create \
    -XX:AOTConfiguration="$conf" \
    -XX:AOTCache="$aot" \
    -XX:+AOTClassLinking \
    -cp "$CP"
  [[ -f "$aot" ]] || fail "$aot was not created"
  log "$aot created ($(du -sh "$aot" | cut -f1))"
done
