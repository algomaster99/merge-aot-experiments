#!/bin/bash
# Creates one single-{op}.aot per workload for the cross-workload experiment.
set -euo pipefail

log()  { echo -e "\033[1;32m[$(date '+%H:%M:%S')] $*\033[0m"; }
fail() { echo -e "\033[1;31mERROR: $*\033[0m" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

log "Java version:"
java -version

JAR="pdfbox/app/target/pdfbox-app-3.0.7.jar"
MAIN="org.apache.pdfbox.tools.PDFBox"
CP="$JAR:pdfbox-deps/pdfbox-jbig2/target/classes/:pdfbox-deps/apache-commons-io/target/classes/"
PDF="pdfbox/test.pdf"
TMP="workload-tmp"
OPS=(render export:text fromtext split)

[[ -f "$JAR" ]] || fail "$JAR not found — build pdfbox app first"
[[ -f "$PDF" ]] || fail "$PDF not found"

mkdir -p "$TMP"

# Prepare prerequisite files needed by some ops during recording.
log "Preparing prerequisite files…"
java -cp "$CP" "$MAIN" export:text --input "$PDF" --output "$TMP/create-aot-text.txt" >/dev/null 2>&1

for op in "${OPS[@]}"; do
  safe="${op//:/-}"
  aot="single-${safe}.aot"
  conf="single-${safe}.aotconf"
  if [[ -f "$aot" ]]; then
    log "$aot already exists, skipping."
    continue
  fi
  log "Creating $aot (training op: $op)"
  rm -f "$conf"

  case "$op" in
    render)
      java -XX:AOTMode=record -XX:AOTConfiguration="$conf" -XX:+AOTClassLinking \
        -cp "$CP" "$MAIN" render --input "$PDF"
      ;;
    export:text)
      java -XX:AOTMode=record -XX:AOTConfiguration="$conf" -XX:+AOTClassLinking \
        -cp "$CP" "$MAIN" export:text --input "$PDF" --output "$TMP/create-aot-text.txt"
      ;;
    fromtext)
      java -XX:AOTMode=record -XX:AOTConfiguration="$conf" -XX:+AOTClassLinking \
        -cp "$CP" "$MAIN" fromtext --input "$TMP/create-aot-text.txt" \
          --output "$TMP/create-aot-from-text.pdf" -standardFont Times-Roman
      ;;
    split)
      java -XX:AOTMode=record -XX:AOTConfiguration="$conf" -XX:+AOTClassLinking \
        -cp "$CP" "$MAIN" split --input "$PDF" -split 3 -outputPrefix "$TMP/create-aot-split"
      ;;
  esac

  [[ -f "$conf" ]] || fail "AOT configuration file was not produced for op=$op"

  java -XX:AOTMode=create \
    -XX:AOTConfiguration="$conf" \
    -XX:AOTCache="$aot" \
    -XX:+AOTClassLinking \
    -cp "$CP"

  [[ -f "$aot" ]] || fail "$aot was not created"
  log "$aot created ($(du -sh "$aot" | cut -f1))"
done
