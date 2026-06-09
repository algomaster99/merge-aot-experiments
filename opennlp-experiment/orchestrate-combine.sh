#!/bin/bash
set -euo pipefail

log()  { echo -e "\033[1;32m[$(date '+%H:%M:%S')] $*\033[0m"; }
fail() { echo -e "\033[1;31mERROR: $*\033[0m" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

log "Java version:"
java -version

OPENNLP_DIR="opennlp"
MORFOLOGIK_DIR="opennlp-deps/morfologik"
DEPS_DIR="${SCRIPT_DIR}/combine-deps"

OPENNLP_MODULES=(
  "opennlp-tools"
  "opennlp-tools-models"
  "opennlp-uima"
  "opennlp-morfologik-addon"
)

# morfologik submodules that have tests (morfologik-fsa has none)
MORFOLOGIK_MODULES=(
  "morfologik-fsa-builders"
  "morfologik-stemming"
  "morfologik-tools"
)

CACHE_PATHS=()
CLASSES_PATHS=()
for mod in "${OPENNLP_MODULES[@]}"; do
  CACHE_PATHS+=("$OPENNLP_DIR/$mod/cache.aot")
  CLASSES_PATHS+=("$OPENNLP_DIR/$mod/target/classes")
done
for mod in "${MORFOLOGIK_MODULES[@]}"; do
  CACHE_PATHS+=("$MORFOLOGIK_DIR/$mod/cache.aot")
  CLASSES_PATHS+=("$MORFOLOGIK_DIR/$mod/target/classes")
done

for path in "${CACHE_PATHS[@]}"; do
  [[ -f "$path" ]] || fail "Missing cache: $path — run: cd $OPENNLP_DIR/$mod && mvn test -Ptree-merge"
done

# Recompile if target/classes was cleaned up after the test run
NEED_COMPILE=false
for path in "${CLASSES_PATHS[@]}"; do
  [[ -d "$path" ]] || { NEED_COMPILE=true; break; }
done

if $NEED_COMPILE; then
  log "target/classes missing — recompiling (no tests)..."
  (cd "$OPENNLP_DIR" && mvn -q -B compile -pl "$(IFS=,; echo "${OPENNLP_MODULES[*]}")" --also-make)
  (cd "$MORFOLOGIK_DIR" && mvn -q -B compile -pl "$(IFS=,; echo "${MORFOLOGIK_MODULES[*]}")" --also-make)
fi

for path in "${CLASSES_PATHS[@]}"; do
  [[ -d "$path" ]] || fail "Compile failed — still missing $path"
done

log "Copying external dependency JARs to $DEPS_DIR..."
mkdir -p "$DEPS_DIR"
(cd "$OPENNLP_DIR" && mvn -q -B dependency:copy-dependencies \
  -DoutputDirectory="$DEPS_DIR" \
  -DincludeScope=compile \
  -DexcludeGroupIds=org.apache.opennlp \
  -pl "$(IFS=,; echo "${OPENNLP_MODULES[*]}")" 2>/dev/null)
(cd "$MORFOLOGIK_DIR" && mvn -q -B dependency:copy-dependencies \
  -DoutputDirectory="$DEPS_DIR" \
  -DincludeScope=compile \
  -DexcludeGroupIds=org.carrot2 \
  -pl "$(IFS=,; echo "${MORFOLOGIK_MODULES[*]}")" 2>/dev/null)

DEP_CP="$(find "$DEPS_DIR" -name '*.jar' | sort | tr '\n' ':' | sed 's/:$//')"
CLASSES_CP="$(IFS=:; echo "${CLASSES_PATHS[*]}")"
CLASSPATH="${CLASSES_CP}:${DEP_CP}"

BASE_AOT="${CACHE_PATHS[0]}"
MERGE_INPUTS="$(IFS=:; echo "${CACHE_PATHS[*]}")"
OUTPUT_AOT="tree.aot"

rm -f "$OUTPUT_AOT"

log "Merging ${#CACHE_PATHS[@]} caches → $OUTPUT_AOT"
java \
  -Xlog:aot=info \
  -Xlog:aot+map=trace,aot+map+oops=trace,aot=warning:file=aot.map:none:filesize=0 \
  --add-opens java.base/java.io=ALL-UNNAMED \
  --add-opens java.base/java.lang=ALL-UNNAMED \
  --add-opens java.base/java.lang.reflect=ALL-UNNAMED \
  --add-opens java.base/java.util=ALL-UNNAMED \
  --add-opens java.base/jdk.internal.loader=ALL-UNNAMED \
  -XX:AOTMode=merge \
  -XX:AOTCache="$BASE_AOT" \
  -XX:AOTMergeInputs="$MERGE_INPUTS" \
  -XX:AOTCacheOutput="$OUTPUT_AOT" \
  -cp "$CLASSPATH" \
  -version

[[ -f "$OUTPUT_AOT" ]] || fail "tree.aot was not created"
log "$OUTPUT_AOT created ($(du -sh "$OUTPUT_AOT" | cut -f1))"
