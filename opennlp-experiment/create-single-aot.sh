#!/bin/bash
# Creates one single-{op}.aot per workload for the cross-workload experiment.
# Records against the self-contained fat JAR (benchmark-1.0-SNAPSHOT.jar).
set -euo pipefail

log() { echo -e "\033[1;32m[$(date '+%H:%M:%S')] $*\033[0m"; }
fail() { echo -e "\033[1;31mERROR: $*\033[0m" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

log "Java version:"
java -version

FAT_JAR="benchmark/target/benchmark-1.0-SNAPSHOT.jar"
MAIN="opennlp.bench.Main"
WORK_DIR="workload-tmp"
OPS=("train-sentdetect" "train-postag" "train-postag-morfologik")

[[ -f "$FAT_JAR" ]] || fail "$FAT_JAR not found — run: cd benchmark && mvn package -DskipTests"

OPENS=(
  --add-opens java.base/java.io=ALL-UNNAMED
  --add-opens java.base/java.lang=ALL-UNNAMED
  --add-opens java.base/java.lang.reflect=ALL-UNNAMED
  --add-opens java.base/java.util=ALL-UNNAMED
  --add-opens java.base/jdk.internal.loader=ALL-UNNAMED
)

mkdir -p "$WORK_DIR"
log "Preparing workload data..."
java "${OPENS[@]}" -cp "$FAT_JAR" "$MAIN" prepare "$WORK_DIR"

for op in "${OPS[@]}"; do
  aot="single-${op}.aot"
  conf="single-${op}.aotconf"
  if [ -f "$aot" ]; then
    log "$aot already exists, skipping."
    continue
  fi
  log "Creating $aot (training op: $op)"
  rm -f "$conf"
  java -XX:AOTMode=record -XX:AOTConfiguration="$conf" \
    -XX:+AOTClassLinking \
    "${OPENS[@]}" \
    -cp "$FAT_JAR" "$MAIN" "$op" "$WORK_DIR"
  [[ -f "$conf" ]] || fail "AOTConfiguration not produced for $op"
  java -XX:AOTMode=create -XX:AOTConfiguration="$conf" \
    -XX:AOTCache="$aot" \
    -XX:+AOTClassLinking \
    "${OPENS[@]}" \
    -cp "$FAT_JAR"
  [[ -f "$aot" ]] || fail "$aot was not created"
  log "$aot created ($(du -sh "$aot" | cut -f1))"
done
