#!/bin/bash
set -euo pipefail

log()  { echo -e "\033[1;32m[$(date '+%H:%M:%S')] $*\033[0m"; }
info() { echo -e "\033[1;34m  >> $*\033[0m"; }
sep()  { echo -e "\033[0;90m  $(printf '─%.0s' {1..60})\033[0m"; }

JAR="pdfbox/app/target/pdfbox-app-3.0.7.jar"
MAIN="org.apache.pdfbox.tools.PDFBox"
PDF="pdfbox/test.pdf"
BASE="test"
TMP="workload-tmp"
AOT="tree.aot"
SINGLE_AOT="single.aot"

CP="pdfbox/app/target/pdfbox-app-3.0.7.jar:pdfbox-deps/pdfbox-jbig2/target/classes/:pdfbox-deps/apache-commons-io/target/classes/"

# If operations sometimes "hang", this prevents infinite waits and points at the op.
# Set OP_TIMEOUT_SEC higher if your workload is slow.
OP_TIMEOUT_SEC="${OP_TIMEOUT_SEC:-900}"

if [ ! -f "$AOT" ]; then
  echo "tree.aot not found — run orchestrate-combine-*.sh first" >&2
  exit 1
fi

if [ ! -f "$SINGLE_AOT" ]; then
  echo "single.aot not found" >&2
  exit 1
fi

log "Java version:"
java -version
echo

mkdir -p "$TMP"

# ---------------------------------------------------------------------------
# Timing helpers
# ---------------------------------------------------------------------------
ms() { echo $(( $(date +%s%N) / 1000000 )); }

measure_ms() {
  # Prints integer milliseconds, or exits on failure/timeout.
  # $1=op $2=mode $3+=command
  local op="$1"; local mode="$2"; shift 2
  local start; start=$(ms)
  local err_file="$TMP/${RUN_IDX:-0}-${op//:/}-${mode}.stderr.log"

  # Use `timeout` when available to prevent indefinite hangs.
  if command -v timeout >/dev/null 2>&1; then
    timeout "${OP_TIMEOUT_SEC}s" "$@" >/dev/null 2>"$err_file"
    local rc=$?
  else
    "$@" >/dev/null 2>"$err_file"
    local rc=$?
  fi

  if [ "$rc" -ne 0 ]; then
    echo "ERROR: timed out/failed (op=$op mode=$mode rc=$rc OP_TIMEOUT_SEC=$OP_TIMEOUT_SEC) see $err_file" >&2
    return "$rc"
  fi

  echo $(( $(ms) - start ))
}

declare -A minv maxv cnt samples

update_stats() {
  local key="$1"; local sample_ms="$2"
  cnt[$key]=$(( ${cnt[$key]:-0} + 1 ))
  samples[$key]="${samples[$key]:-} ${sample_ms}"

  if [ -z "${minv[$key]:-}" ] || (( sample_ms < minv[$key] )); then
    minv[$key]="$sample_ms"
  fi
  if [ -z "${maxv[$key]:-}" ] || (( sample_ms > maxv[$key] )); then
    maxv[$key]="$sample_ms"
  fi
}

median_for_key() {
  local key="$1"
  local n="${cnt[$key]:-0}"
  local values median

  if [ "$n" -eq 0 ]; then
    echo "n/a"
    return
  fi

  values="${samples[$key]# }"
  median="$(
    printf "%s\n" $values | sort -n | awk '
      { a[++n] = $1 }
      END {
        if (n % 2 == 1) {
          printf "%.1f", a[(n + 1) / 2]
        } else {
          printf "%.1f", (a[n / 2] + a[(n / 2) + 1]) / 2
        }
      }
    '
  )"
  echo "$median"
}

print_summary() {
  local runs="$1"

  # Operation labels (must match the workload below).
  local -a ops=("encrypt" "decrypt" "export:text" "export:images" "render" "fromtext" "split" "merge" "decode" "overlay")

  echo
  log "Aggregated timing over ${runs} runs (ms)"
  sep

  printf "  %-16s | %10s %6s %6s | %10s %6s %6s | %10s %6s %6s\n" \
    "Operation" "no-med" "no-min" "no-max" "tree-med" "tree-min" "tree-max" "single-med" "single-min" "single-max"

  local op key n
  local med min max med_tree min_tree max_tree med_single min_single max_single

  for op in "${ops[@]}"; do
    key="${op}|no"
    n="${cnt[$key]:-0}"
    if [ "$n" -eq 0 ]; then
      printf "  %-16s | %-10s %-6s %-6s | %-10s %-6s %-6s | %-10s %-6s %-6s\n" \
        "$op" "n/a" "n/a" "n/a" "n/a" "n/a" "n/a" "n/a" "n/a" "n/a"
      continue
    fi

    med="$(median_for_key "$key")"
    min="${minv[$key]}"
    max="${maxv[$key]}"

    key="${op}|tree"
    med_tree="$(median_for_key "$key")"
    min_tree="${minv[$key]}"
    max_tree="${maxv[$key]}"

    key="${op}|single"
    med_single="$(median_for_key "$key")"
    min_single="${minv[$key]}"
    max_single="${maxv[$key]}"

    printf "  %-16s | %10s %6s %6s | %10s %6s %6s | %10s %6s %6s\n" \
      "$op" "${med}" "${min}" "${max}" "${med_tree}" "${min_tree}" "${max_tree}" "${med_single}" "${min_single}" "${max_single}"
  done
}

