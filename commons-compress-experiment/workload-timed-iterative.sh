#!/bin/bash
# Timing comparison for the iterative-AOT JDK build (PR 31344). Three modes:
#   no        — no AOT cache
#   aotcache  — single-iterjdk-{op}.aot cross-workload (cache trained on the
#               other three ops, run on this one) — same shape as the
#               original cross-workload test, rebuilt for this JDK build
#   iterative — iterative.aot, built incrementally by create-iterative-aot.sh
#               (gzip -> zip -> tar -> list-archives, each step folded into the next)
#
# Point JAVA_BIN at the JDK build under test, e.g.:
#   JAVA_BIN=~/Desktop/tools/jdk/build/linux-x86_64-server-release-aot-re-training/images/jdk/bin/java \
#     ./workload-timed-iterative.sh
set -euo pipefail

log()  { echo -e "\033[1;32m[$(date '+%H:%M:%S')] $*\033[0m"; }
sep()  { echo -e "\033[0;90m  $(printf '─%.0s' {1..60})\033[0m"; }
fail() { echo -e "\033[1;31mERROR: $*\033[0m" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

JAVA_BIN="${JAVA_BIN:-java}"
JAR="benchmark/target/original-benchmark-1.0-SNAPSHOT.jar"
DEPS_DIR="single-aot-deps"
# single-iterjdk-{op}.aot and iterative.aot are both recorded against JARs
# (CDS dump rejects non-empty directory classpath entries) — use the
# matching JAR-based classpath for all run modes here.
CP="$JAR:\
$DEPS_DIR/commons-compress-1.28.0.jar:\
$DEPS_DIR/commons-lang3-3.20.0.jar:\
$DEPS_DIR/commons-codec-1.21.0.jar:\
$DEPS_DIR/commons-io-2.20.0.jar"
MAIN="dev.compressexp.Main"
WORK_DIR="workload-tmp"
ITERATIVE_AOT="iterative.aot"
RUNS="${RUNS:-30}"
OPS=("gzip-roundtrip" "zip-roundtrip" "tar-roundtrip" "list-archives")

[[ -f "$JAR" ]] || fail "$JAR not found — run: cd benchmark && mvn package -DskipTests"
[[ -f "$ITERATIVE_AOT" ]] || fail "$ITERATIVE_AOT not found — run create-iterative-aot.sh first"
for _op in "${OPS[@]}"; do
  [[ -f "single-iterjdk-${_op}.aot" ]] || fail "single-iterjdk-${_op}.aot not found — run create-single-aot-iterjdk.sh first"
done

mkdir -p "$WORK_DIR"

log "Java binary under test: $JAVA_BIN"
"$JAVA_BIN" -version

"$JAVA_BIN" -cp "$CP" "$MAIN" prepare "$WORK_DIR" >/dev/null

ms() { date +%s%N | awk '{printf "%.1f", $1/1000000}'; }

declare -A samples

update_stats() {
  local key="$1" sample_ms="$2"
  samples[$key]="${samples[$key]:-} ${sample_ms}"
}

mean_for_key() {
  local values="${samples[$1]# }"
  printf "%s\n" $values | awk '
    { sum += $1; n++ }
    END { if (n == 0) { print "n/a" } else { printf "%.1f", sum/n } }'
}

stddev_for_key() {
  local values="${samples[$1]# }"
  printf "%s\n" $values | awk '
    { sum += $1; sumsq += $1*$1; n++ }
    END { if (n < 2) { print "n/a" } else { printf "%.1f", sqrt((sumsq - sum*sum/n) / (n-1)) } }'
}

run_no() {
  local op="$1"
  "$JAVA_BIN" -cp "$CP" "$MAIN" "$op" "$WORK_DIR"
}

# train_op determines which single-iterjdk-{op}.aot to load; test_op is the workload run.
run_aotcache_cross() {
  local train_op="$1" test_op="$2"
  "$JAVA_BIN" -XX:AOTCache="single-iterjdk-${train_op}.aot" -XX:+AOTClassLinking \
    -cp "$CP" "$MAIN" "$test_op" "$WORK_DIR"
}

run_iterative() {
  local op="$1"
  "$JAVA_BIN" -XX:AOTCache="$ITERATIVE_AOT" -XX:+AOTClassLinking \
    -cp "$CP" "$MAIN" "$op" "$WORK_DIR"
}

measure_ms() {
  local label_op="$1" label_mode="$2"
  shift 2
  local file_label_op="${label_op//>/-to-}"
  local err_file="$WORK_DIR/${RUN_IDX:-0}-${file_label_op}-${label_mode}.stderr.log"
  local start end rc
  start=$(ms)
  "$@" >/dev/null 2>"$err_file"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "ERROR: failed (op=$label_op mode=$label_mode rc=$rc) see $err_file" >&2
    return "$rc"
  fi
  end=$(ms)
  awk "BEGIN {printf \"%.1f\", $end - $start}"
}

# Mean time of test_op when run with caches trained on each other op.
test_mean_aotcache() {
  local test_op="$1" sum=0 n=0 train_op key m
  for train_op in "${OPS[@]}"; do
    [[ "$train_op" == "$test_op" ]] && continue
    key="${train_op}|${test_op}|aotcache"
    m=$(mean_for_key "$key")
    sum=$(awk "BEGIN{printf \"%.4f\", $sum + $m}")
    n=$(( n + 1 ))
  done
  awk -v s="$sum" -v n="$n" 'BEGIN{printf "%.1f", s/n}'
}

# Pooled SD of test_op across all caches trained on other ops.
test_stddev_aotcache() {
  local test_op="$1" all_samples="" train_op key
  for train_op in "${OPS[@]}"; do
    [[ "$train_op" == "$test_op" ]] && continue
    key="${train_op}|${test_op}|aotcache"
    all_samples="$all_samples ${samples[$key]:-}"
  done
  printf "%s\n" $all_samples | awk '
    { sum += $1; sumsq += $1*$1; n++ }
    END { if (n < 2) { print "n/a" } else { printf "%.1f", sqrt((sumsq - sum*sum/n) / (n-1)) } }'
}

log "Running Commons Compress iterative-AOT workload RUNS=$RUNS"
for RUN_IDX in $(seq 1 "$RUNS"); do
  printf "  run %2d/%d\n" "$RUN_IDX" "$RUNS"
  # no and iterative: one pass over all ops
  for op in "${OPS[@]}"; do
    update_stats "${op}|no"        "$(measure_ms "$op" "no"        run_no        "$op")"
    update_stats "${op}|iterative" "$(measure_ms "$op" "iterative" run_iterative "$op")"
  done
  # aotcache cross-workload: for each training op, run its cache on all other ops
  for train_op in "${OPS[@]}"; do
    for test_op in "${OPS[@]}"; do
      [[ "$test_op" == "$train_op" ]] && continue
      update_stats "${train_op}|${test_op}|aotcache" \
        "$(measure_ms "${train_op}>${test_op}" "aotcache" run_aotcache_cross "$train_op" "$test_op")"
    done
  done
done

echo
log "Per-workload timing over ${RUNS} runs (ms)"
sep
printf "  %-16s | %18s | %20s %8s | %20s %8s\n" \
  "Workload" "no (mean±SD)" "aotcache (mean±SD)" "su-aotcache" "iterative (mean±SD)" "su-iterative"
sep
for op in "${OPS[@]}"; do
  m_no=$(mean_for_key "${op}|no")
  m_ac=$(test_mean_aotcache "$op")
  m_it=$(mean_for_key "${op}|iterative")
  sd_no=$(stddev_for_key "${op}|no")
  sd_ac=$(test_stddev_aotcache "$op")
  sd_it=$(stddev_for_key "${op}|iterative")
  su_ac=$(awk -v b="$m_no" -v a="$m_ac" 'BEGIN{if(a+0==0){print "n/a"}else{printf "%.2fx",b/a}}')
  su_it=$(awk -v b="$m_no" -v a="$m_it" 'BEGIN{if(a+0==0){print "n/a"}else{printf "%.2fx",b/a}}')
  printf "  %-16s | %18s | %20s %8s | %20s %8s\n" \
    "$op" "${m_no}±${sd_no}" "${m_ac}±${sd_ac}" "$su_ac" "${m_it}±${sd_it}" "$su_it"
done

# ─── class-load summary (same-workload aotcache for each op) ───────────────

print_class_load_row() {
  local mode="$1" op="$2"
  local classload_log="$WORK_DIR/classload-${op}-${mode}.log"
  case "$mode" in
    no)
      "$JAVA_BIN" -Xlog:class+load:file="$classload_log" \
        -cp "$CP" "$MAIN" "$op" "$WORK_DIR"
      ;;
    aotcache)
      "$JAVA_BIN" -XX:AOTCache="single-iterjdk-${op}.aot" \
        -XX:+AOTClassLinking \
        -Xlog:class+load:file="$classload_log" \
        -cp "$CP" "$MAIN" "$op" "$WORK_DIR"
      ;;
    iterative)
      "$JAVA_BIN" -XX:AOTCache="$ITERATIVE_AOT" \
        -XX:+AOTClassLinking \
        -Xlog:class+load:file="$classload_log" \
        -cp "$CP" "$MAIN" "$op" "$WORK_DIR"
      ;;
  esac
  printf "  %-16s | %-9s | %8s | %8s\n" \
    "$op" "$mode" \
    "$(awk '/source: file:/{count++} END{print count+0}' "$classload_log")" \
    "$(awk '/source: shared object[s]? file/{count++} END{print count+0}' "$classload_log")"
}

echo
log "Class-load source summary per workload (aotcache uses same-workload cache)"
sep
printf "  %-16s | %-9s | %8s | %8s\n" "Operation" "Mode" "file:" "shared"
for op in "${OPS[@]}"; do
  print_class_load_row "no" "$op"
  print_class_load_row "aotcache" "$op"
  print_class_load_row "iterative" "$op"
  echo "--------------------------------"
done

# ─── cache size table ───────────────────────────────────────────────────────

echo
log "Cache sizes"
sep
printf "  %-40s | %10s\n" "Cache" "Size"
sep
for op in "${OPS[@]}"; do
  printf "  %-40s | %10s\n" "single-iterjdk-${op}.aot" "$(du -h "single-iterjdk-${op}.aot" | awk '{print $1}')"
done
for f in iterative-step*.aot; do
  [[ -f "$f" ]] || continue
  printf "  %-40s | %10s\n" "$f" "$(du -h "$f" | awk '{print $1}')"
done
printf "  %-40s | %10s\n" "iterative.aot" "$(du -h "$ITERATIVE_AOT" | awk '{print $1}')"
