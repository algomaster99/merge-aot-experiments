#!/bin/bash
set -euo pipefail

log()  { echo -e "\033[1;32m[$(date '+%H:%M:%S')] $*\033[0m"; }
sep()  { echo -e "\033[0;90m  $(printf '─%.0s' {1..60})\033[0m"; }
fail() { echo -e "\033[1;31mERROR: $*\033[0m" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

JAR="certificate-ripper/target/crip.jar"
TREECACHE_AOT="tree.aot"
WORK_DIR="workload-tmp"

RUNS="${RUNS:-30}"
JAVA_NO_BIN="${JAVA_NO_BIN:-java}"
JAVA_AOTCACHE_BIN="${JAVA_AOTCACHE_BIN:-java}"
JAVA_TREECACHE_BIN="${JAVA_TREECACHE_BIN:-java}"

OPS=(print-https export-pem-https print-smtps)
EXPORT_DIR="$SCRIPT_DIR/$WORK_DIR/exports"
mkdir -p "$EXPORT_DIR/pem" "$WORK_DIR"

[[ -f "$JAR" ]] || fail "$JAR not found"
for _op in "${OPS[@]}"; do
  [[ -f "single-${_op}.aot" ]] || fail "single-${_op}.aot not found — run ./create-single-aot.sh first"
done
[[ -f "$TREECACHE_AOT" ]] || fail "tree.aot not found — run ./orchestrate-combine.sh first"

_crip_args() {
  case "$1" in
    print-https)      echo "print --url https://github.com --resolve-ca false" ;;
    export-pem-https) echo "export pem --url https://github.com --resolve-ca false -d $EXPORT_DIR/pem" ;;
    print-smtps)      echo "print --url smtps://smtp.gmail.com:465 --resolve-ca false" ;;
  esac
}

log "Java binaries:"
printf "  no-AOT:    %s\n" "$JAVA_NO_BIN";       "$JAVA_NO_BIN"       -version 2>&1 | head -1
printf "  AOTCache:  %s\n" "$JAVA_AOTCACHE_BIN"; "$JAVA_AOTCACHE_BIN" -version 2>&1 | head -1
printf "  TreeCache: %s\n" "$JAVA_TREECACHE_BIN"; "$JAVA_TREECACHE_BIN" -version 2>&1 | head -1
echo

# ── timing helpers ────────────────────────────────────────────────────────────

ms() { date +%s%N | awk '{printf "%.1f", $1/1000000}'; }

declare -A _samples

_update() { _samples[$1]="${_samples[$1]:-} $2"; }

_mean() {
  local s="${_samples[$1]:-}"
  [[ -z "$s" ]] && { echo "n/a"; return; }
  printf "%s\n" $s | awk '{sum+=$1;n++} END{if(!n)print "n/a"; else printf "%.1f",sum/n}'
}

_stddev() {
  local s="${_samples[$1]:-}"
  [[ -z "$s" ]] && { echo "n/a"; return; }
  printf "%s\n" $s | awk '{sum+=$1;sumsq+=$1*$1;n++} END{if(n<2)print "n/a"; else printf "%.1f",sqrt((sumsq-sum*sum/n)/(n-1))}'
}

_measure() {
  local key="$1" op="$2" java_bin="$3"
  shift 3
  local errfile="$WORK_DIR/${key//|/-}.err"
  local t0 t1 rc=0
  read -ra args <<< "$(_crip_args "$op")"
  t0=$(ms)
  "$java_bin" "$@" -jar "$JAR" "${args[@]}" >/dev/null 2>"$errfile" || rc=$?
  t1=$(ms)
  if (( rc != 0 )); then
    echo "  WARN: key=$key exited $rc — see $errfile" >&2
    return
  fi
  _update "$key" "$(awk "BEGIN{printf \"%.1f\",$t1-$t0}")"
}

# ── main loop ─────────────────────────────────────────────────────────────────

log "Running $RUNS iterations × ${#OPS[@]} ops (cross-workload)"
sep

