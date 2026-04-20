#!/bin/bash
set -euo pipefail

log()  { echo -e "\033[1;32m[$(date '+%H:%M:%S')] $*\033[0m"; }
sep()  { echo -e "\033[0;90m  $(printf '─%.0s' {1..60})\033[0m"; }
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
WORK_DIR="workload-tmp"
AOT="tree.aot"
RUNS="${RUNS:-10}"
OP_TIMEOUT_SEC="${OP_TIMEOUT_SEC:-900}"
JAVA_NO_BIN="${JAVA_NO_BIN:-java}"
JAVA_TREE_BIN="${JAVA_TREE_BIN:-java}"
OPS=("zip-roundtrip" "tar-roundtrip" "gzip-roundtrip" "list-archives")

[[ -f "$JAR" ]] || fail "$JAR not found — run: cd benchmark && mvn package -DskipTests"
[[ -f "$AOT" ]] || fail "tree.aot not found — run orchestrate-combine.sh first"

mkdir -p "$WORK_DIR"

log "Java version(s):"
echo "no-AOT java:   $JAVA_NO_BIN"
"$JAVA_NO_BIN" -version
echo
echo "tree-AOT java: $JAVA_TREE_BIN"
"$JAVA_TREE_BIN" -version
echo

"$JAVA_NO_BIN" -cp "$CP" "$MAIN" prepare "$WORK_DIR" >/dev/null

ms() { date +%s%N | awk '{printf "%.1f", $1/1000000}'; }

declare -A minv maxv cnt samples

update_stats() {
  local key="$1"
  local sample_ms="$2"
  cnt[$key]=$(( ${cnt[$key]:-0} + 1 ))
  samples[$key]="${samples[$key]:-} ${sample_ms}"
  if [ -z "${minv[$key]:-}" ] || awk "BEGIN {exit !(${sample_ms} < ${minv[$key]})}"; then
    minv[$key]="$sample_ms"
  fi
  if [ -z "${maxv[$key]:-}" ] || awk "BEGIN {exit !(${sample_ms} > ${maxv[$key]})}"; then
    maxv[$key]="$sample_ms"
  fi
}

median_for_key() {
  local key="$1"
  local values="${samples[$key]# }"
  printf "%s\n" $values | sort -n | awk '
    { a[++n] = $1 }
    END {
      if (n == 0) {
        print "n/a"
      } else if (n % 2 == 1) {
        printf "%.1f", a[(n + 1) / 2]
      } else {
        printf "%.1f", (a[n / 2] + a[(n / 2) + 1]) / 2
      }
    }
  '
}

run_mode_op() {
  local mode="$1"
  local op="$2"
  case "$mode" in
    no)
      "$JAVA_NO_BIN" -cp "$CP" "$MAIN" "$op" "$WORK_DIR"
      ;;
    tree)
      "$JAVA_TREE_BIN" -XX:AOTCache="$AOT" \
        --add-modules java.instrument \
        --add-opens java.base/java.io=ALL-UNNAMED \
        -cp "$CP" "$MAIN" "$op" "$WORK_DIR"
      ;;
    *)
      fail "Unknown mode: $mode"
      ;;
  esac
}

measure_ms() {
  local op="$1"
  local mode="$2"
  shift 2
  local err_file="$WORK_DIR/${RUN_IDX:-0}-${op}-${mode}.stderr.log"
  local start end rc
  start=$(ms)
  "$@" >/dev/null 2>"$err_file"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "ERROR: failed (op=$op mode=$mode rc=$rc) see $err_file" >&2
    return "$rc"
  fi
  end=$(ms)
  awk "BEGIN {printf \"%.1f\", $end - $start}"
}

print_summary() {
  echo
  log "Aggregated timing over ${RUNS} runs (ms)"
  sep
  printf "  %-16s | %10s %6s %6s | %10s %6s %6s\n" \
    "Operation" "no-med" "no-min" "no-max" "tree-med" "tree-min" "tree-max"
  local op
  for op in "${OPS[@]}"; do
    printf "  %-16s | %10s %6s %6s | %10s %6s %6s\n" \
      "$op" \
      "$(median_for_key "${op}|no")" "${minv[${op}|no]:-n/a}" "${maxv[${op}|no]:-n/a}" \
      "$(median_for_key "${op}|tree")" "${minv[${op}|tree]:-n/a}" "${maxv[${op}|tree]:-n/a}"
  done
}

print_class_load_row() {
  local mode="$1"
  local op="$2"
  local classload_log="$WORK_DIR/classload-${op}-${mode}.log"

  case "$mode" in
    no)
      "$JAVA_NO_BIN" -Xlog:class+load -cp "$CP" "$MAIN" "$op" "$WORK_DIR" >"$classload_log" 2>&1
      ;;
    tree)
      "$JAVA_TREE_BIN" -Xlog:class+load -XX:AOTCache="$AOT" \
        --add-modules java.instrument \
        --add-opens java.base/java.io=ALL-UNNAMED \
        -cp "$CP" "$MAIN" "$op" "$WORK_DIR" >"$classload_log" 2>&1
      ;;
  esac

  printf "  %-16s | %-4s | %8s | %8s\n" \
    "$op" "$mode" \
    "$(awk '/source: file:/{count++} END{print count+0}' "$classload_log")" \
    "$(awk '/source: shared object[s]? file/{count++} END{print count+0}' "$classload_log")"
}

log "Running Commons Compress workload RUNS=$RUNS"
for RUN_IDX in $(seq 1 "$RUNS"); do
  for op in "${OPS[@]}"; do
    no_ms=$(measure_ms "$op" "no" run_mode_op "no" "$op")
    update_stats "${op}|no" "$no_ms"
    tree_ms=$(measure_ms "$op" "tree" run_mode_op "tree" "$op")
    update_stats "${op}|tree" "$tree_ms"
  done
done

print_summary

echo
log "Class-load source summary per workload"
sep
printf "  %-16s | %-4s | %8s | %8s\n" "Operation" "Mode" "file:" "shared"
for op in "${OPS[@]}"; do
  print_class_load_row "no" "$op"
  print_class_load_row "tree" "$op"
  echo "--------------------------------"
done
