#!/bin/bash
# Records one single-{op}.aot per workload using the OpenNLP CLI directly.
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
OPS=(sentdetect tokenize postag)

[[ -d "$LIB_DIR" ]]  || fail "$LIB_DIR not found — run CI setup step or: mvn dependency:copy-dependencies -f opennlp/opennlp-distr/pom.xml -DoutputDirectory=$LIB_DIR -Dscope=runtime"
[[ -d "$MODELS_DIR" ]] || fail "$MODELS_DIR not found — extract .bin files from model JARs first"
for op in "${OPS[@]}"; do
  [[ -f "single-${op}.aot" ]] && { log "single-${op}.aot already exists, skipping."; }
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

# Input text and model for each workload.
cli_args() {
  case "$1" in
    sentdetect) echo "SentenceDetector $MODELS_DIR/opennlp-en-ud-ewt-sentence-1.3-2.5.4.bin" ;;
    tokenize)   echo "TokenizerME $MODELS_DIR/opennlp-en-ud-ewt-tokens-1.3-2.5.4.bin" ;;
    postag)     echo "POSTagger $MODELS_DIR/opennlp-en-ud-ewt-pos-1.3-2.5.4.bin" ;;
  esac
}

input_text() {
  case "$1" in
    sentdetect) echo "Pierre Vinken, 61 years old, will join the board as a nonexecutive director Nov. 29. Mr. Vinken is chairman of Elsevier N.V., the Dutch publishing group. No price was given." ;;
    tokenize)   echo "Pierre Vinken, 61 years old, will join the board as a nonexecutive director Nov. 29." ;;
    postag)     echo "Pierre Vinken , 61 years old , will join the board as a nonexecutive director Nov. 29 ." ;;
  esac
}

for op in "${OPS[@]}"; do
  aot="single-${op}.aot"
  conf="single-${op}.aotconf"
  [[ -f "$aot" ]] && continue

  log "Recording $aot"
  rm -f "$conf"
  read -ra args <<< "$(cli_args "$op")"
  input_text "$op" | java "$LOG4J" "${OPENS[@]}" \
    -XX:AOTMode=record -XX:AOTConfiguration="$conf" \
    -XX:+AOTClassLinking \
    -cp "$CP" opennlp.tools.cmdline.CLI "${args[@]}" >/dev/null

  [[ -f "$conf" ]] || fail "AOTConfiguration not produced for $op"

  java "$LOG4J" "${OPENS[@]}" \
    -XX:AOTMode=create -XX:AOTConfiguration="$conf" \
    -XX:AOTCache="$aot" \
    -XX:+AOTClassLinking \
    -cp "$CP"

  [[ -f "$aot" ]] || fail "$aot was not created"
  log "$aot created ($(du -sh "$aot" | cut -f1))"
done
