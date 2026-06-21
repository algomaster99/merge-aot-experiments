#!/bin/bash
set -euo pipefail

log()  { echo -e "\033[1;32m[$(date '+%H:%M:%S')] $*\033[0m"; }
sep()  { echo -e "\033[0;90m  $(printf '─%.0s' {1..60})\033[0m"; }
fail() { echo -e "\033[1;31mERROR: $*\033[0m" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

LIB_DIR="opennlp-cli-lib"
MODELS_DIR="models"
LOG4J_CFG="opennlp/opennlp-distr/src/main/resources/log4j2.xml"
TREECACHE_AOT="tree.aot"
WORK_DIR="workload-tmp"

RUNS="${RUNS:-30}"
JAVA_NO_BIN="${JAVA_NO_BIN:-java}"
JAVA_AOTCACHE_BIN="${JAVA_AOTCACHE_BIN:-java}"
JAVA_TREECACHE_BIN="${JAVA_TREECACHE_BIN:-java}"

OPS=(sentdetect tokenize postag)

[[ -d "$LIB_DIR" ]]  || fail "$LIB_DIR not found"
[[ -d "$MODELS_DIR" ]] || fail "$MODELS_DIR not found"
for _op in "${OPS[@]}"; do
  [[ -f "single-${_op}.aot" ]] || fail "single-${_op}.aot not found — run ./create-single-aot.sh first"
done
[[ -f "$TREECACHE_AOT" ]] || fail "tree.aot not found — run ./orchestrate-combine.sh first"

mkdir -p "$WORK_DIR"

CP="$(ls "$LIB_DIR"/*.jar | tr '\n' ':')"
LOG4J="-Dlog4j.configurationFile=${LOG4J_CFG}"
OPENS=(
  --add-opens java.base/java.io=ALL-UNNAMED
  --add-opens java.base/java.lang=ALL-UNNAMED
  --add-opens java.base/java.lang.reflect=ALL-UNNAMED
  --add-opens java.base/java.util=ALL-UNNAMED
  --add-opens java.base/jdk.internal.loader=ALL-UNNAMED
)

log "Java binaries:"
printf "  no-AOT:    %s\n" "$JAVA_NO_BIN";    "$JAVA_NO_BIN"    -version 2>&1 | head -1
printf "  AOTCache:  %s\n" "$JAVA_AOTCACHE_BIN"; "$JAVA_AOTCACHE_BIN" -version 2>&1 | head -1
printf "  TreeCache: %s\n" "$JAVA_TREECACHE_BIN"; "$JAVA_TREECACHE_BIN" -version 2>&1 | head -1
echo

# ─── per-op CLI helpers ───────────────────────────────────────────────────────

_cli_subcmd() {
  case "$1" in
    sentdetect) echo "SentenceDetector" ;;
    tokenize)   echo "TokenizerME" ;;
    postag)     echo "POSTagger" ;;
  esac
}

_cli_model() {
  case "$1" in
    sentdetect) echo "$MODELS_DIR/opennlp-en-ud-ewt-sentence-1.3-2.5.4.bin" ;;
    tokenize)   echo "$MODELS_DIR/opennlp-en-ud-ewt-tokens-1.3-2.5.4.bin" ;;
    postag)     echo "$MODELS_DIR/opennlp-en-ud-ewt-pos-1.3-2.5.4.bin" ;;
  esac
}

_input_text() {
  case "$1" in
    sentdetect) echo "Pierre Vinken, 61 years old, will join the board as a nonexecutive director Nov. 29. Mr. Vinken is chairman of Elsevier N.V., the Dutch publishing group. No price was given." ;;
    tokenize)   echo "Pierre Vinken, 61 years old, will join the board as a nonexecutive director Nov. 29." ;;
    postag)     echo "Pierre Vinken , 61 years old , will join the board as a nonexecutive director Nov. 29 ." ;;
  esac
}

# Invoke the CLI for a given op, with extra java args passed after the op arg.
# Usage: _invoke op java_bin [extra_java_args...]
_invoke() {
  local op="$1" java_bin="$2"
  shift 2
  _input_text "$op" | "$java_bin" "$@" \
    "$LOG4J" "${OPENS[@]}" -cp "$CP" \
    opennlp.tools.cmdline.CLI "$(_cli_subcmd "$op")" "$(_cli_model "$op")"
}

# ─── timing helpers ───────────────────────────────────────────────────────────

ms() { date +%s%N | awk '{printf "%.1f", $1/1000000}'; }

declare -A _samples

