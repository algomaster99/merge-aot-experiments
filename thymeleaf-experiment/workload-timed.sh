#!/bin/bash
set -euo pipefail

log()  { echo -e "\033[1;32m[$(date '+%H:%M:%S')] $*\033[0m"; }
sep()  { echo -e "\033[0;90m  $(printf '─%.0s' {1..68})\033[0m"; }
fail() { echo -e "\033[1;31mERROR: $*\033[0m" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

FAT_JAR="benchmark/target/benchmark-fat.jar"
WORK_DIR="workload-tmp"
TREECACHE_AOT="tree.aot"

RUNS="${RUNS:-30}"
JAVA_NO_BIN="${JAVA_NO_BIN:-java}"
JAVA_AOTCACHE_BIN="${JAVA_AOTCACHE_BIN:-java}"
JAVA_TREECACHE_BIN="${JAVA_TREECACHE_BIN:-java}"

OPS=(html-render text-render xml-render fragment-render)

[[ -f "$FAT_JAR" ]] || fail "$FAT_JAR not found — run: cd benchmark && mvn package -DskipTests"
for _op in "${OPS[@]}"; do
  [[ -f "single-${_op}.aot" ]] || fail "single-${_op}.aot not found — run ./create-single-aot.sh first"
done
[[ -f "$TREECACHE_AOT" ]] || fail "tree.aot not found — run ./orchestrate-combine.sh first"

mkdir -p "$WORK_DIR"

log "Java binaries:"
printf "  no-AOT:         %s\n" "$JAVA_NO_BIN";         "$JAVA_NO_BIN"         -version 2>&1 | head -1
printf "  AOTCache-AOT: %s\n" "$JAVA_AOTCACHE_BIN"; "$JAVA_AOTCACHE_BIN" -version 2>&1 | head -1
printf "  TreeCache-AOT:     %s\n" "$JAVA_TREECACHE_BIN";     "$JAVA_TREECACHE_BIN"     -version 2>&1 | head -1
echo

# ─── run helpers ─────────────────────────────────────────────────────────────

_run_no()     { "$JAVA_NO_BIN"     -jar "$FAT_JAR" "$1"; }
_run_treecache() { "$JAVA_TREECACHE_BIN" -XX:AOTCache="$TREECACHE_AOT" -XX:+AOTClassLinking \
  --add-opens java.base/java.lang=ALL-UNNAMED --add-opens java.base/java.util=ALL-UNNAMED \
  -jar "$FAT_JAR" "$1"; }

# train_op determines which single-{op}.aot to load; test_op is the workload run.
_run_aotcache_cross() {
  local train_op="$1" test_op="$2"
  "$JAVA_AOTCACHE_BIN" -XX:AOTCache="single-${train_op}.aot" -XX:+AOTClassLinking \
    -jar "$FAT_JAR" "$test_op"
}

# ─── timing helpers ──────────────────────────────────────────────────────────

ms() { date +%s%N | awk '{printf "%.1f", $1/1000000}'; }

declare -A _min _max _samples

_update() {
  local key="$1" v="$2"
  _samples[$key]="${_samples[$key]:-} $v"
  if [[ -z "${_min[$key]:-}" ]] || awk "BEGIN{exit !($v < ${_min[$key]})}"; then _min[$key]=$v; fi
  if [[ -z "${_max[$key]:-}" ]] || awk "BEGIN{exit !($v > ${_max[$key]})}"; then _max[$key]=$v; fi
}

_mean() {
  printf "%s\n" ${_samples[$1]:-} | awk '
    {sum+=$1; n++}
    END{ if(!n){print "n/a"} else{printf "%.1f",sum/n} }'
}

_stddev() {
  printf "%s\n" ${_samples[$1]:-} | awk '
    {sum+=$1; sumsq+=$1*$1; n++}
    END{ if(n<2){print "n/a"} else{printf "%.1f",sqrt((sumsq-sum*sum/n)/(n-1))} }'
}

_measure_no() {
  local op="$1" run="$2"
  local errfile="$WORK_DIR/err-${op}-no-${run}.log"
  local t0 t1 rc=0
  t0=$(ms); _run_no "$op" >/dev/null 2>"$errfile" || rc=$?; t1=$(ms)
  if (( rc != 0 )); then echo "  WARN: op=$op mode=no run=$run exited $rc — see $errfile" >&2; return; fi
  _update "${op}|no" "$(awk "BEGIN{printf \"%.1f\",$t1-$t0}")"
}

_measure_treecache() {
  local op="$1" run="$2"
  local errfile="$WORK_DIR/err-${op}-TreeCache-${run}.log"
  local t0 t1 rc=0
  t0=$(ms); _run_treecache "$op" >/dev/null 2>"$errfile" || rc=$?; t1=$(ms)
  if (( rc != 0 )); then echo "  WARN: op=$op mode=TreeCache run=$run exited $rc — see $errfile" >&2; return; fi
  _update "${op}|TreeCache" "$(awk "BEGIN{printf \"%.1f\",$t1-$t0}")"
}

_measure_aotcache_cross() {
  local train_op="$1" test_op="$2" run="$3"
  local errfile="$WORK_DIR/err-${train_op}-${test_op}-aotcache-${run}.log"
  local t0 t1 rc=0
  t0=$(ms); _run_aotcache_cross "$train_op" "$test_op" >/dev/null 2>"$errfile" || rc=$?; t1=$(ms)
  if (( rc != 0 )); then
    echo "  WARN: train=$train_op test=$test_op run=$run exited $rc — see $errfile" >&2; return
  fi
  _update "${train_op}|${test_op}|aotcache" "$(awk "BEGIN{printf \"%.1f\",$t1-$t0}")"
}

# Mean over all test ops ≠ train_op.
# mode: "no" → ${test}|no   "aotcache" → ${train}|${test}|aotcache   "TreeCache" → ${test}|TreeCache
_cross_mean() {
  local train_op="$1" mode="$2"
  local sum=0 n=0 test_op key m
  for test_op in "${OPS[@]}"; do
    [[ "$test_op" == "$train_op" ]] && continue
    case "$mode" in
      no)        key="${test_op}|no" ;;
      aotcache)  key="${train_op}|${test_op}|aotcache" ;;
      TreeCache) key="${test_op}|TreeCache" ;;
    esac
    m=$(_mean "$key")
    sum=$(awk "BEGIN{printf \"%.4f\", $sum + $m}")
    n=$(( n + 1 ))
  done
  awk -v s="$sum" -v n="$n" 'BEGIN{printf "%.1f", s/n}'
}

