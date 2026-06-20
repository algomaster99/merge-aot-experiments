#!/bin/bash
# Record single-{op}.aot by running one training workload with -XX:AOTCacheOutput.
# Usage: ./create-single-aot.sh <workload>
#   workload: analyze-complexity | analyze-style | analyze-naming | analyze-bugs | analyze-coroutines
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TRAIN_OP="${1:-analyze-complexity}"
DETEKT="$SCRIPT_DIR/detekt"
BENCH_JAR="$SCRIPT_DIR/benchmark/target/benchmark-1.0-SNAPSHOT.jar"
EXT_DEPS_CP_FILE="$SCRIPT_DIR/ext-deps-cp.txt"
WORK_DIR="$SCRIPT_DIR/workload-tmp"
AOT_OUT="$SCRIPT_DIR/single-${TRAIN_OP}.aot"
JAVA_BIN="${JAVA_BIN:-java}"
MAIN="dev.detektexp.MainKt"

log()  { echo -e "\033[1;32m[$(date '+%H:%M:%S')] $*\033[0m"; }
fail() { echo -e "\033[1;31mERROR: $*\033[0m" >&2; exit 1; }

[[ -f "$BENCH_JAR" ]]       || fail "$BENCH_JAR not found — run install-all.sh first"
[[ -f "$EXT_DEPS_CP_FILE" ]] || fail "ext-deps-cp.txt not found — run install-all.sh first"

EXT_DEPS_CP="$(cat "$EXT_DEPS_CP_FILE")"
DETEKT_CP="\
$DETEKT/detekt-utils/target/classes:\
$DETEKT/detekt-tooling/target/classes:\
$DETEKT/detekt-psi-utils/target/classes:\
$DETEKT/detekt-api/target/classes:\
$DETEKT/detekt-parser/target/classes:\
$DETEKT/detekt-metrics/target/classes:\
$DETEKT/detekt-rules-complexity/target/classes:\
$DETEKT/detekt-rules-style/target/classes:\
$DETEKT/detekt-rules-naming/target/classes:\
$DETEKT/detekt-rules-errorprone/target/classes:\
$DETEKT/detekt-rules-coroutines/target/classes"
CP="$BENCH_JAR:$DETEKT_CP:$EXT_DEPS_CP"

JAVA_ARGS=(
  --add-opens java.base/java.lang=ALL-UNNAMED
  --add-opens java.base/java.util=ALL-UNNAMED
  --add-opens java.base/java.io=ALL-UNNAMED
)

mkdir -p "$WORK_DIR"
log "Preparing workdir"
"$JAVA_BIN" "${JAVA_ARGS[@]}" -cp "$CP" "$MAIN" prepare "$WORK_DIR" >/dev/null

log "Recording single.aot for workload: $TRAIN_OP"
"$JAVA_BIN" \
  -XX:AOTCacheOutput="$AOT_OUT" \
  -XX:+AOTClassLinking \
  "${JAVA_ARGS[@]}" \
  -cp "$CP" "$MAIN" "$TRAIN_OP" "$WORK_DIR" >/dev/null

log "Created: $AOT_OUT"
