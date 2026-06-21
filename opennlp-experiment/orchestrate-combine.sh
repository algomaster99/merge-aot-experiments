#!/bin/bash
set -euo pipefail

log()  { echo -e "\033[1;32m[$(date '+%H:%M:%S')] $*\033[0m"; }
fail() { echo -e "\033[1;31mERROR: $*\033[0m" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

log "Java version:"
java -version

LIB_DIR="opennlp-cli-lib"
MODELS_DIR="models"
LOG4J_CFG="opennlp/opennlp-distr/src/main/resources/log4j2.xml"

[[ -d "$LIB_DIR" ]]    || fail "$LIB_DIR not found — run CI setup step first"
[[ -d "$MODELS_DIR" ]] || fail "$MODELS_DIR not found"

OPENNLP_MODULES=(
  "opennlp/opennlp-tools"
  "opennlp/opennlp-morfologik-addon"
)

MORFOLOGIK_MODULES=(
  "opennlp-deps/morfologik/morfologik-fsa-builders"
  "opennlp-deps/morfologik/morfologik-stemming"
  "opennlp-deps/morfologik/morfologik-tools"
)

CACHE_PATHS=()
for mod in "${OPENNLP_MODULES[@]}" "${MORFOLOGIK_MODULES[@]}"; do
  CACHE_PATHS+=("$mod/cache.aot")
done

for path in "${CACHE_PATHS[@]}"; do
  [[ -f "$path" ]] || fail "Missing cache: $path"
done

CP="$(ls "$LIB_DIR"/*.jar | tr '\n' ':')"
LOG4J="-Dlog4j.configurationFile=${LOG4J_CFG}"
OPENS=(
  --add-opens java.base/java.io=ALL-UNNAMED
  --add-opens java.base/java.lang=ALL-UNNAMED
  --add-opens java.base/java.lang.reflect=ALL-UNNAMED
  --add-opens java.base/java.util=ALL-UNNAMED
  --add-opens java.base/jdk.internal.loader=ALL-UNNAMED
)

# ── per-op CLI helpers (must match workload-timed.sh) ────────────────────────

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

# ── record CLI workload caches with current JDK (covers cmdline.* + log4j) ──
# The tree-merge profile excludes **/cmdline/** tests, so CLI classes and log4j
# are absent from all 5 component caches. Recording here ensures they're merged
# into tree.aot.

OPS=(sentdetect tokenize postag)
CLI_CACHES=()

for op in "${OPS[@]}"; do
  cli_aot="cli-${op}.aot"
  cli_conf="cli-${op}.aotconf"
  if [[ -f "$cli_aot" ]]; then
    log "$cli_aot already exists, reusing"
  else
    log "Recording CLI cache for $op (step 1: AOTConfiguration)"
    rm -f "$cli_conf"
    _input_text "$op" | java "$LOG4J" "${OPENS[@]}" \
      -XX:AOTMode=record -XX:AOTConfiguration="$cli_conf" \
      -XX:+AOTClassLinking \
      -cp "$CP" opennlp.tools.cmdline.CLI "$(_cli_subcmd "$op")" "$(_cli_model "$op")" >/dev/null
    [[ -f "$cli_conf" ]] || fail "AOTConfiguration not produced for $op"

    log "Recording CLI cache for $op (step 2: AOTCache)"
    java "${OPENS[@]}" \
      -XX:AOTMode=create -XX:AOTConfiguration="$cli_conf" \
      -XX:AOTCache="$cli_aot" \
      -XX:+AOTClassLinking \
      -cp "$CP"
    [[ -f "$cli_aot" ]] || fail "$cli_aot not created"
    log "$cli_aot created ($(du -sh "$cli_aot" | cut -f1))"
  fi
  CLI_CACHES+=("$cli_aot")
done

# ── merge all caches → tree.aot ───────────────────────────────────────────────

ALL_CACHES=("${CACHE_PATHS[@]}" "${CLI_CACHES[@]}")
BASE_AOT="${ALL_CACHES[0]}"
MERGE_INPUTS="$(IFS=:; echo "${ALL_CACHES[*]}")"
OUTPUT_AOT="tree.aot"

rm -f "$OUTPUT_AOT"

log "Merging ${#ALL_CACHES[@]} caches → $OUTPUT_AOT"
java \
  -Xlog:aot=info \
  -Xlog:aot+map=trace,aot+map+oops=trace,aot=warning:file=aot.map:none:filesize=0 \
  "${OPENS[@]}" \
  -XX:AOTMode=merge \
  -XX:AOTCache="$BASE_AOT" \
  -XX:AOTMergeInputs="$MERGE_INPUTS" \
  -XX:AOTCacheOutput="$OUTPUT_AOT" \
  -cp "$CP" \
  -version

[[ -f "$OUTPUT_AOT" ]] || fail "tree.aot was not created"
log "$OUTPUT_AOT created ($(du -sh "$OUTPUT_AOT" | cut -f1))"
