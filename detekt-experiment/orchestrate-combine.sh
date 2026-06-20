#!/bin/bash
# Build tree.aot by merging cache.aot files from all detekt module test suites.
# Run this AFTER the user has run: mvn test -P tree-merge  for each module.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DETEKT="$SCRIPT_DIR/detekt"
JAVA_BIN="${JAVA_BIN:-java}"
AOT_OUT="$SCRIPT_DIR/tree.aot"

log()  { echo -e "\033[1;32m[$(date '+%H:%M:%S')] $*\033[0m"; }
fail() { echo -e "\033[1;31mERROR: $*\033[0m" >&2; exit 1; }
warn() { echo -e "\033[1;33mWARN: $*\033[0m"; }

# Modules whose test suites contribute to tree.aot
MODULES=(
  detekt-rules-complexity
  detekt-rules-style
  detekt-rules-naming
  detekt-rules-errorprone
  detekt-rules-coroutines
  detekt-rules-exceptions
  detekt-rules-empty
  detekt-rules-performance
  detekt-rules-documentation
  detekt-core
  detekt-parser
)

CACHE_FILES=()
for mod in "${MODULES[@]}"; do
  cache="$DETEKT/$mod/cache.aot"
  if [[ -f "$cache" ]]; then
    CACHE_FILES+=("$cache")
    log "Found: $cache"
  else
    warn "Missing: $cache — run: mvn test -P tree-merge -f $DETEKT/$mod/pom.xml"
  fi
done

[[ ${#CACHE_FILES[@]} -gt 0 ]] || fail "No cache.aot files found. Run mvn test -P tree-merge for each module first."

MERGE_INPUTS="$(IFS=:; echo "${CACHE_FILES[*]}")"

log "Merging ${#CACHE_FILES[@]} cache(s) → $AOT_OUT"
"$JAVA_BIN" \
  -XX:AOTCacheOutput="$AOT_OUT" \
  -XX:AOTMode=create \
  -XX:AOTMergeInputs="$MERGE_INPUTS" \
  -Xlog:aot+map=trace,aot+map+oops=trace,aot=warning:file="$SCRIPT_DIR/aot.map":none:filesize=0 \
  -version

log "Created: $AOT_OUT  (aot.map written to $SCRIPT_DIR/aot.map)"
