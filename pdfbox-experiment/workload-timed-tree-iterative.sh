#!/bin/bash
# Timing comparison for the dep-chain iterative AOT cache (iterative-tree.aot).
# Three modes per workload:
#
#   no           — no AOT cache (plain JDK baseline)
#   aotcache     — single-iterjdk-{train_op}.aot cross-workload: cache trained
#                  on one op, run on all other ops, mean taken over the others
#   iterative-tree — iterative-tree.aot built by create-iterative-aot-deps.sh
#                    (pdfbox reactor iterative chain → bc deps → commons-logging)
#
# Usage:
#   JAVA_BIN=<aot-re-jdk>/bin/java RUNS=30 ./workload-timed-tree-iterative.sh
set -euo pipefail

log()  { echo -e "\033[1;32m[$(date '+%H:%M:%S')] $*\033[0m"; }
sep()  { echo -e "\033[0;90m  $(printf '─%.0s' {1..60})\033[0m"; }
fail() { echo -e "\033[1;31mERROR: $*\033[0m" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

JAVA_NO_BIN="${JAVA_NO_BIN:-${JAVA_BIN:-java}}"
JAVA_AOTCACHE_BIN="${JAVA_AOTCACHE_BIN:-${JAVA_BIN:-java}}"
JAVA_TREE_ITER_BIN="${JAVA_TREE_ITER_BIN:-${JAVA_BIN:-java}}"
JAR="pdfbox/app/target/pdfbox-app-3.0.7.jar"
MAIN="org.apache.pdfbox.tools.PDFBox"
PDF="pdfbox/test.pdf"
BASE="tree-iter"
TMP="workload-tmp"
TREE_ITER_AOT="iterative-tree.aot"
RUNS="${RUNS:-30}"
OPS=(export:text export:images render fromtext split merge decode overlay)

[[ -f "$JAR" ]]           || fail "$JAR not found — build pdfbox first"
[[ -f "$PDF" ]]           || fail "$PDF not found"
[[ -f "$TREE_ITER_AOT" ]] || fail "$TREE_ITER_AOT not found — run create-iterative-aot-deps.sh first"
for _op in "${OPS[@]}"; do
  [[ -f "single-iterjdk-${_op//:/-}.aot" ]] \
    || fail "single-iterjdk-${_op//:/-}.aot not found — run create-single-aot-iterjdk.sh first"
done

mkdir -p "$TMP"

log "Java binaries:"
printf "  no:          %s\n" "$JAVA_NO_BIN";       "$JAVA_NO_BIN"       -version 2>&1 | head -1
printf "  aotcache:    %s\n" "$JAVA_AOTCACHE_BIN"; "$JAVA_AOTCACHE_BIN" -version 2>&1 | head -1
printf "  tree-iter:   %s\n" "$JAVA_TREE_ITER_BIN"; "$JAVA_TREE_ITER_BIN" -version 2>&1 | head -1
echo

# ─── op args ─────────────────────────────────────────────────────────────────

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

log "Preparing prerequisite files…"
"$JAVA_NO_BIN" -cp "$JAR" "$MAIN" export:text --input "$PDF" --output "$TMP/$BASE-text.txt" >/dev/null 2>&1
"$JAVA_NO_BIN" -cp "$JAR" "$MAIN" split --input "$PDF" -split 3 -outputPrefix "$TMP/split-$BASE" >/dev/null 2>&1

# ─── runners ─────────────────────────────────────────────────────────────────

run_no() {
  local op="$1"; local -a args; op_args "$op" args
  "$JAVA_NO_BIN" -cp "$JAR" "$MAIN" "${args[@]}"
}

run_aotcache_cross() {
  local train_op="$1" test_op="$2"; local -a args; op_args "$test_op" args
  "$JAVA_AOTCACHE_BIN" -XX:AOTCache="single-iterjdk-${train_op//:/-}.aot" -XX:+AOTClassLinking \
    -cp "$JAR" "$MAIN" "${args[@]}"
}

run_tree_iter() {
  local op="$1"; local -a args; op_args "$op" args
  "$JAVA_TREE_ITER_BIN" -XX:AOTCache="$TREE_ITER_AOT" -XX:+AOTClassLinking \
    -cp "$JAR" "$MAIN" "${args[@]}"
}

# ─── timing helpers ──────────────────────────────────────────────────────────

ms() { date +%s%N | awk '{printf "%.1f", $1/1000000}'; }

declare -A _samples

_update() {
  local key="$1" v="$2"
  _samples[$key]="${_samples[$key]:-} $v"
}

_mean() {
  printf "%s\n" ${_samples[$1]:-} | awk \
    '{sum+=$1; n++} END{if(!n){print "n/a"}else{printf "%.1f",sum/n}}'
}

_stddev() {
  printf "%s\n" ${_samples[$1]:-} | awk \
    '{sum+=$1; sumsq+=$1*$1; n++}
     END{if(n<2){print "n/a"}else{printf "%.1f",sqrt((sumsq-sum*sum/n)/(n-1))}}'
}

_measure() {
  local key="$1" label="$2"; shift 2
  local safe="${label//:/-}"; safe="${safe//>/-}"
  local errfile="$TMP/${RUN_IDX:-0}-${safe}.stderr.log"
  local t0 t1 rc=0
  t0=$(ms); "$@" >/dev/null 2>"$errfile" || rc=$?; t1=$(ms)
  if (( rc != 0 )); then
    echo "  WARN: $label exited $rc — see $errfile" >&2; return
  fi
  _update "$key" "$(awk "BEGIN{printf \"%.1f\",$t1-$t0}")"
}

# Mean of test_op times over all caches trained on ≠ test_op.
_aotcache_cross_mean() {
  local test_op="$1" sum=0 n=0 train_op m
  for train_op in "${OPS[@]}"; do
    [[ "$train_op" == "$test_op" ]] && continue
    m=$(_mean "${train_op}|${test_op}|aotcache")
    sum=$(awk "BEGIN{printf \"%.4f\",$sum+$m}")
    n=$(( n+1 ))
  done
  awk -v s="$sum" -v n="$n" 'BEGIN{printf "%.1f",s/n}'
}

# Pooled SD of test_op across all cross-workload caches.
_aotcache_cross_stddev() {
  local test_op="$1" all="" train_op
  for train_op in "${OPS[@]}"; do
    [[ "$train_op" == "$test_op" ]] && continue
    all="$all ${_samples[${train_op}|${test_op}|aotcache]:-}"
  done
  printf "%s\n" $all | awk \
    '{sum+=$1; sumsq+=$1*$1; n++}
     END{if(n<2){print "n/a"}else{printf "%.1f",sqrt((sumsq-sum*sum/n)/(n-1))}}'
}

# ─── main measurement loop ────────────────────────────────────────────────────

log "Running PDFBox tree-iterative workload experiment — RUNS=$RUNS"
sep

for RUN_IDX in $(seq 1 "$RUNS"); do
  printf "  run %2d/%d\n" "$RUN_IDX" "$RUNS"
  for op in "${OPS[@]}"; do
    _measure "${op}|no"        "no:$op"        run_no        "$op"
    _measure "${op}|tree-iter" "tree-iter:$op" run_tree_iter "$op"
  done
  for train_op in "${OPS[@]}"; do
    for test_op in "${OPS[@]}"; do
      [[ "$test_op" == "$train_op" ]] && continue
      _measure "${train_op}|${test_op}|aotcache" "aotcache:${train_op}>${test_op}" \
        run_aotcache_cross "$train_op" "$test_op"
    done
  done
done

# ─── results table ───────────────────────────────────────────────────────────

echo
log "Per-workload timing over ${RUNS} runs (ms)"
sep
printf "  %-16s | %18s | %20s %8s | %22s %10s\n" \
  "Workload" "no (mean±SD)" "aotcache (mean±SD)" "su-aot" "tree-iter (mean±SD)" "su-tree-iter"
sep
for op in "${OPS[@]}"; do
  m_no=$(_mean "${op}|no")
  m_ac=$(_aotcache_cross_mean "$op")
  m_ti=$(_mean "${op}|tree-iter")
  sd_no=$(_stddev "${op}|no")
  sd_ac=$(_aotcache_cross_stddev "$op")
  sd_ti=$(_stddev "${op}|tree-iter")
  su_ac=$(awk -v b="$m_no" -v a="$m_ac" 'BEGIN{if(a+0==0){print "n/a"}else{printf "%.2fx",b/a}}')
  su_ti=$(awk -v b="$m_no" -v a="$m_ti" 'BEGIN{if(a+0==0){print "n/a"}else{printf "%.2fx",b/a}}')
  printf "  %-16s | %18s | %20s %8s | %22s %10s\n" \
    "$op" "${m_no}±${sd_no}" "${m_ac}±${sd_ac}" "$su_ac" "${m_ti}±${sd_ti}" "$su_ti"
done

# ─── LaTeX rows ──────────────────────────────────────────────────────────────

_latex_rows() {
  local project="$1"
  local n="${#OPS[@]}"
  local tex_file="$TMP/latex-rows-tree-iter.tex"
  local sum_su_ac=0 sum_su_ti=0
  echo "\\multirow{$(( n+1 ))}{*}{${project}}" > "$tex_file"
  local op
  for op in "${OPS[@]}"; do
    local m_no m_ac m_ti sd_no sd_ac sd_ti su_ac su_ti fmt_ac fmt_ti
    m_no=$(_mean "${op}|no");      sd_no=$(_stddev "${op}|no")
    m_ac=$(_aotcache_cross_mean "$op"); sd_ac=$(_aotcache_cross_stddev "$op")
    m_ti=$(_mean "${op}|tree-iter"); sd_ti=$(_stddev "${op}|tree-iter")
    su_ac=$(awk -v b="$m_no" -v a="$m_ac" 'BEGIN{if(a+0==0){print "0"}else{printf "%.2f",b/a}}')
    su_ti=$(awk -v b="$m_no" -v a="$m_ti" 'BEGIN{if(a+0==0){print "0"}else{printf "%.2f",b/a}}')
    sum_su_ac=$(awk "BEGIN{printf \"%.4f\",$sum_su_ac+$su_ac}")
    sum_su_ti=$(awk "BEGIN{printf \"%.4f\",$sum_su_ti+$su_ti}")
    fmt_ac=$(awk -v a="$su_ac" -v b="$su_ti" 'BEGIN{if(a+0>b+0){print "\\textbf{"a"x}"}else{print a"x"}}')
    fmt_ti=$(awk -v a="$su_ac" -v b="$su_ti" 'BEGIN{if(b+0>a+0){print "\\textbf{"b"x}"}else{print b"x"}}')
    echo "  & ${op} & \$${m_no}\\pm${sd_no}\$ & \$${m_ac}\\pm${sd_ac}\$ & ${fmt_ac} & \$${m_ti}\\pm${sd_ti}\$ & ${fmt_ti} \\\\" \
      >> "$tex_file"
  done
  local avg_ac avg_ti fmt_avg_ac fmt_avg_ti
  avg_ac=$(awk -v s="$sum_su_ac" -v n="$n" 'BEGIN{printf "%.2f",s/n}')
  avg_ti=$(awk -v s="$sum_su_ti" -v n="$n" 'BEGIN{printf "%.2f",s/n}')
  fmt_avg_ac=$(awk -v a="$avg_ac" -v b="$avg_ti" 'BEGIN{if(a+0>b+0){print "\\textbf{"a"x}"}else{print a"x"}}')
  fmt_avg_ti=$(awk -v a="$avg_ac" -v b="$avg_ti" 'BEGIN{if(b+0>a+0){print "\\textbf{"b"x}"}else{print b"x"}}')
  echo "  & \\textit{Average} & & & ${fmt_avg_ac} & & ${fmt_avg_ti} \\\\" >> "$tex_file"
  echo "\\midrule" >> "$tex_file"
}

_latex_rows "pdfbox"

# ─── class-load breakdown ────────────────────────────────────────────────────

_classload_row() {
  local mode="$1" op="$2"
  local safe="${op//:/-}"
  local logfile="$TMP/cl-${safe}-${mode}.log"
  local -a args; op_args "$op" args
  case "$mode" in
    no)
      "$JAVA_NO_BIN" -Xlog:class+load:file="$logfile" \
        -cp "$JAR" "$MAIN" "${args[@]}" >/dev/null 2>&1
      ;;
    aotcache)
      "$JAVA_AOTCACHE_BIN" -XX:AOTCache="single-iterjdk-${safe}.aot" -XX:+AOTClassLinking \
        -Xlog:class+load:file="$logfile" \
        -cp "$JAR" "$MAIN" "${args[@]}" >/dev/null 2>&1
      ;;
    tree-iter)
      "$JAVA_TREE_ITER_BIN" -XX:AOTCache="$TREE_ITER_AOT" -XX:+AOTClassLinking \
        -Xlog:class+load:file="$logfile" \
        -cp "$JAR" "$MAIN" "${args[@]}" >/dev/null 2>&1
      ;;
  esac
  printf "  %-16s | %-10s | %8s | %8s\n" "$op" "$mode" \
    "$(awk '/source: file:/{c++} END{print c+0}' "$logfile")" \
    "$(awk '/source: shared object/{c++} END{print c+0}' "$logfile")"
}

