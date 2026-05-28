#!/bin/bash
set -euo pipefail

log()  { echo -e "\033[1;32m[$(date '+%H:%M:%S')] $*\033[0m"; }
sep()  { echo -e "\033[0;90m  $(printf '─%.0s' {1..60})\033[0m"; }
fail() { echo -e "\033[1;31mERROR: $*\033[0m" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

JAR="benchmark/target/original-benchmark-1.0-SNAPSHOT.jar"
CP="$JAR:\
commons-compress/target/classes:\
commons-compress-deps/commons-lang/target/classes:\
commons-compress-deps/commons-codec/target/classes:\
commons-compress-deps/apache-commons-io/target/classes"
# single-{op}.aot caches are recorded against JARs; use the JAR-based classpath.
SINGLE_DEPS_DIR="single-aot-deps"
AOTCACHE_CP="$JAR:\
$SINGLE_DEPS_DIR/commons-compress-1.28.0.jar:\
$SINGLE_DEPS_DIR/commons-lang3-3.20.0.jar:\
$SINGLE_DEPS_DIR/commons-codec-1.21.0.jar:\
$SINGLE_DEPS_DIR/commons-io-2.20.0.jar"
MAIN="dev.compressexp.Main"
WORK_DIR="workload-tmp"
TREECACHE_AOT="tree.aot"
RUNS="${RUNS:-30}"
OP_TIMEOUT_SEC="${OP_TIMEOUT_SEC:-900}"
JAVA_NO_BIN="${JAVA_NO_BIN:-java}"
JAVA_AOTCACHE_BIN="${JAVA_AOTCACHE_BIN:-java}"
JAVA_TREECACHE_BIN="${JAVA_TREECACHE_BIN:-java}"
OPS=("gzip-roundtrip" "zip-roundtrip" "tar-roundtrip" "list-archives")

[[ -f "$JAR" ]] || fail "$JAR not found — run: cd benchmark && mvn package -DskipTests"
for _op in "${OPS[@]}"; do
  [[ -f "single-${_op}.aot" ]] || fail "single-${_op}.aot not found — run create-single-aot.sh first"
done
[[ -f "$TREECACHE_AOT" ]] || fail "tree.aot not found — run orchestrate-combine.sh first"

mkdir -p "$WORK_DIR"

log "Java version(s):"
echo "no-AOT java:         $JAVA_NO_BIN";         "$JAVA_NO_BIN"         -version
echo
echo "AOTCache-AOT java: $JAVA_AOTCACHE_BIN"; "$JAVA_AOTCACHE_BIN" -version
echo
echo "TreeCache-AOT java:     $JAVA_TREECACHE_BIN";     "$JAVA_TREECACHE_BIN"     -version
echo

"$JAVA_NO_BIN" -cp "$CP" "$MAIN" prepare "$WORK_DIR" >/dev/null

ms() { date +%s%N | awk '{printf "%.1f", $1/1000000}'; }

declare -A minv maxv cnt samples

update_stats() {
  local key="$1" sample_ms="$2"
  cnt[$key]=$(( ${cnt[$key]:-0} + 1 ))
  samples[$key]="${samples[$key]:-} ${sample_ms}"
  if [ -z "${minv[$key]:-}" ] || awk "BEGIN {exit !(${sample_ms} < ${minv[$key]})}"; then
    minv[$key]="$sample_ms"
  fi
  if [ -z "${maxv[$key]:-}" ] || awk "BEGIN {exit !(${sample_ms} > ${maxv[$key]})}"; then
    maxv[$key]="$sample_ms"
  fi
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

# ─── run helpers ─────────────────────────────────────────────────────────────

run_no() {
  local op="$1"
  "$JAVA_NO_BIN" \
    --add-modules java.instrument \
    --add-opens java.base/java.io=ALL-UNNAMED \
    --add-opens java.base/java.lang=ALL-UNNAMED \
    --add-opens java.base/java.lang.reflect=ALL-UNNAMED \
    --add-opens java.base/java.time=ALL-UNNAMED \
    --add-opens java.base/java.time.chrono=ALL-UNNAMED \
    --add-opens java.base/java.util=ALL-UNNAMED \
    -cp "$CP" "$MAIN" "$op" "$WORK_DIR"
}

# train_op determines which single-{op}.aot to load; test_op is the workload run.
run_mono_cross() {
  local train_op="$1" test_op="$2"
  "$JAVA_AOTCACHE_BIN" -XX:AOTCache="single-${train_op}.aot" \
    -XX:+AOTClassLinking \
    --add-modules java.instrument \
    --add-opens java.base/java.io=ALL-UNNAMED \
    --add-opens java.base/java.lang=ALL-UNNAMED \
    --add-opens java.base/java.lang.reflect=ALL-UNNAMED \
    --add-opens java.base/java.time=ALL-UNNAMED \
    --add-opens java.base/java.time.chrono=ALL-UNNAMED \
    --add-opens java.base/java.util=ALL-UNNAMED \
    -cp "$AOTCACHE_CP" "$MAIN" "$test_op" "$WORK_DIR"
}

run_TreeCache() {
  local op="$1"
  "$JAVA_TREECACHE_BIN" -XX:AOTCache="$TREECACHE_AOT" \
    -XX:+AOTClassLinking \
    --add-modules java.instrument \
    --add-opens java.base/java.io=ALL-UNNAMED \
    --add-opens java.base/java.lang=ALL-UNNAMED \
    --add-opens java.base/java.lang.reflect=ALL-UNNAMED \
    --add-opens java.base/java.time=ALL-UNNAMED \
    --add-opens java.base/java.time.chrono=ALL-UNNAMED \
    --add-opens java.base/java.util=ALL-UNNAMED \
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

# ─── main measurement loop ───────────────────────────────────────────────────

log "Running Commons Compress workload RUNS=$RUNS"
for RUN_IDX in $(seq 1 "$RUNS"); do
  printf "  run %2d/%d\n" "$RUN_IDX" "$RUNS"
  # no-AOT and TreeCache: one pass over all ops
  for op in "${OPS[@]}"; do
    update_stats "${op}|no"     "$(measure_ms "$op" "no"     run_no     "$op")"
    update_stats "${op}|TreeCache" "$(measure_ms "$op" "TreeCache" run_TreeCache "$op")"
  done
  # AOTCache cross-workload: for each training op, run its cache on all other ops
  for train_op in "${OPS[@]}"; do
    for test_op in "${OPS[@]}"; do
      [[ "$test_op" == "$train_op" ]] && continue
      update_stats "${train_op}|${test_op}|aotcache" \
        "$(measure_ms "${train_op}>${test_op}" "aotcache" run_mono_cross "$train_op" "$test_op")"
    done
  done
done

# ─── results ─────────────────────────────────────────────────────────────────

print_summary() {
  echo
  log "Per-workload timing over ${RUNS} runs (ms) — AOTCache uses caches trained on other ops"
  sep
  printf "  %-16s | %18s | %20s %8s | %20s %8s\n" \
    "Workload" "no (mean±SD)" "aotcache (mean±SD)" "su-aotcache" "TreeCache (mean±SD)" "su-TreeCache"
  sep
  local op
  for op in "${OPS[@]}"; do
    local m_no m_mono m_TreeCache sd_no sd_mono sd_TreeCache su_mono su_TreeCache
    m_no=$(mean_for_key "${op}|no")
    m_mono=$(test_mean_aotcache "$op")
    m_TreeCache=$(mean_for_key "${op}|TreeCache")
    sd_no=$(stddev_for_key "${op}|no")
    sd_mono=$(test_stddev_aotcache "$op")
    sd_TreeCache=$(stddev_for_key "${op}|TreeCache")
    su_mono=$(awk   -v b="$m_no" -v a="$m_mono"   'BEGIN{if(a+0==0){print "n/a"}else{printf "%.2fx",b/a}}')
    su_TreeCache=$(awk -v b="$m_no" -v a="$m_TreeCache" 'BEGIN{if(a+0==0){print "n/a"}else{printf "%.2fx",b/a}}')
    printf "  %-16s | %18s | %20s %8s | %20s %8s\n" \
      "$op" "${m_no}±${sd_no}" "${m_mono}±${sd_mono}" "$su_mono" "${m_TreeCache}±${sd_TreeCache}" "$su_TreeCache"
  done
}

print_latex_rows() {
  local project="$1"
  local n="${#OPS[@]}"
  local tex_file="$WORK_DIR/latex-rows.tex"
  local sum_su_mono=0 sum_su_TreeCache=0
  echo "\\multirow{$(( n + 1 ))}{*}{${project}}" > "$tex_file"
  local op
  for op in "${OPS[@]}"; do
    local m_no m_mono m_TreeCache sd_no sd_mono sd_TreeCache su_mono su_TreeCache fmt_su_mono fmt_su_TreeCache
    m_no=$(mean_for_key "${op}|no")
    m_mono=$(test_mean_aotcache "$op")
    m_TreeCache=$(mean_for_key "${op}|TreeCache")
    sd_no=$(stddev_for_key "${op}|no")
    sd_mono=$(test_stddev_aotcache "$op")
    sd_TreeCache=$(stddev_for_key "${op}|TreeCache")
    su_mono=$(awk   -v b="$m_no" -v a="$m_mono"   'BEGIN{if(a+0==0){print "n/a"}else{printf "%.2f",b/a}}')
    su_TreeCache=$(awk -v b="$m_no" -v a="$m_TreeCache" 'BEGIN{if(a+0==0){print "n/a"}else{printf "%.2f",b/a}}')
    sum_su_mono=$(awk  "BEGIN{printf \"%.4f\", $sum_su_mono  + $su_mono}")
    sum_su_TreeCache=$(awk "BEGIN{printf \"%.4f\", $sum_su_TreeCache + $su_TreeCache}")
    fmt_su_mono=$(awk   -v a="$su_mono" -v b="$su_TreeCache" 'BEGIN{if(a+0>b+0) print "\\textbf{"a"x}" ; else print a"x"}')
    fmt_su_TreeCache=$(awk -v a="$su_mono" -v b="$su_TreeCache" 'BEGIN{if(b+0>a+0) print "\\textbf{"b"x}" ; else print b"x"}')
    echo "  & ${op} & \$${m_no} \pm ${sd_no}\$ & \$${m_mono} \pm ${sd_mono}\$ & ${fmt_su_mono} & \$${m_TreeCache} \pm ${sd_TreeCache}\$ & ${fmt_su_TreeCache} \\\\" >> "$tex_file"
  done
  local avg_mono avg_TreeCache fmt_avg_mono fmt_avg_TreeCache
  avg_mono=$(awk  -v s="$sum_su_mono"   -v n="$n" 'BEGIN{printf "%.2f", s/n}')
  avg_TreeCache=$(awk -v s="$sum_su_TreeCache" -v n="$n" 'BEGIN{printf "%.2f", s/n}')
  fmt_avg_mono=$(awk   -v a="$avg_mono" -v b="$avg_TreeCache" 'BEGIN{if(a+0>b+0) print "\\textbf{"a"x}" ; else print a"x"}')
  fmt_avg_TreeCache=$(awk -v a="$avg_mono" -v b="$avg_TreeCache" 'BEGIN{if(b+0>a+0) print "\\textbf{"b"x}" ; else print b"x"}')
  echo "  & \\textit{Average} & & & ${fmt_avg_mono} & & ${fmt_avg_TreeCache} \\\\" >> "$tex_file"
  echo "\\midrule" >> "$tex_file"
}

print_summary
print_latex_rows "commons-compress"

# ─── class-load summary (same-workload AOTCache for each op) ───────────────

print_class_load_row() {
  local mode="$1" op="$2"
  local classload_log="$WORK_DIR/classload-${op}-${mode}.log"
  case "$mode" in
    no)
      "$JAVA_NO_BIN" -Xlog:class+load:file="$classload_log" \
        --add-modules java.instrument \
        --add-opens java.base/java.io=ALL-UNNAMED \
        --add-opens java.base/java.lang=ALL-UNNAMED \
        --add-opens java.base/java.lang.reflect=ALL-UNNAMED \
        --add-opens java.base/java.time=ALL-UNNAMED \
        --add-opens java.base/java.time.chrono=ALL-UNNAMED \
        --add-opens java.base/java.util=ALL-UNNAMED \
        -cp "$CP" "$MAIN" "$op" "$WORK_DIR"
      ;;
    AOTCache)
      "$JAVA_AOTCACHE_BIN" -XX:AOTCache="single-${op}.aot" \
        -XX:+AOTClassLinking \
        -Xlog:class+load:file="$classload_log" \
        --add-modules java.instrument \
        --add-opens java.base/java.io=ALL-UNNAMED \
        --add-opens java.base/java.lang=ALL-UNNAMED \
        --add-opens java.base/java.lang.reflect=ALL-UNNAMED \
        --add-opens java.base/java.time=ALL-UNNAMED \
        --add-opens java.base/java.time.chrono=ALL-UNNAMED \
        --add-opens java.base/java.util=ALL-UNNAMED \
        -cp "$AOTCACHE_CP" "$MAIN" "$op" "$WORK_DIR"
      ;;
    TreeCache)
      "$JAVA_TREECACHE_BIN" -XX:AOTCache="$TREECACHE_AOT" \
        -XX:+AOTClassLinking \
        -Xlog:class+load:file="$classload_log" \
        --add-modules java.instrument \
        --add-opens java.base/java.io=ALL-UNNAMED \
        --add-opens java.base/java.lang=ALL-UNNAMED \
        --add-opens java.base/java.lang.reflect=ALL-UNNAMED \
        --add-opens java.base/java.time=ALL-UNNAMED \
        --add-opens java.base/java.time.chrono=ALL-UNNAMED \
        --add-opens java.base/java.util=ALL-UNNAMED \
        -cp "$CP" "$MAIN" "$op" "$WORK_DIR"
      ;;
  esac
  printf "  %-16s | %-6s | %8s | %8s\n" \
    "$op" "$mode" \
    "$(awk '/source: file:/{count++} END{print count+0}' "$classload_log")" \
    "$(awk '/source: shared object[s]? file/{count++} END{print count+0}' "$classload_log")"
}

echo
log "Class-load source summary per workload (AOTCache uses same-workload cache)"
sep
printf "  %-16s | %-6s | %8s | %8s\n" "Operation" "Mode" "file:" "shared"
for op in "${OPS[@]}"; do
  print_class_load_row "no" "$op"
  print_class_load_row "AOTCache" "$op"
  print_class_load_row "TreeCache" "$op"
  echo "--------------------------------"
done
