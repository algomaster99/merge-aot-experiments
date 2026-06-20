#!/bin/bash
set -euo pipefail

log()  { echo -e "\033[1;32m[$(date '+%H:%M:%S')] $*\033[0m"; }
sep()  { echo -e "\033[0;90m  $(printf '─%.0s' {1..60})\033[0m"; }
fail() { echo -e "\033[1;31mERROR: $*\033[0m" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

DETEKT="$SCRIPT_DIR/detekt"
BENCH_JAR="benchmark/target/benchmark-1.0-SNAPSHOT.jar"
MAIN="dev.detektexp.MainKt"
WORK_DIR="workload-tmp"
TREE_AOT="tree.aot"
RUNS="${RUNS:-30}"
JAVA_NO_BIN="${JAVA_NO_BIN:-java}"
JAVA_SINGLE_BIN="${JAVA_SINGLE_BIN:-java}"
JAVA_TREE_BIN="${JAVA_TREE_BIN:-java}"
OPS=("analyze-complexity" "analyze-style" "analyze-naming" "analyze-bugs" "analyze-coroutines")

[[ -f "$BENCH_JAR" ]] || fail "$BENCH_JAR not found — run: cd benchmark && mvn package -DskipTests"
for op in "${OPS[@]}"; do
  [[ -f "single-${op}.aot" ]] || fail "single-${op}.aot not found — run: ./create-single-aot.sh $op"
done
[[ -f "$TREE_AOT" ]] || fail "tree.aot not found — run ./orchestrate-combine.sh first"

# Detekt modules from source tree (same classpath used by mvn test -P tree-merge)
DETEKT_CP="\
$DETEKT/detekt-utils/target/classes:\
$DETEKT/detekt-tooling/target/classes:\
$DETEKT/detekt-psi-utils/target/classes:\
$DETEKT/detekt-api/target/classes:\
$DETEKT/detekt-parser/target/classes:\
$DETEKT/detekt-metrics/target/classes:\
$DETEKT/detekt-rules-complexity/target/classes:\
$DETEKT/detekt-rules-style/target/classes:\
$DETEKT/detekt-rules-naming/target/classes:\
$DETEKT/detekt-rules-errorprone/target/classes:\
$DETEKT/detekt-rules-coroutines/target/classes"

# Fat JAR provides all external deps; detekt modules come from target/classes
CP="$BENCH_JAR:$DETEKT_CP"

JAVA_ARGS=(
  --add-opens java.base/java.lang=ALL-UNNAMED
  --add-opens java.base/java.util=ALL-UNNAMED
  --add-opens java.base/java.io=ALL-UNNAMED
)

mkdir -p "$WORK_DIR"
"$JAVA_NO_BIN" "${JAVA_ARGS[@]}" -cp "$CP" "$MAIN" prepare "$WORK_DIR" >/dev/null

log "Java version: $("$JAVA_NO_BIN" -version 2>&1 | head -1)"

ms() { date +%s%N | awk '{printf "%.1f", $1/1000000}'; }

declare -A minv maxv cnt samples

update_stats() {
  local key="$1" t="$2"
  cnt[$key]=$(( ${cnt[$key]:-0} + 1 ))
  samples[$key]="${samples[$key]:-} $t"
  if [[ -z "${minv[$key]:-}" ]] || awk "BEGIN{exit !(${t}<${minv[$key]})}"; then minv[$key]="$t"; fi
  if [[ -z "${maxv[$key]:-}" ]] || awk "BEGIN{exit !(${t}>${maxv[$key]})}"; then maxv[$key]="$t"; fi
}

mean_for_key() {
  printf "%s\n" ${samples[$1]:-} | awk '{s+=$1;n++}END{if(n==0){print "n/a"}else{printf "%.1f",s/n}}'
}

stddev_for_key() {
  printf "%s\n" ${samples[$1]:-} | awk '{s+=$1;q+=$1*$1;n++}END{if(n<2){print "n/a"}else{printf "%.1f",sqrt((q-s*s/n)/(n-1))}}'
}

run_no() {
  "$JAVA_NO_BIN" "${JAVA_ARGS[@]}" -cp "$CP" "$MAIN" "$1" "$WORK_DIR"
}

run_single() {  # train_op test_op
  "$JAVA_SINGLE_BIN" -XX:AOTCache="single-${1}.aot" -XX:+AOTClassLinking \
    "${JAVA_ARGS[@]}" -cp "$CP" "$MAIN" "$2" "$WORK_DIR"
}

run_tree() {
  "$JAVA_TREE_BIN" -XX:AOTCache="$TREE_AOT" -XX:+AOTClassLinking \
    "${JAVA_ARGS[@]}" -cp "$CP" "$MAIN" "$1" "$WORK_DIR"
}

measure_ms() {
  local label="$1" mode="$2"; shift 2
  local err_file="$WORK_DIR/${RUN_IDX:-0}-${label//>/→}-${mode}.stderr.log"
  local start end rc
  start=$(ms)
  "$@" >/dev/null 2>"$err_file"
  rc=$?
  if [[ $rc -ne 0 ]]; then
    echo "ERROR: $label mode=$mode rc=$rc — see $err_file" >&2; return $rc
  fi
  end=$(ms)
  awk "BEGIN{printf \"%.1f\",$end-$start}"
}

test_mean_single() {
  local test_op="$1" sum=0 n=0
  for train_op in "${OPS[@]}"; do
    [[ "$train_op" == "$test_op" ]] && continue
    local m; m=$(mean_for_key "${train_op}|${test_op}|single")
    sum=$(awk "BEGIN{printf \"%.4f\",$sum+$m}"); n=$(( n+1 ))
  done
  awk -v s="$sum" -v n="$n" 'BEGIN{printf "%.1f",s/n}'
}

test_stddev_single() {
  local test_op="$1" all=""
  for train_op in "${OPS[@]}"; do
    [[ "$train_op" == "$test_op" ]] && continue
    all="$all ${samples[${train_op}|${test_op}|single]:-}"
  done
  printf "%s\n" $all | awk '{s+=$1;q+=$1*$1;n++}END{if(n<2){print "n/a"}else{printf "%.1f",sqrt((q-s*s/n)/(n-1))}}'
}

log "Running detekt workloads RUNS=$RUNS"
for RUN_IDX in $(seq 1 "$RUNS"); do
  printf "  run %2d/%d\n" "$RUN_IDX" "$RUNS"
  for op in "${OPS[@]}"; do
    update_stats "${op}|no"   "$(measure_ms "$op" "no"   run_no   "$op")"
    update_stats "${op}|tree" "$(measure_ms "$op" "tree" run_tree "$op")"
  done
  for train_op in "${OPS[@]}"; do
    for test_op in "${OPS[@]}"; do
      [[ "$test_op" == "$train_op" ]] && continue
      update_stats "${train_op}|${test_op}|single" \
        "$(measure_ms "${train_op}>${test_op}" "single" run_single "$train_op" "$test_op")"
    done
  done
done

print_summary() {
  echo
  log "Per-workload timing over ${RUNS} runs (ms) — single uses cache trained on a different op"
  sep
  printf "  %-20s | %18s | %20s %8s | %20s %8s\n" \
    "Workload" "no (mean±SD)" "single (mean±SD)" "su-single" "tree (mean±SD)" "su-tree"
  sep
  for op in "${OPS[@]}"; do
    local m_no m_single m_tree sd_no sd_single sd_tree su_single su_tree
    m_no=$(mean_for_key "${op}|no")
    m_single=$(test_mean_single "$op")
    m_tree=$(mean_for_key "${op}|tree")
    sd_no=$(stddev_for_key "${op}|no")
    sd_single=$(test_stddev_single "$op")
    sd_tree=$(stddev_for_key "${op}|tree")
    su_single=$(awk -v b="$m_no" -v a="$m_single" 'BEGIN{if(a+0==0){print "n/a"}else{printf "%.2fx",b/a}}')
    su_tree=$(awk   -v b="$m_no" -v a="$m_tree"   'BEGIN{if(a+0==0){print "n/a"}else{printf "%.2fx",b/a}}')
    printf "  %-20s | %18s | %20s %8s | %20s %8s\n" \
      "$op" "${m_no}±${sd_no}" "${m_single}±${sd_single}" "$su_single" "${m_tree}±${sd_tree}" "$su_tree"
  done
}

print_latex_rows() {
  local project="$1"
  local n="${#OPS[@]}"
  local tex_file="$WORK_DIR/latex-rows.tex"
  local sum_su_single=0 sum_su_tree=0
  echo "\\multirow{$(( n + 1 ))}{*}{${project}}" > "$tex_file"
  for op in "${OPS[@]}"; do
    local m_no m_single m_tree sd_no sd_single sd_tree su_single su_tree fmt_su_single fmt_su_tree
    m_no=$(mean_for_key "${op}|no")
    m_single=$(test_mean_single "$op")
    m_tree=$(mean_for_key "${op}|tree")
    sd_no=$(stddev_for_key "${op}|no")
    sd_single=$(test_stddev_single "$op")
    sd_tree=$(stddev_for_key "${op}|tree")
    su_single=$(awk -v b="$m_no" -v a="$m_single" 'BEGIN{if(a+0==0){print "n/a"}else{printf "%.2f",b/a}}')
    su_tree=$(awk   -v b="$m_no" -v a="$m_tree"   'BEGIN{if(a+0==0){print "n/a"}else{printf "%.2f",b/a}}')
    sum_su_single=$(awk "BEGIN{printf \"%.4f\",$sum_su_single+$su_single}")
    sum_su_tree=$(awk   "BEGIN{printf \"%.4f\",$sum_su_tree+$su_tree}")
    fmt_su_single=$(awk -v a="$su_single" -v b="$su_tree" 'BEGIN{if(a+0>b+0) print "\\textbf{"a"x}"; else print a"x"}')
    fmt_su_tree=$(awk   -v a="$su_single" -v b="$su_tree" 'BEGIN{if(b+0>a+0) print "\\textbf{"b"x}"; else print b"x"}')
    echo "  & ${op} & \$${m_no} \\pm ${sd_no}\$ & \$${m_single} \\pm ${sd_single}\$ & ${fmt_su_single} & \$${m_tree} \\pm ${sd_tree}\$ & ${fmt_su_tree} \\\\" >> "$tex_file"
  done
  local avg_single avg_tree fmt_avg_single fmt_avg_tree
  avg_single=$(awk -v s="$sum_su_single" -v n="$n" 'BEGIN{printf "%.2f",s/n}')
  avg_tree=$(awk   -v s="$sum_su_tree"   -v n="$n" 'BEGIN{printf "%.2f",s/n}')
  fmt_avg_single=$(awk -v a="$avg_single" -v b="$avg_tree" 'BEGIN{if(a+0>b+0) print "\\textbf{"a"x}"; else print a"x"}')
  fmt_avg_tree=$(awk   -v a="$avg_single" -v b="$avg_tree" 'BEGIN{if(b+0>a+0) print "\\textbf{"b"x}"; else print b"x"}')
  echo "  & \\textit{Average} & & & ${fmt_avg_single} & & ${fmt_avg_tree} \\\\" >> "$tex_file"
  echo "\\midrule" >> "$tex_file"
}

print_summary
print_latex_rows "detekt"
