#!/bin/bash
# Records one single-{op}.aot per workload using the crip fat jar.
set -euo pipefail

log()  { echo -e "\033[1;32m[$(date '+%H:%M:%S')] $*\033[0m"; }
fail() { echo -e "\033[1;31mERROR: $*\033[0m" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

log "Java version:"
java -version

JAR="certificate-ripper/target/crip.jar"
[[ -f "$JAR" ]] || fail "$JAR not found — run: mvn package -DskipTests in certificate-ripper/"

OPS=(print-https export-pem-https print-smtps)
EXPORT_DIR="$SCRIPT_DIR/workload-tmp/exports"
mkdir -p "$EXPORT_DIR/pem"

_crip_args() {
  case "$1" in
    print-https)     echo "print --url https://github.com --resolve-ca false" ;;
    export-pem-https) echo "export pem --url https://github.com --resolve-ca false -d $EXPORT_DIR/pem" ;;
    print-smtps)     echo "print --url smtps://smtp.gmail.com:465 --resolve-ca false" ;;
  esac
}

for op in "${OPS[@]}"; do
  aot="single-${op}.aot"
  conf="single-${op}.aotconf"
  if [[ -f "$aot" ]]; then
    log "$aot already exists, skipping."
    continue
  fi

  log "Recording $aot (step 1: AOTConfiguration)"
  rm -f "$conf"
  read -ra args <<< "$(_crip_args "$op")"
  java -XX:AOTMode=record -XX:AOTConfiguration="$conf" \
    -XX:+AOTClassLinking \
    -jar "$JAR" "${args[@]}" >/dev/null 2>/dev/null || true

  [[ -f "$conf" ]] || fail "AOTConfiguration not produced for $op"

  log "Recording $aot (step 2: AOTCache)"
  java -XX:AOTMode=create -XX:AOTConfiguration="$conf" \
    -XX:AOTCache="$aot" \
    -XX:+AOTClassLinking \
    -jar "$JAR"

  [[ -f "$aot" ]] || fail "$aot was not created"
  log "$aot created ($(du -sh "$aot" | cut -f1))"
done
