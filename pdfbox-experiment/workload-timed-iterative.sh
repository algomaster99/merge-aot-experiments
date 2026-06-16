#!/bin/bash
# Timing comparison for the iterative-AOT JDK build (PR 31344). Three modes:
#   no        — no AOT cache
#   aotcache  — single-iterjdk-{op}.aot cross-workload (cache trained on the
#               other ops, run on this one) — same shape as the original
#               cross-workload test, rebuilt for this JDK build
#   iterative — iterative.aot, built incrementally by create-iterative-aot.sh
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
JAR="pdfbox/app/target/pdfbox-app-3.0.7.jar"
MAIN="org.apache.pdfbox.tools.PDFBox"
PDF="pdfbox/test.pdf"
BASE="iterjdk"
TMP="workload-tmp"
ITERATIVE_AOT="iterative.aot"
RUNS="${RUNS:-30}"
OPS=(export:text export:images render fromtext split merge decode overlay)

[[ -f "$JAR" ]] || fail "$JAR not found — build pdfbox first"
[[ -f "$PDF" ]] || fail "$PDF not found"
[[ -f "$ITERATIVE_AOT" ]] || fail "$ITERATIVE_AOT not found — run create-iterative-aot.sh first"
for _op in "${OPS[@]}"; do
  [[ -f "single-iterjdk-${_op//:/-}.aot" ]] || fail "single-iterjdk-${_op//:/-}.aot not found — run create-single-aot-iterjdk.sh first"
done

mkdir -p "$TMP"

log "Java binary under test: $JAVA_BIN"
"$JAVA_BIN" -version

op_args() {
  local op="$1"
  local -n _arr="$2"
  case "$op" in
    export:text)   _arr=(export:text   --input "$PDF" --output "$TMP/$BASE-text.txt") ;;
    export:images) _arr=(export:images --input "$PDF") ;;
    render)        _arr=(render        --input "$PDF") ;;
    fromtext)      _arr=(fromtext      --input "$TMP/$BASE-text.txt"
                           --output "$TMP/$BASE-from-text.pdf"
                           -standardFont Times-Roman) ;;
    split)         _arr=(split         --input "$PDF" -split 3 -outputPrefix "$TMP/split-$BASE") ;;
    merge)         _arr=(merge         --input "$TMP/split-$BASE-1.pdf"
                           --output "$TMP/merged-$BASE.pdf") ;;
    decode)        _arr=(decode "$PDF" "$TMP/$BASE-decoded.pdf") ;;
    overlay)       _arr=(overlay       -default "$PDF" --input "$PDF"
                           --output "$TMP/$BASE-overlay.pdf") ;;
    *) fail "Unknown op: $op" ;;
  esac
}

log "Preparing prerequisite files for workload…"
"$JAVA_BIN" -cp "$JAR" "$MAIN" export:text --input "$PDF" --output "$TMP/$BASE-text.txt" >/dev/null 2>&1
"$JAVA_BIN" -cp "$JAR" "$MAIN" split --input "$PDF" -split 3 -outputPrefix "$TMP/split-$BASE" >/dev/null 2>&1

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
  local -a args; op_args "$op" args
  "$JAVA_BIN" -cp "$JAR" "$MAIN" "${args[@]}"
}

# train_op determines which single-iterjdk-{op}.aot to load; test_op is the workload run.
run_aotcache_cross() {
  local train_op="$1" test_op="$2"
  local -a args; op_args "$test_op" args
  "$JAVA_BIN" -XX:AOTCache="single-iterjdk-${train_op//:/-}.aot" -XX:+AOTClassLinking \
    -cp "$JAR" "$MAIN" "${args[@]}"
}

run_iterative() {
  local op="$1"
  local -a args; op_args "$op" args
  "$JAVA_BIN" -XX:AOTCache="$ITERATIVE_AOT" -XX:+AOTClassLinking \
    -cp "$JAR" "$MAIN" "${args[@]}"
}

measure_ms() {
  local label_op="$1" label_mode="$2"
  shift 2
  local file_label_op="${label_op//>/-to-}"
  file_label_op="${file_label_op//:/-}"
  local err_file="$TMP/${RUN_IDX:-0}-${file_label_op}-${label_mode}.stderr.log"
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

log "Running PDFBox iterative-AOT workload RUNS=$RUNS"
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
  local safe="${op//:/-}"
  local classload_log="$TMP/classload-${safe}-${mode}.log"
  local -a args; op_args "$op" args
  case "$mode" in
    no)
      "$JAVA_BIN" -Xlog:class+load:file="$classload_log" \
        -cp "$JAR" "$MAIN" "${args[@]}" >/dev/null 2>&1
      ;;
    aotcache)
      "$JAVA_BIN" -XX:AOTCache="single-iterjdk-${safe}.aot" \
        -XX:+AOTClassLinking \
        -Xlog:class+load:file="$classload_log" \
        -cp "$JAR" "$MAIN" "${args[@]}" >/dev/null 2>&1
      ;;
    iterative)
      "$JAVA_BIN" -XX:AOTCache="$ITERATIVE_AOT" \
        -XX:+AOTClassLinking \
        -Xlog:class+load:file="$classload_log" \
        -cp "$JAR" "$MAIN" "${args[@]}" >/dev/null 2>&1
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
  safe="${op//:/-}"
  printf "  %-40s | %10s\n" "single-iterjdk-${safe}.aot" "$(du -h "single-iterjdk-${safe}.aot" | awk '{print $1}')"
done
for f in iterative-step*.aot; do
  [[ -f "$f" ]] || continue
  printf "  %-40s | %10s\n" "$f" "$(du -h "$f" | awk '{print $1}')"
done
printf "  %-40s | %10s\n" "iterative.aot" "$(du -h "$ITERATIVE_AOT" | awk '{print $1}')"