# Pool all cross-workload samples for a given train_op and mode, then compute SD.
# no/TreeCache: 30 runs × (N-1) test ops; aotcache: same (30 × N-1 cross pairs).
_cross_stddev() {
  local train_op="$1" mode="$2"
  local all_samples="" test_op key
  for test_op in "${OPS[@]}"; do
    [[ "$test_op" == "$train_op" ]] && continue
    case "$mode" in
      no)        key="${test_op}|no" ;;
      aotcache)  key="${train_op}|${test_op}|aotcache" ;;
      TreeCache) key="${test_op}|TreeCache" ;;
    esac
    all_samples="$all_samples ${_samples[$key]:-}"
  done
  printf "%s\n" $all_samples | awk '
    {sum+=$1; sumsq+=$1*$1; n++}
    END{ if(n<2){print "n/a"} else{printf "%.1f",sqrt((sumsq-sum*sum/n)/(n-1))} }'
}

# ─── main measurement loop ───────────────────────────────────────────────────

log "Running $RUNS iterations × ${#OPS[@]} ops (cross-workload)"
sep

for run in $(seq 1 "$RUNS"); do
  printf "  run %2d/%d\n" "$run" "$RUNS"
  # no-AOT and TreeCache: one pass over all ops
  for op in "${OPS[@]}"; do
    _measure_no     "$op" "$run"
    _measure_treecache "$op" "$run"
  done
  # AOTCache cross-workload: for each training op, run its cache on all other ops
  for train_op in "${OPS[@]}"; do
    for test_op in "${OPS[@]}"; do
      [[ "$test_op" == "$train_op" ]] && continue
      _measure_aotcache_cross "$train_op" "$test_op" "$run"
    done
  done
done

# ─── results ─────────────────────────────────────────────────────────────────

echo
log "Cross-workload timing over $RUNS runs (ms) — train on X, mean±SD of other 3 ops"
sep
printf "  %-16s | %18s | %20s %8s | %20s %8s\n" \
  "Trained on" "no (mean±SD)" "aotcache (mean±SD)" "su-aotcache" "TreeCache (mean±SD)" "su-TreeCache"
sep
for train_op in "${OPS[@]}"; do
  m_no=$(_cross_mean "$train_op" "no")
  m_mono=$(_cross_mean "$train_op" "aotcache")
  m_TreeCache=$(_cross_mean "$train_op" "TreeCache")
  sd_no=$(_cross_stddev "$train_op" "no")
  sd_mono=$(_cross_stddev "$train_op" "aotcache")
  sd_TreeCache=$(_cross_stddev "$train_op" "TreeCache")
  su_mono=$(awk   -v b="$m_no" -v a="$m_mono"   'BEGIN{if(a+0==0){print "n/a"}else{printf "%.2fx",b/a}}')
  su_TreeCache=$(awk -v b="$m_no" -v a="$m_TreeCache" 'BEGIN{if(a+0==0){print "n/a"}else{printf "%.2fx",b/a}}')
  printf "  %-16s | %18s | %20s %8s | %20s %8s\n" \
    "$train_op" "${m_no}±${sd_no}" "${m_mono}±${sd_mono}" "$su_mono" "${m_TreeCache}±${sd_TreeCache}" "$su_TreeCache"
done

# ─── LaTeX rows ──────────────────────────────────────────────────────────────

