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
JAR="pdfbox/app/target/pdfbox-app-3.0.7.jar"
MAIN="org.apache.pdfbox.tools.PDFBox"
PDF="pdfbox/test.pdf"
BASE="iterjdk"
TMP="workload-tmp"

log "Java binary: $JAVA_BIN"
"$JAVA_BIN" -version

[[ -f "$JAR" ]] || fail "$JAR not found — build pdfbox app first"
[[ -f "$PDF" ]] || fail "$PDF not found"

# Training order for the iterative cache.
OPS=(export:text export:images render fromtext split merge decode overlay)

mkdir -p "$TMP"

op_args() {
  local op="$1"
  local -n _arr="$2"
  case "$op" in
    export:text)   _arr=(export:text   --input "$PDF" --output "$TMP/$BASE-text.txt") ;;
    export:images) _arr=(export:images --input "$PDF") ;;
    render)        _arr=(render        --input "$PDF") ;;
    fromtext)      _arr=(fromtext      --input "$TMP/$BASE-text.txt"
                           --output "$TMP/$BASE-from-text.pdf"
                           -standardFont Times-Roman) ;;
    split)         _arr=(split         --input "$PDF" -split 3 -outputPrefix "$TMP/split-$BASE") ;;
    merge)         _arr=(merge         --input "$TMP/split-$BASE-1.pdf"
                           --output "$TMP/merged-$BASE.pdf") ;;
    decode)        _arr=(decode "$PDF" "$TMP/$BASE-decoded.pdf") ;;
    overlay)       _arr=(overlay       -default "$PDF" --input "$PDF"
                           --output "$TMP/$BASE-overlay.pdf") ;;
    *) fail "Unknown op: $op" ;;
  esac
}

log "Preparing prerequisite files…"
"$JAVA_BIN" -cp "$JAR" "$MAIN" export:text --input "$PDF" --output "$TMP/$BASE-text.txt" >/dev/null 2>&1
"$JAVA_BIN" -cp "$JAR" "$MAIN" split --input "$PDF" -split 3 -outputPrefix "$TMP/split-$BASE" >/dev/null 2>&1

prev_aot=""
for i in "${!OPS[@]}"; do
  op="${OPS[$i]}"
  safe="${op//:/-}"
  step=$(( i + 1 ))
  out_aot="iterative-step${step}-${safe}.aot"

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

  args=()
  op_args "$op" args
  "$JAVA_BIN" \
    "${base_args[@]}" \
    -XX:AOTCacheOutput="$out_aot" \
    -XX:+AOTClassLinking \
    -cp "$JAR" "$MAIN" "${args[@]}"

  test -f "$out_aot"
  log "$out_aot created ($(du -sh "$out_aot" | cut -f1))"
  prev_aot="$out_aot"
done

cp -f "$prev_aot" iterative.aot
log "Final iterative cache: iterative.aot (copy of $prev_aot)"
