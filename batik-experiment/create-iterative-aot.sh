#!/bin/bash
# Builds an AOT cache incrementally, one workload at a time, using the
# one-step "-XX:AOTCache=<base> -XX:AOTCacheOutput=<next>" workflow added in
# https://github.com/openjdk/jdk/pull/31344 ("iterative training for AOT
# one-step workflow"). Each step loads the cache produced by the previous
# step as its base and folds the new workload's classes into the output —
# no AOTMode=record/create/merge needed, and no AOTMode=merge support is
# required from the JDK (the build under test does not have it).
#
# Point JAVA_BIN at the JDK build that contains the PR before running, e.g.:
#   JAVA_BIN=~/Desktop/tools/jdk/build/linux-x86_64-server-release-aot-re-training/images/jdk/bin/java \
#     ./create-iterative-aot.sh
set -euo pipefail

log()  { echo -e "\033[1;32m[$(date '+%H:%M:%S')] $*\033[0m"; }
fail() { echo -e "\033[1;31mERROR: $*\033[0m" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

JAVA_BIN="${JAVA_BIN:-java}"
FAT_JAR="benchmark/target/benchmark-fat.jar"
MAIN="dev.batikexp.Main"
WORK_DIR="workload-tmp"
JAVA_ARGS=(-Djava.awt.headless=true -cp "$FAT_JAR")

log "Java binary: $JAVA_BIN"
"$JAVA_BIN" -version

[[ -f "$FAT_JAR" ]] || fail "$FAT_JAR not found — run: cd benchmark && mvn package -DskipTests"

# Training order for the iterative cache.
OPS=(svg-parse svg-to-png svg-to-jpeg svg-generate)

mkdir -p "$WORK_DIR"
"$JAVA_BIN" "${JAVA_ARGS[@]}" "$MAIN" prepare "$WORK_DIR"

prev_aot=""
for i in "${!OPS[@]}"; do
  op="${OPS[$i]}"
  step=$(( i + 1 ))
  out_aot="iterative-step${step}-${op}.aot"

  if [ -f "$out_aot" ]; then
    log "$out_aot already exists, skipping."
    prev_aot="$out_aot"
    continue
  fi

  base_args=()
  if [ -n "$prev_aot" ]; then
    base_args=(-XX:AOTCache="$prev_aot")
    log "Step $step: folding '$op' into $prev_aot -> $out_aot"
  else
    log "Step $step: training '$op' from scratch -> $out_aot"
  fi

  "$JAVA_BIN" \
    "${base_args[@]}" \
    -XX:AOTCacheOutput="$out_aot" \
    -XX:+AOTClassLinking \
    "${JAVA_ARGS[@]}" "$MAIN" "$op" "$WORK_DIR"

  test -f "$out_aot"
  log "$out_aot created ($(du -sh "$out_aot" | cut -f1))"
  prev_aot="$out_aot"
done

cp -f "$prev_aot" iterative.aot
log "Final iterative cache: iterative.aot (copy of $prev_aot)"