_print_latex_rows() {
  local project="$1"
  local n="${#OPS[@]}"
  local tex_file="$WORK_DIR/latex-rows.tex"
  local sum_su_mono=0 sum_su_TreeCache=0
  echo "\\multirow{$(( n + 1 ))}{*}{${project}}" > "$tex_file"
  local train_op
  for train_op in "${OPS[@]}"; do
    local m_no m_mono m_TreeCache sd_no sd_mono sd_TreeCache su_mono su_TreeCache fmt_su_mono fmt_su_TreeCache
    m_no=$(_cross_mean "$train_op" "no")
    m_mono=$(_cross_mean "$train_op" "aotcache")
    m_TreeCache=$(_cross_mean "$train_op" "TreeCache")
    sd_no=$(_cross_stddev "$train_op" "no")
    sd_mono=$(_cross_stddev "$train_op" "aotcache")
    sd_TreeCache=$(_cross_stddev "$train_op" "TreeCache")
    su_mono=$(awk   -v b="$m_no" -v a="$m_mono"   'BEGIN{if(a+0==0){print "n/a"}else{printf "%.2f",b/a}}')
    su_TreeCache=$(awk -v b="$m_no" -v a="$m_TreeCache" 'BEGIN{if(a+0==0){print "n/a"}else{printf "%.2f",b/a}}')
    sum_su_mono=$(awk  "BEGIN{printf \"%.4f\", $sum_su_mono   + $su_mono}")
    sum_su_TreeCache=$(awk "BEGIN{printf \"%.4f\", $sum_su_TreeCache + $su_TreeCache}")
    fmt_su_mono=$(awk   -v a="$su_mono" -v b="$su_TreeCache" 'BEGIN{if(a+0>b+0) print "\\textbf{"a"x}" ; else print a"x"}')
    fmt_su_TreeCache=$(awk -v a="$su_mono" -v b="$su_TreeCache" 'BEGIN{if(b+0>a+0) print "\\textbf{"b"x}" ; else print b"x"}')
    echo "  & ${train_op} & \$${m_no} \pm ${sd_no}\$ & \$${m_mono} \pm ${sd_mono}\$ & ${fmt_su_mono} & \$${m_TreeCache} \pm ${sd_TreeCache}\$ & ${fmt_su_TreeCache} \\\\" >> "$tex_file"
  done
  local avg_mono avg_TreeCache fmt_avg_mono fmt_avg_TreeCache
  avg_mono=$(awk   -v s="$sum_su_mono"   -v n="$n" 'BEGIN{printf "%.2f", s/n}')
  avg_TreeCache=$(awk -v s="$sum_su_TreeCache" -v n="$n" 'BEGIN{printf "%.2f", s/n}')
  fmt_avg_mono=$(awk   -v a="$avg_mono" -v b="$avg_TreeCache" 'BEGIN{if(a+0>b+0) print "\\textbf{"a"x}" ; else print a"x"}')
  fmt_avg_TreeCache=$(awk -v a="$avg_mono" -v b="$avg_TreeCache" 'BEGIN{if(b+0>a+0) print "\\textbf{"b"x}" ; else print b"x"}')
  echo "  & \\textit{Average} & & & ${fmt_avg_mono} & & ${fmt_avg_TreeCache} \\\\" >> "$tex_file"
  echo "\\midrule" >> "$tex_file"
}

_print_latex_rows "thymeleaf"

# ─── class-load summary (same-workload AOTCache for each op) ───────────────

_classload_row() {
  local op="$1" mode="$2"
  local logfile="$WORK_DIR/cl-${op}-${mode}.log"
  case "$mode" in
    no)         "$JAVA_NO_BIN"         -Xlog:class+load:file="$logfile" -jar "$FAT_JAR" "$op" >/dev/null 2>&1 ;;
    AOTCache) "$JAVA_AOTCACHE_BIN" -XX:AOTCache="single-${op}.aot" -XX:+AOTClassLinking \
                  -Xlog:class+load:file="$logfile" -jar "$FAT_JAR" "$op" >/dev/null 2>&1 ;;
    TreeCache)     "$JAVA_TREECACHE_BIN"     -XX:AOTCache="$TREECACHE_AOT" -XX:+AOTClassLinking \
                  --add-opens java.base/java.lang=ALL-UNNAMED --add-opens java.base/java.util=ALL-UNNAMED \
                  -Xlog:class+load:file="$logfile" -jar "$FAT_JAR" "$op" >/dev/null 2>&1 ;;
  esac
  printf "  %-16s | %-10s | %8s | %8s\n" "$op" "$mode" \
    "$(awk '/source: file:/{c++} END{print c+0}' "$logfile")" \
    "$(awk '/source: shared object/{c++} END{print c+0}' "$logfile")"
}

echo
log "Class-load source breakdown (AOTCache uses same-workload cache)"
sep
printf "  %-16s | %-10s | %8s | %8s\n" "Operation" "Mode" "file:" "shared"
sep
for op in "${OPS[@]}"; do
  _classload_row "$op" no
  _classload_row "$op" AOTCache
  _classload_row "$op" TreeCache
  sep
done
