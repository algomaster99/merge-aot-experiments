#!/bin/bash
set -euo pipefail

log()  { echo -e "\033[1;32m[$(date '+%H:%M:%S')] $*\033[0m"; }
sep()  { echo -e "\033[0;90m  $(printf '─%.0s' {1..60})\033[0m"; }
fail() { echo -e "\033[1;31mERROR: $*\033[0m" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# ─── classpath setup ─────────────────────────────────────────────────────────

# original JAR = just benchmark classes + resources (no deps); used with source classes dirs
ORIG_JAR="benchmark/target/original-benchmark-1.0-SNAPSHOT.jar"
# fat JAR = self-contained; used for single-AOT recording and playback
FAT_JAR="benchmark/target/benchmark-1.0-SNAPSHOT.jar"

OPENNLP_MODULES=(
  "opennlp/opennlp-tools"
  "opennlp/opennlp-tools-models"
  "opennlp/opennlp-uima"
  "opennlp/opennlp-morfologik-addon"
)
MORFOLOGIK_MODULES=(
  "opennlp-deps/morfologik/morfologik-fsa"
  "opennlp-deps/morfologik/morfologik-fsa-builders"
  "opennlp-deps/morfologik/morfologik-stemming"
  "opennlp-deps/morfologik/morfologik-tools"
)

CLASSES_CP=""
for mod in "${OPENNLP_MODULES[@]}" "${MORFOLOGIK_MODULES[@]}"; do
  CLASSES_CP="${CLASSES_CP}${mod}/target/classes:"
done
DEPS_JAR_CP="$(find combine-deps -name '*.jar' 2>/dev/null | sort | tr '\n' ':' | sed 's/:$//')"

# CP for no-AOT and TreeCache: source classes + external JARs (same structure as tree.aot recording)
CP="${ORIG_JAR}:${CLASSES_CP}${DEPS_JAR_CP}"
# CP for single-AOT: fat JAR (same structure as single.aot recording by create-single-aot.sh)
AOTCACHE_CP="${FAT_JAR}"

MAIN="opennlp.bench.Main"
WORK_DIR="workload-tmp"
TREECACHE_AOT="tree.aot"
RUNS="${RUNS:-30}"
JAVA_NO_BIN="${JAVA_NO_BIN:-java}"
JAVA_AOTCACHE_BIN="${JAVA_AOTCACHE_BIN:-java}"
JAVA_TREECACHE_BIN="${JAVA_TREECACHE_BIN:-java}"
OPS=("train-sentdetect" "train-postag" "build-dict")

[[ -f "$ORIG_JAR" ]] || fail "$ORIG_JAR not found — run: cd benchmark && mvn package -DskipTests"
[[ -f "$FAT_JAR"  ]] || fail "$FAT_JAR not found — run: cd benchmark && mvn package -DskipTests"
for _op in "${OPS[@]}"; do
  [[ -f "single-${_op}.aot" ]] || fail "single-${_op}.aot not found — run create-single-aot.sh first"
done
[[ -f "$TREECACHE_AOT" ]] || fail "tree.aot not found — run orchestrate-combine.sh first"

mkdir -p "$WORK_DIR"

log "Java version(s):"
echo "no-AOT java:       $JAVA_NO_BIN";       "$JAVA_NO_BIN"       -version
echo
echo "AOTCache java:     $JAVA_AOTCACHE_BIN"; "$JAVA_AOTCACHE_BIN" -version
echo
echo "TreeCache java:    $JAVA_TREECACHE_BIN"; "$JAVA_TREECACHE_BIN" -version
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

OPENS=(
  --add-opens java.base/java.io=ALL-UNNAMED
  --add-opens java.base/java.lang=ALL-UNNAMED
  --add-opens java.base/java.lang.reflect=ALL-UNNAMED
  --add-opens java.base/java.util=ALL-UNNAMED
  --add-opens java.base/jdk.internal.loader=ALL-UNNAMED
)

run_no() {
  local op="$1"
  "$JAVA_NO_BIN" \
    "${OPENS[@]}" \
    -cp "$CP" "$MAIN" "$op" "$WORK_DIR"
}

# train_op selects which single-{op}.aot to load; test_op is the workload executed.
run_mono_cross() {
  local train_op="$1" test_op="$2"
  "$JAVA_AOTCACHE_BIN" -XX:AOTCache="single-${train_op}.aot" \
    -XX:+AOTClassLinking \
    "${OPENS[@]}" \
    -cp "$AOTCACHE_CP" "$MAIN" "$test_op" "$WORK_DIR"
}

run_TreeCache() {
  local op="$1"
  "$JAVA_TREECACHE_BIN" -XX:AOTCache="$TREECACHE_AOT" \
    -XX:+AOTClassLinking \
    "${OPENS[@]}" \
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

log "Running OpenNLP-Morfologik workloads RUNS=$RUNS"
for RUN_IDX in $(seq 1 "$RUNS"); do
  printf "  run %2d/%d\n" "$RUN_IDX" "$RUNS"
  for op in "${OPS[@]}"; do
    update_stats "${op}|no"        "$(measure_ms "$op" "no"        run_no        "$op")"
    update_stats "${op}|TreeCache" "$(measure_ms "$op" "TreeCache" run_TreeCache "$op")"
  done
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
    su_mono=$(awk   -v b="$m_no" -v a="$m_mono"      'BEGIN{if(a+0==0){print "n/a"}else{printf "%.2fx",b/a}}')
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
    su_mono=$(awk   -v b="$m_no" -v a="$m_mono"      'BEGIN{if(a+0==0){print "n/a"}else{printf "%.2f",b/a}}')
    su_TreeCache=$(awk -v b="$m_no" -v a="$m_TreeCache" 'BEGIN{if(a+0==0){print "n/a"}else{printf "%.2f",b/a}}')
    sum_su_mono=$(awk      "BEGIN{printf \"%.4f\", $sum_su_mono      + $su_mono}")
    sum_su_TreeCache=$(awk "BEGIN{printf \"%.4f\", $sum_su_TreeCache + $su_TreeCache}")
    fmt_su_mono=$(awk      -v a="$su_mono" -v b="$su_TreeCache" 'BEGIN{if(a+0>b+0) print "\\textbf{"a"x}" ; else print a"x"}')
    fmt_su_TreeCache=$(awk -v a="$su_mono" -v b="$su_TreeCache" 'BEGIN{if(b+0>a+0) print "\\textbf{"b"x}" ; else print b"x"}')
    echo "  & ${op} & \$${m_no} \pm ${sd_no}\$ & \$${m_mono} \pm ${sd_mono}\$ & ${fmt_su_mono} & \$${m_TreeCache} \pm ${sd_TreeCache}\$ & ${fmt_su_TreeCache} \\\\" >> "$tex_file"
  done
  local avg_mono avg_TreeCache fmt_avg_mono fmt_avg_TreeCache
  avg_mono=$(awk      -v s="$sum_su_mono"      -v n="$n" 'BEGIN{printf "%.2f", s/n}')
  avg_TreeCache=$(awk -v s="$sum_su_TreeCache" -v n="$n" 'BEGIN{printf "%.2f", s/n}')
  fmt_avg_mono=$(awk      -v a="$avg_mono" -v b="$avg_TreeCache" 'BEGIN{if(a+0>b+0) print "\\textbf{"a"x}" ; else print a"x"}')
  fmt_avg_TreeCache=$(awk -v a="$avg_mono" -v b="$avg_TreeCache" 'BEGIN{if(b+0>a+0) print "\\textbf{"b"x}" ; else print b"x"}')
  echo "  & \\textit{Average} & & & ${fmt_avg_mono} & & ${fmt_avg_TreeCache} \\\\" >> "$tex_file"
  echo "\\midrule" >> "$tex_file"
  log "LaTeX rows written to $tex_file"
}

print_summary
print_latex_rows "opennlp-morfologik"

# ─── class-load summary (same-workload AOTCache for each op) ─────────────────

print_class_load_row() {
  local mode="$1" op="$2"
  local classload_log="$WORK_DIR/classload-${op}-${mode}.log"
  case "$mode" in
    no)
      "$JAVA_NO_BIN" -Xlog:class+load:file="$classload_log" \
        "${OPENS[@]}" \
        -cp "$CP" "$MAIN" "$op" "$WORK_DIR"
      ;;
    AOTCache)
      "$JAVA_AOTCACHE_BIN" -XX:AOTCache="single-${op}.aot" \
        -XX:+AOTClassLinking \
        -Xlog:class+load:file="$classload_log" \
        "${OPENS[@]}" \
        -cp "$AOTCACHE_CP" "$MAIN" "$op" "$WORK_DIR"
      ;;
    TreeCache)
      "$JAVA_TREECACHE_BIN" -XX:AOTCache="$TREECACHE_AOT" \
        -XX:+AOTClassLinking \
        -Xlog:class+load:file="$classload_log" \
        "${OPENS[@]}" \
        -cp "$CP" "$MAIN" "$op" "$WORK_DIR"
      ;;
  esac
  printf "  %-16s | %-9s | %8s | %8s\n" \
    "$op" "$mode" \
    "$(awk '/source: file:/{count++} END{print count+0}' "$classload_log")" \
    "$(awk '/source: shared object[s]? file/{count++} END{print count+0}' "$classload_log")"
}

echo
log "Class-load source summary per workload (AOTCache uses same-workload cache)"
sep
printf "  %-16s | %-9s | %8s | %8s\n" "Operation" "Mode" "file:" "shared"
sep
for op in "${OPS[@]}"; do
  print_class_load_row "no"        "$op"
  print_class_load_row "AOTCache"  "$op"
  print_class_load_row "TreeCache" "$op"
  sep
done