run_op() {
  # $1 = label, rest = java args (without -XX:AOTCache)
  local label="$1"; shift
  local -a cmd_no cmd_tree cmd_single
  local ms_no ms_tree ms_single

  cmd_no=(java -cp "$CP" "$MAIN" "$@")
  cmd_tree=(java -XX:AOTCache="$AOT" -cp "$CP" "$MAIN" "$@")
  cmd_single=(java -XX:AOTCache="$SINGLE_AOT" -cp "$CP" "$MAIN" "$@")

  ms_no="$(measure_ms "$label" "no" "${cmd_no[@]}")"
  update_stats "${label}|no" "$ms_no"
  if [ "${PRINT_PER_RUN:-0}" = "1" ]; then
    printf "  \033[1;33m%-30s\033[0m \033[0;90mno AOT  \033[0m \033[1;37m%dms\033[0m\n" "$label" "$ms_no"
  fi

  ms_tree="$(measure_ms "$label" "tree" "${cmd_tree[@]}")"
  update_stats "${label}|tree" "$ms_tree"
  if [ "${PRINT_PER_RUN:-0}" = "1" ]; then
    printf "  \033[1;33m%-30s\033[0m \033[0;90mAOT tree  \033[0m \033[1;37m%dms\033[0m\n" "$label" "$ms_tree"
  fi

  ms_single="$(measure_ms "$label" "single" "${cmd_single[@]}")"
  update_stats "${label}|single" "$ms_single"
  if [ "${PRINT_PER_RUN:-0}" = "1" ]; then
    printf "  \033[1;33m%-30s\033[0m \033[0;90mAOT single\033[0m \033[1;37m%dms\033[0m\n" "$label" "$ms_single"
  fi
}

# ---------------------------------------------------------------------------
# Workload
# ---------------------------------------------------------------------------
log "PDFBox workload — comparing no-AOT vs single.aot vs tree.aot"
sep

RUNS="${RUNS:-10}"

# Set PRINT_PER_RUN=1 if you still want per-op timings printed for each run.
PRINT_PER_RUN="${PRINT_PER_RUN:-0}"

if ! [[ "$RUNS" =~ ^[0-9]+$ ]] || [ "$RUNS" -lt 1 ]; then
  echo "RUNS must be an integer >= 1 (got: $RUNS)" >&2
  exit 1
fi

workload_once() {
  run_op "encrypt" \
    encrypt -O 123 -U 123 --input "$PDF" --output "$TMP/$BASE-locked.pdf"

  run_op "decrypt" \
    decrypt -password 123 --input "$TMP/$BASE-locked.pdf" --output "$TMP/$BASE-unlocked.pdf"

  run_op "export:text" \
    export:text --input "$PDF" --output "$TMP/$BASE-text.txt"

  run_op "export:images" \
    export:images --input "$PDF"

  run_op "render" \
    render --input "$PDF"

  run_op "fromtext" \
    fromtext --input "$TMP/$BASE-text.txt" \
             --output "$TMP/$BASE-from-text.pdf" \
             -standardFont Times-Roman

  run_op "split" \
    split --input "$PDF" -split 3 -outputPrefix "$TMP/split-$BASE"

  run_op "merge" \
    merge --input "$TMP/split-$BASE-1.pdf" \
          --output "$TMP/merged-$BASE.pdf"

  run_op "decode" \
    decode "$PDF" "$TMP/$BASE-decoded.pdf"

  run_op "overlay" \
    overlay -default "$PDF" --input "$PDF" --output "$TMP/$BASE-overlay.pdf"
}

log "Running workload ${RUNS} times (aggregate)"
sep
for i in $(seq 1 "$RUNS"); do
  if [ "$PRINT_PER_RUN" = "1" ]; then
    log "Run $i/$RUNS"
  fi
  RUN_IDX="$i"
  workload_once
done

print_summary "$RUNS"

echo
log "Done."
