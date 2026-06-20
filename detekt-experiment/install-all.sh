#!/bin/bash
# Build detekt source modules (install to .m2), compile benchmark, generate ext-deps-cp.txt.
# Run once before using workload-timed.sh or create-single-aot.sh.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DETEKT="$SCRIPT_DIR/detekt"

log() { echo -e "\033[1;32m[$(date '+%H:%M:%S')] $*\033[0m"; }
fail() { echo -e "\033[1;31mERROR: $*\033[0m" >&2; exit 1; }

[[ -d "$DETEKT" ]] || fail "detekt source not found at $DETEKT"

install() {
  local mod="$1"
  log "Installing $mod"
  mvn install -DskipTests -f "$DETEKT/$mod/pom.xml" -q
}

# Install parent POM first so all child modules can resolve it from local .m2
log "Installing parent POM"
mvn install -N -f "$DETEKT/pom.xml" -q

# Layer 0 — no detekt deps
install detekt-utils
install detekt-tooling

# Layer 1
install detekt-psi-utils

# Layer 2
install detekt-api

# Layer 3
install detekt-parser
install detekt-metrics

# Layer 4 — rule sets
install detekt-rules-complexity
install detekt-rules-coroutines
install detekt-rules-documentation
install detekt-rules-empty
install detekt-rules-errorprone
install detekt-rules-exceptions
install detekt-rules-naming
install detekt-rules-performance
install detekt-rules-style

# Layer 5 — report modules
install detekt-report-html
install detekt-report-md
install detekt-report-sarif
install detekt-report-txt
install detekt-report-xml

# Layer 6
install detekt-core
install detekt-rules

# Layer 7 — test support
install detekt-test-utils
install detekt-test

log "Installing detekt-api test-jar"
mvn jar:test-jar -f "$DETEKT/detekt-api/pom.xml" -q 2>/dev/null
mvn install:install-file \
  -Dfile="$DETEKT/detekt-api/target/detekt-api-1.23.8-tests.jar" \
  -DgroupId=io.gitlab.arturbosch.detekt \
  -DartifactId=detekt-api \
  -Dversion=1.23.8 \
  -Dpackaging=jar \
  -Dclassifier=tests \
  -DgeneratePom=false \
  -q 2>/dev/null || true

log "Compiling benchmark (thin JAR)"
mvn package -DskipTests -f "$SCRIPT_DIR/benchmark/pom.xml" -q

log "Generating external deps classpath"
mvn dependency:build-classpath \
  -f "$SCRIPT_DIR/benchmark/pom.xml" \
  -DincludeScope=runtime \
  -Dmdep.outputFile="$SCRIPT_DIR/ext-deps-cp.txt" \
  -q

# Strip detekt module JARs — at runtime we use target/classes instead
python3 - "$SCRIPT_DIR/ext-deps-cp.txt" <<'EOF'
import sys, re

path = sys.argv[1]
with open(path) as f:
    entries = f.read().strip().split(':')

# Remove entries that are detekt module JARs (keep external deps only)
filtered = [e for e in entries if '/io/gitlab/arturbosch/detekt/' not in e]
with open(path, 'w') as f:
    f.write(':'.join(filtered))
EOF

log "External deps classpath written to: $SCRIPT_DIR/ext-deps-cp.txt"
log "Done. Ready to run workload-timed.sh (after running mvn test -P tree-merge for each module)."