for run in $(seq 1 "$RUNS"); do
  printf "  run %2d/%d\n" "$run" "$RUNS"
  for op in "${OPS[@]}"; do
    _measure "${op}|no"        "$op" "$JAVA_NO_BIN"
    _measure "${op}|TreeCache" "$op" "$JAVA_TREECACHE_BIN" \
      -XX:AOTCache="$TREECACHE_AOT" -XX:+AOTClassLinking
  done
  for train_op in "${OPS[@]}"; do
    for test_op in "${OPS[@]}"; do
      [[ "$test_op" == "$train_op" ]] && continue
      _measure "${train_op}|${test_op}|aotcache" "$test_op" "$JAVA_AOTCACHE_BIN" \
        -XX:AOTCache="single-${train_op}.aot" -XX:+AOTClassLinking
    done
  done
done

# ── results ───────────────────────────────────────────────────────────────────

_test_mean_aotcache() {
  local test_op="$1" sum=0 n=0 train_op m
  for train_op in "${OPS[@]}"; do
    [[ "$train_op" == "$test_op" ]] && continue
    m=$(_mean "${train_op}|${test_op}|aotcache")
    [[ "$m" == "n/a" ]] && continue
    sum=$(awk "BEGIN{printf \"%.4f\",$sum+$m}")
    n=$(( n + 1 ))
  done
  [[ $n -eq 0 ]] && { echo "n/a"; return; }
  awk -v s="$sum" -v n="$n" 'BEGIN{printf "%.1f",s/n}'
}

_test_stddev_aotcache() {
  local test_op="$1" all="" train_op
  for train_op in "${OPS[@]}"; do
    [[ "$train_op" == "$test_op" ]] && continue
    all="$all ${_samples[${train_op}|${test_op}|aotcache]:-}"
  done
  printf "%s\n" $all | awk '{sum+=$1;sumsq+=$1*$1;n++} END{if(n<2)print "n/a"; else printf "%.1f",sqrt((sumsq-sum*sum/n)/(n-1))}'
}

echo
log "Per-workload timing over $RUNS runs (ms) — AOTCache uses caches trained on other ops"
sep
printf "  %-20s | %18s | %20s %12s | %20s %12s\n" \
  "Workload" "no (mean±SD)" "aotcache (mean±SD)" "su-aotcache" "TreeCache (mean±SD)" "su-TreeCache"
sep
for op in "${OPS[@]}"; do
  m_no=$(_mean "${op}|no")
  m_mono=$(_test_mean_aotcache "$op")
  m_tree=$(_mean "${op}|TreeCache")
  sd_no=$(_stddev "${op}|no")
  sd_mono=$(_test_stddev_aotcache "$op")
  sd_tree=$(_stddev "${op}|TreeCache")
  su_mono=$(awk -v b="$m_no" -v a="$m_mono" 'BEGIN{if(a+0==0){print "n/a"}else{printf "%.2fx",b/a}}')
  su_tree=$(awk -v b="$m_no" -v a="$m_tree" 'BEGIN{if(a+0==0){print "n/a"}else{printf "%.2fx",b/a}}')
  printf "  %-20s | %18s | %20s %12s | %20s %12s\n" \
    "$op" "${m_no}±${sd_no}" "${m_mono}±${sd_mono}" "$su_mono" "${m_tree}±${sd_tree}" "$su_tree"
done

# ── LaTeX rows ────────────────────────────────────────────────────────────────