echo
log "Class-load source breakdown (aotcache uses same-workload cache)"
sep
printf "  %-16s | %-10s | %8s | %8s\n" "Operation" "Mode" "file:" "shared"
sep
for op in "${OPS[@]}"; do
  _classload_row no        "$op"
  _classload_row aotcache  "$op"
  _classload_row tree-iter "$op"
  sep
done

# ─── cache size table ────────────────────────────────────────────────────────

echo
log "Cache sizes"
sep
printf "  %-44s | %10s\n" "Cache" "Size"
sep
for op in "${OPS[@]}"; do
  safe="${op//:/-}"
  printf "  %-44s | %10s\n" "single-iterjdk-${safe}.aot" \
    "$(du -h "single-iterjdk-${safe}.aot" 2>/dev/null | awk '{print $1}' || echo n/a)"
done
for f in pdfbox/io/iter.aot pdfbox/fontbox/iter.aot pdfbox/pdfbox/iter.aot pdfbox/tools/iter.aot \
         pdfbox-deps/bc-java-util-workload/iter.aot \
         pdfbox-deps/bc-java-prov-workload/iter.aot \
         pdfbox-deps/bc-java-pkix-workload/iter.aot \
         pdfbox-deps/commons-logging-workload/iter.aot; do
  [[ -f "$f" ]] || continue
  printf "  %-44s | %10s\n" "$f" "$(du -h "$f" | awk '{print $1}')"
done
printf "  %-44s | %10s\n" "$TREE_ITER_AOT" "$(du -h "$TREE_ITER_AOT" | awk '{print $1}')"

echo
log "Done. LaTeX rows → $TMP/latex-rows-tree-iter.tex"
