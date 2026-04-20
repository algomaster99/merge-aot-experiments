#!/bin/bash
set -euo pipefail

log()  { echo -e "\033[1;32m[$(date '+%H:%M:%S')] $*\033[0m"; }
fail() { echo -e "\033[1;31mERROR: $*\033[0m" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

JAR="benchmark/target/original-benchmark-1.0-SNAPSHOT.jar"
CP="$JAR:\
commons-compress/target/commons-compress-1.28.0.jar:\
commons-compress-deps/commons-lang/target/commons-lang3-3.20.0.jar:\
commons-compress-deps/commons-codec/target/commons-codec-1.21.0.jar:\
commons-compress-deps/apache-commons-io/target/commons-io-2.20.0.jar"
MAIN="dev.compressexp.Main"
AOT="tree.aot"
WORK_DIR="workload-tmp"
OUT_DIR="aot-analysis/commons-compress/classes"
COMBINED_LOG="$WORK_DIR/classload-all-tree.log"
OPS=("zip-roundtrip" "tar-roundtrip" "gzip-roundtrip" "list-archives")

[[ -f "$JAR" ]] || fail "$JAR not found — build benchmark first"
[[ -f "$AOT" ]] || fail "tree.aot not found — run orchestrate-combine.sh first"

mkdir -p "$WORK_DIR" "$OUT_DIR"
: > "$COMBINED_LOG"

java -cp "$CP" "$MAIN" prepare "$WORK_DIR" >/dev/null

log "Running workload with tree.aot + -Xlog:class+load=info"
for op in "${OPS[@]}"; do
  log "  $op"
  java -Xlog:class+load=info -XX:AOTCache="$AOT" \
    --add-modules java.instrument \
    --add-opens java.base/java.io=ALL-UNNAMED \
    -cp "$CP" "$MAIN" "$op" "$WORK_DIR" >>"$COMBINED_LOG" 2>&1 || true
done

AOT_RAW="$WORK_DIR/rt-aot-raw.txt"
FS_RAW="$WORK_DIR/rt-fs-raw.txt"
AOT_CLASSES="$OUT_DIR/runtime-tree.classes"
FS_CLASSES="$OUT_DIR/runtime-tree-fs.classes"

touch "$AOT_RAW" "$FS_RAW"

awk '
/\[class,load\]/ {
    match($0, /\[class,load\] ([^ ]+)/, arr)
    if (!arr[1]) next
    cls = arr[1]
    gsub(/\./, "/", cls)
    if (/source: shared objects file/) {
        print cls > "'"$AOT_RAW"'"
    } else {
        print cls > "'"$FS_RAW"'"
    }
}
' "$COMBINED_LOG"

sort -u "$AOT_RAW" > "$AOT_CLASSES"
sort -u "$FS_RAW" > "$FS_CLASSES"

log "Done"
echo "  AOT-served classes: $(wc -l < "$AOT_CLASSES") -> $AOT_CLASSES"
echo "  File-loaded classes: $(wc -l < "$FS_CLASSES") -> $FS_CLASSES"