_print_latex_rows() {
  local project="$1" n="${#OPS[@]}" tex_file="$WORK_DIR/latex-rows.tex"
  local sum_su_mono=0 sum_su_tree=0 cnt_mono=0 cnt_tree=0
  echo "\\multirow{$(( n + 1 ))}{*}{${project}}" > "$tex_file"
  for op in "${OPS[@]}"; do
    local m_no m_mono m_tree sd_no sd_mono sd_tree su_mono su_tree fmt_mono fmt_tree
    m_no=$(_mean "${op}|no");          sd_no=$(_stddev "${op}|no")
    m_mono=$(_test_mean_aotcache "$op"); sd_mono=$(_test_stddev_aotcache "$op")
    m_tree=$(_mean "${op}|TreeCache"); sd_tree=$(_stddev "${op}|TreeCache")
    su_mono=$(awk -v b="$m_no" -v a="$m_mono" 'BEGIN{if(a+0==0){print "n/a"}else{printf "%.2f",b/a}}')
    su_tree=$(awk -v b="$m_no" -v a="$m_tree" 'BEGIN{if(a+0==0){print "n/a"}else{printf "%.2f",b/a}}')
    if [[ "$su_mono" != "n/a" ]]; then
      sum_su_mono=$(awk "BEGIN{printf \"%.4f\",$sum_su_mono+$su_mono}"); cnt_mono=$(( cnt_mono+1 ))
    fi
    if [[ "$su_tree" != "n/a" ]]; then
      sum_su_tree=$(awk "BEGIN{printf \"%.4f\",$sum_su_tree+$su_tree}"); cnt_tree=$(( cnt_tree+1 ))
    fi
    fmt_mono=$(awk -v a="$su_mono" -v b="$su_tree" 'BEGIN{if(a+0>b+0) print "\\textbf{"a"x}"; else print a"x"}')
    fmt_tree=$(awk -v a="$su_mono" -v b="$su_tree" 'BEGIN{if(b+0>a+0) print "\\textbf{"b"x}"; else print b"x"}')
    echo "  & ${op} & \$${m_no} \pm ${sd_no}\$ & \$${m_mono} \pm ${sd_mono}\$ & ${fmt_mono} & \$${m_tree} \pm ${sd_tree}\$ & ${fmt_tree} \\\\" >> "$tex_file"
  done
  local avg_mono avg_tree fmt_avg_mono fmt_avg_tree
  avg_mono=$(awk -v s="$sum_su_mono" -v c="$cnt_mono" 'BEGIN{if(c==0)print "n/a"; else printf "%.2f",s/c}')
  avg_tree=$(awk -v s="$sum_su_tree"  -v c="$cnt_tree"  'BEGIN{if(c==0)print "n/a"; else printf "%.2f",s/c}')
  fmt_avg_mono=$(awk -v a="$avg_mono" -v b="$avg_tree" 'BEGIN{if(a+0>b+0) print "\\textbf{"a"x}"; else print a"x"}')
  fmt_avg_tree=$(awk -v a="$avg_mono" -v b="$avg_tree" 'BEGIN{if(b+0>a+0) print "\\textbf{"b"x}"; else print b"x"}')
  echo "  & \\textit{Average} & & & ${fmt_avg_mono} & & ${fmt_avg_tree} \\\\" >> "$tex_file"
  echo "\\midrule" >> "$tex_file"
}

_print_latex_rows "certificate-ripper"

# ── class-load breakdown ──────────────────────────────────────────────────────

_classload_row() {
  local op="$1" mode="$2"
  local logfile="$WORK_DIR/cl-${op}-${mode}.log"
  local rc=0
  read -ra args <<< "$(_crip_args "$op")"
  case "$mode" in
    no)
      "$JAVA_NO_BIN" \
        -Xlog:class+load:file="$logfile" \
        -jar "$JAR" "${args[@]}" >/dev/null 2>&1 || rc=$? ;;
    AOTCache)
      "$JAVA_AOTCACHE_BIN" \
        -XX:AOTCache="single-${op}.aot" -XX:+AOTClassLinking \
        -Xlog:class+load:file="$logfile" \
        -jar "$JAR" "${args[@]}" >/dev/null 2>&1 || rc=$? ;;
    TreeCache)
      "$JAVA_TREECACHE_BIN" \
        -XX:AOTCache="$TREECACHE_AOT" -XX:+AOTClassLinking \
        -Xlog:class+load:file="$logfile" \
        -jar "$JAR" "${args[@]}" >/dev/null 2>&1 || rc=$? ;;
  esac
  if (( rc != 0 )); then
    printf "  %-22s | %-9s | %8s | %8s\n" "$op" "$mode" "n/a" "n/a"
    return
  fi
  printf "  %-22s | %-9s | %8s | %8s\n" "$op" "$mode" \
    "$(awk '/source: file:/{c++} END{print c+0}' "$logfile")" \
    "$(awk '/source: shared objects/{c++} END{print c+0}' "$logfile")"
}

echo
log "Class-load source breakdown (AOTCache uses same-workload cache)"
sep
printf "  %-22s | %-9s | %8s | %8s\n" "Operation" "Mode" "file:" "shared"
sep
for op in "${OPS[@]}"; do
  for mode in no AOTCache TreeCache; do
    _classload_row "$op" "$mode"
  done
  sep
done
