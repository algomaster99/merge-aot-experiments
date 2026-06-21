#!/bin/bash
set -euo pipefail

log()  { echo -e "\033[1;32m[$(date '+%H:%M:%S')] $*\033[0m"; }
fail() { echo -e "\033[1;31mERROR: $*\033[0m" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

log "Java version:"
java -version

JAR="tika/tika-app/target/tika-app-3.3.1.jar"
[[ -f "$JAR" ]] || fail "$JAR not found — run: cd tika && mvn install -DskipTests -q"

DOCS_DIR="tika/tika-app/src/test/resources/test-data"

OPS=(text-pdf text-docx text-archive)

_tika_args() {
  case "$1" in
    text-pdf)     echo "--text ${DOCS_DIR}/testPDF_childAttachments.pdf" ;;
    text-docx)    echo "--text ${DOCS_DIR}/test_recursive_embedded.docx" ;;
    text-archive) echo "--text ${DOCS_DIR}/test-documents.tgz" ;;
  esac
}

for op in "${OPS[@]}"; do
  single_aot="single-${op}.aot"
  single_conf="single-${op}.aotconf"

  if [[ -f "$single_aot" ]]; then
    log "$single_aot already exists, skipping"
    continue
  fi

  log "Recording single.aot for $op (step 1: AOTConfiguration)"
  rm -f "$single_conf"
  read -ra args <<< "$(_tika_args "$op")"
  java -XX:AOTMode=record -XX:AOTConfiguration="$single_conf" \
    -XX:+AOTClassLinking \
    -jar "$JAR" "${args[@]}" >/dev/null 2>/dev/null || true
  [[ -f "$single_conf" ]] || fail "AOTConfiguration not produced for $op"

  log "Recording single.aot for $op (step 2: AOTCache)"
  java -XX:AOTMode=create -XX:AOTConfiguration="$single_conf" \
    -XX:AOTCache="$single_aot" \
    -XX:+AOTClassLinking \
    -jar "$JAR"
  [[ -f "$single_aot" ]] || fail "$single_aot not created"
  log "$single_aot created ($(du -sh "$single_aot" | cut -f1))"
done
