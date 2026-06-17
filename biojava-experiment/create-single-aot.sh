#!/bin/bash
# Creates one single-{op}.aot per workload for the cross-workload (AOTCache) experiment.
set -euo pipefail

log()  { echo -e "\033[1;32m[$(date '+%H:%M:%S')] $*\033[0m"; }
fail() { echo -e "\033[1;31mERROR: $*\033[0m" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

log "Java version:"
java -version

FAT_JAR="benchmark/target/benchmark-fat.jar"
MAIN="dev.biojavaexp.Main"
WORK_DIR="workload-tmp"
OPS=(genbank-write msa aa-prop pdb-parse)

JAVA_ARGS=(-cp "$FAT_JAR")

[[ -f "$FAT_JAR" ]] || fail "$FAT_JAR not found — run: cd benchmark && mvn package -DskipTests"

mkdir -p "$WORK_DIR"
log "Preparing workload inputs"
java "${JAVA_ARGS[@]}" "$MAIN" prepare "$WORK_DIR"

for op in "${OPS[@]}"; do
  aot="single-${op}.aot"
  conf="single-${op}.aotconf"
  if [[ -f "$aot" ]]; then
    log "$aot already exists, skipping."
    continue
  fi
  log "Creating $aot (training op: $op)"
  rm -f "$conf"
  java -XX:AOTMode=record -XX:AOTConfiguration="$conf" \
    -XX:+AOTClassLinking \
    "${JAVA_ARGS[@]}" "$MAIN" "$op" "$WORK_DIR"
  [[ -f "$conf" ]] || fail "AOT configuration file was not produced for op=$op"
  java -XX:AOTMode=create \
    -XX:AOTConfiguration="$conf" \
    -XX:AOTCache="$aot" \
    -XX:+AOTClassLinking \
    "${JAVA_ARGS[@]}"
  [[ -f "$aot" ]] || fail "$aot was not created"
  log "$aot created ($(du -sh "$aot" | cut -f1))"
done
