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

# ── component test-suite caches (produced by mvn test -Ptree-merge) ───────────

TIKA_CORE_CACHE="tika/tika-core/cache.aot"
TIKA_PDF_CACHE="tika/tika-parsers/tika-parsers-standard/tika-parsers-standard-modules/tika-parser-pdf-module/cache.aot"
TIKA_MSFT_CACHE="tika/tika-parsers/tika-parsers-standard/tika-parsers-standard-modules/tika-parser-microsoft-module/cache.aot"

for path in "$TIKA_CORE_CACHE" "$TIKA_PDF_CACHE" "$TIKA_MSFT_CACHE"; do
  [[ -f "$path" ]] || fail "Missing cache: $path — run mvn test -Ptree-merge in that module"
done

CACHE_PATHS=("$TIKA_CORE_CACHE" "$TIKA_PDF_CACHE" "$TIKA_MSFT_CACHE")

# ── CLI workload caches (covers TikaCLI and format-specific startup classes) ──

OPS=(text-pdf text-docx text-html)

_tika_args() {
  case "$1" in
    text-pdf)  echo "--text ${DOCS_DIR}/testPDF_childAttachments.pdf" ;;
    text-docx) echo "--text ${DOCS_DIR}/test_recursive_embedded.docx" ;;
    text-html) echo "--text ${DOCS_DIR}/testJsonMultipleInts.html" ;;
  esac
}

CLI_CACHES=()
for op in "${OPS[@]}"; do
  cli_aot="cli-${op}.aot"
  cli_conf="cli-${op}.aotconf"
  if [[ -f "$cli_aot" ]]; then
    log "$cli_aot already exists, reusing"
  else
    log "Recording CLI cache for $op (step 1: AOTConfiguration)"
    rm -f "$cli_conf"
    read -ra args <<< "$(_tika_args "$op")"
    java -XX:AOTMode=record -XX:AOTConfiguration="$cli_conf" \
      -XX:+AOTClassLinking \
      -jar "$JAR" "${args[@]}" >/dev/null 2>/dev/null || true
    [[ -f "$cli_conf" ]] || fail "AOTConfiguration not produced for $op"

    log "Recording CLI cache for $op (step 2: AOTCache)"
    java -XX:AOTMode=create -XX:AOTConfiguration="$cli_conf" \
      -XX:AOTCache="$cli_aot" \
      -XX:+AOTClassLinking \
      -jar "$JAR"
    [[ -f "$cli_aot" ]] || fail "$cli_aot not created"
    log "$cli_aot created ($(du -sh "$cli_aot" | cut -f1))"
  fi
  CLI_CACHES+=("$cli_aot")
done

# ── merge all caches → tree.aot ───────────────────────────────────────────────

ALL_CACHES=("${CACHE_PATHS[@]}" "${CLI_CACHES[@]}")
BASE_AOT="${ALL_CACHES[0]}"
MERGE_INPUTS="$(IFS=:; echo "${ALL_CACHES[*]}")"
OUTPUT_AOT="tree.aot"

rm -f "$OUTPUT_AOT"

log "Merging ${#ALL_CACHES[@]} caches → $OUTPUT_AOT"
java \
  -Xlog:aot=info \
  -Xlog:aot+map=trace,aot+map+oops=trace,aot=warning:file=aot.map:none:filesize=0 \
  -XX:AOTMode=merge \
  -XX:AOTCache="$BASE_AOT" \
  -XX:AOTMergeInputs="$MERGE_INPUTS" \
  -XX:AOTCacheOutput="$OUTPUT_AOT" \
  -jar "$JAR" \
  --help >/dev/null 2>&1 || true

[[ -f "$OUTPUT_AOT" ]] || fail "tree.aot was not created"
log "$OUTPUT_AOT created ($(du -sh "$OUTPUT_AOT" | cut -f1))"
