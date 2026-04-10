#!/bin/bash
set -euo pipefail

# Usage:
#   JAVA_NO_BIN=<java>  JAVA_TREE_BIN=<java>  ./workload-timed.sh
#
# Defaults to 'java' from PATH for both if not set.

JAVA_NO_BIN="/home/aman/.sdkman/candidates/java/25-open/bin/java"
JAVA_TREE_BIN="${JAVA_TREE_BIN:-java}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MCS_JAR="$SCRIPT_DIR/mcs/target/mcs-0.9.7.jar"
TREE_AOT="$SCRIPT_DIR/tree.aot"
RUNS=10

log() { echo -e "\033[1;32m[$(date '+%H:%M:%S')] $*\033[0m"; }
err() { echo -e "\033[1;31m[ERROR] $*\033[0m" >&2; }

if [[ ! -f "$MCS_JAR" ]]; then
  err "Missing $MCS_JAR — run: mvn package -Ptree-merge inside mcs-experiment/mcs"
  exit 1
fi

if [[ ! -f "$TREE_AOT" ]]; then
  err "Missing $TREE_AOT — run orchestrate-combine.sh first"
  exit 1
fi

# Returns wall-clock milliseconds for a command
timed_ms() {
  local start end
  start=$(date +%s%N)
  "$@" > /dev/null 2>&1
  end=$(date +%s%N)
  echo $(( (end - start) / 1000000 ))
}

# Collect N timings and print the median
median_ms() {
  local label="$1"; shift
  local -a times=()
  for (( i=0; i<RUNS; i++ )); do
    times+=( "$(timed_ms "$@")" )
  done
  local sorted
  sorted=$(printf '%s\n' "${times[@]}" | sort -n)
  local mid=$(( RUNS / 2 ))
  local median
  median=$(echo "$sorted" | sed -n "$((mid+1))p")
  printf "  %-30s  median=%4d ms  (runs=%d)\n" "$label" "$median" "$RUNS"
}

log "no-AOT java:   $("$JAVA_NO_BIN" -version 2>&1 | head -1)"
log "tree-AOT java: $("$JAVA_TREE_BIN" -version 2>&1 | head -1)"
log "tree.aot size: $(du -h "$TREE_AOT" | awk '{print $1}')"
echo ""

WORKLOADS=(
  "search picocli"
  "search com.fasterxml.jackson.jr:jackson-jr-objects"
  "search --output-format maven info.picocli:picocli:4.7.7"
)

for wl in "${WORKLOADS[@]}"; do
  log "Workload: mcs $wl"
  # shellcheck disable=SC2086
  median_ms "no-AOT  " "$JAVA_NO_BIN" -jar "$MCS_JAR" $wl
  # shellcheck disable=SC2086
  median_ms "tree.aot" "$JAVA_TREE_BIN" -XX:AOTCache="$TREE_AOT" -jar "$MCS_JAR" $wl
  echo ""
done
