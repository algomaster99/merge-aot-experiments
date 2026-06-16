#!/bin/bash
# Same as create-single-aot.sh, but built with a configurable JAVA_BIN and
# written to single-iterjdk-{op}.aot so caches built with the iterative-AOT
# JDK build (PR 31344) don't collide with the single-{op}.aot files already
# built with the stock JDK for the original experiment.
#
# Uses only the self-contained pdfbox-app jar (it already bundles jbig2 and
# commons-io) instead of the pdfbox-deps/*/target/classes directories used
# by create-single-aot.sh — CDS dump (record/create) rejects non-empty
# directory classpath entries on this JDK build.
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
OPS=(export:text export:images render fromtext split merge decode overlay)

log "Java binary: $JAVA_BIN"
"$JAVA_BIN" -version

[[ -f "$JAR" ]] || fail "$JAR not found — build pdfbox app first"
[[ -f "$PDF" ]] || fail "$PDF not found"

mkdir -p "$TMP"

# Builds the pdfbox CLI args for a given op into the named array variable.
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

# Prepare prerequisite files needed by some ops during recording.
log "Preparing prerequisite files…"
"$JAVA_BIN" -cp "$JAR" "$MAIN" export:text --input "$PDF" --output "$TMP/$BASE-text.txt" >/dev/null 2>&1
"$JAVA_BIN" -cp "$JAR" "$MAIN" split --input "$PDF" -split 3 -outputPrefix "$TMP/split-$BASE" >/dev/null 2>&1

for op in "${OPS[@]}"; do
  safe="${op//:/-}"
  aot="single-iterjdk-${safe}.aot"
  conf="single-iterjdk-${safe}.aotconf"
  if [[ -f "$aot" ]]; then
    log "$aot already exists, skipping."
    continue
  fi
  log "Creating $aot (training op: $op)"
  rm -f "$conf"

  args=()
  op_args "$op" args
  "$JAVA_BIN" -XX:AOTMode=record -XX:AOTConfiguration="$conf" -XX:+AOTClassLinking \
    -cp "$JAR" "$MAIN" "${args[@]}"

  [[ -f "$conf" ]] || fail "AOT configuration file was not produced for op=$op"

  "$JAVA_BIN" -XX:AOTMode=create \
    -XX:AOTConfiguration="$conf" \
    -XX:AOTCache="$aot" \
    -XX:+AOTClassLinking \
    -cp "$JAR"

  [[ -f "$aot" ]] || fail "$aot was not created"
  log "$aot created ($(du -sh "$aot" | cut -f1))"
done
