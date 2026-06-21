#!/bin/bash
set -euo pipefail

log()  { echo -e "\033[1;32m[$(date '+%H:%M:%S')] $*\033[0m"; }
fail() { echo -e "\033[1;31mERROR: $*\033[0m" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

log "Java version:"
java -version

JAR="certificate-ripper/target/crip.jar"
[[ -f "$JAR" ]] || fail "$JAR not found"
[[ -f "certificate-ripper/cache.aot" ]] || fail "certificate-ripper/cache.aot not found — run: mvn test -Ptree-merge"

OPS=(print-https export-pem-https print-smtps)
EXPORT_DIR="$SCRIPT_DIR/workload-tmp/exports"
mkdir -p "$EXPORT_DIR/pem"

_crip_args() {
  case "$1" in
    print-https)      echo "print --url https://github.com --resolve-ca false" ;;
    export-pem-https) echo "export pem --url https://github.com --resolve-ca false -d $EXPORT_DIR/pem" ;;
    print-smtps)      echo "print --url smtps://smtp.gmail.com:465 --resolve-ca false" ;;
  esac
}

# ── record CLI workload caches (covers CLI-specific classes not in test suite) ─

CLI_CACHES=()
for op in "${OPS[@]}"; do
  cli_aot="cli-${op}.aot"
  cli_conf="cli-${op}.aotconf"
  if [[ -f "$cli_aot" ]]; then
    log "$cli_aot already exists, reusing"
  else
    log "Recording CLI cache for $op (step 1: AOTConfiguration)"
    rm -f "$cli_conf"
    read -ra args <<< "$(_crip_args "$op")"
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

ALL_CACHES=("certificate-ripper/cache.aot" "${CLI_CACHES[@]}")
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