_update() {
  local key="$1" v="$2"
  _samples[$key]="${_samples[$key]:-} $v"
}

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

# ─── run helpers ─────────────────────────────────────────────────────────────

_measure() {
  local key="$1" op="$2" java_bin="$3"
  shift 3
  local errfile="$WORK_DIR/${key//|/-}.err"
  local t0 t1 rc=0
  t0=$(ms)
  _invoke "$op" "$java_bin" "$@" >/dev/null 2>"$errfile" || rc=$?
  t1=$(ms)
  if (( rc != 0 )); then
    echo "  WARN: key=$key exited $rc — see $errfile" >&2
    return
  fi
  _update "$key" "$(awk "BEGIN{printf \"%.1f\",$t1-$t0}")"
}

# ─── main loop ───────────────────────────────────────────────────────────────

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

# ─── results ─────────────────────────────────────────────────────────────────

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
  local test_op="$1" all=""  train_op
  for train_op in "${OPS[@]}"; do
    [[ "$train_op" == "$test_op" ]] && continue
    all="$all ${_samples[${train_op}|${test_op}|aotcache]:-}"
  done
  printf "%s\n" $all | awk '{sum+=$1;sumsq+=$1*$1;n++} END{if(n<2)print "n/a"; else printf "%.1f",sqrt((sumsq-sum*sum/n)/(n-1))}'
}

echo
log "Per-workload timing over $RUNS runs (ms) — AOTCache uses caches trained on other ops"
sep
printf "  %-12s | %18s | %20s %8s | %20s %8s\n" \
  "Workload" "no (mean±SD)" "aotcache (mean±SD)" "su-aotcache" "TreeCache (mean±SD)" "su-TreeCache"
sep
for op in "${OPS[@]}"; do
  m_no=$(_mean "${op}|no")
  m_mono=$(_test_mean_aotcache "$op")
  m_tree=$(_mean "${op}|TreeCache")
  sd_no=$(_stddev "${op}|no")
  sd_mono=$(_test_stddev_aotcache "$op")
  sd_tree=$(_stddev "${op}|TreeCache")
  su_mono=$(awk  -v b="$m_no" -v a="$m_mono" 'BEGIN{if(a+0==0){print "n/a"}else{printf "%.2fx",b/a}}')
  su_tree=$(awk  -v b="$m_no" -v a="$m_tree" 'BEGIN{if(a+0==0){print "n/a"}else{printf "%.2fx",b/a}}')
  printf "  %-12s | %18s | %20s %8s | %20s %8s\n" \
    "$op" "${m_no}±${sd_no}" "${m_mono}±${sd_mono}" "$su_mono" "${m_tree}±${sd_tree}" "$su_tree"
done

# ─── LaTeX rows ──────────────────────────────────────────────────────────────

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

_print_latex_rows "opennlp"

# ─── class-load breakdown ─────────────────────────────────────────────────────

_classload_row() {
  local op="$1" mode="$2"
  local logfile="$WORK_DIR/cl-${op}-${mode}.log"
  local rc=0
  case "$mode" in
    no)
      _invoke "$op" "$JAVA_NO_BIN" \
        -Xlog:class+load:file="$logfile" >/dev/null 2>&1 || rc=$? ;;
    AOTCache)
      _invoke "$op" "$JAVA_AOTCACHE_BIN" \
        -XX:AOTCache="single-${op}.aot" -XX:+AOTClassLinking \
        -Xlog:class+load:file="$logfile" >/dev/null 2>&1 || rc=$? ;;
    TreeCache)
      _invoke "$op" "$JAVA_TREECACHE_BIN" \
        -XX:AOTCache="$TREECACHE_AOT" -XX:+AOTClassLinking \
        -Xlog:class+load:file="$logfile" >/dev/null 2>&1 || rc=$? ;;
  esac
  if (( rc != 0 )); then
    printf "  %-12s | %-9s | %8s | %8s\n" "$op" "$mode" "n/a" "n/a"
    return
  fi
  printf "  %-12s | %-9s | %8s | %8s\n" "$op" "$mode" \
    "$(awk '/source: file:/{c++} END{print c+0}' "$logfile")" \
    "$(awk '/source: shared object/{c++} END{print c+0}' "$logfile")"
}

echo
log "Class-load source breakdown (AOTCache uses same-workload cache)"
sep
printf "  %-12s | %-9s | %8s | %8s\n" "Operation" "Mode" "file:" "shared"
sep
for op in "${OPS[@]}"; do
  for mode in no AOTCache TreeCache; do
    _classload_row "$op" "$mode"
  done
  sep
done
