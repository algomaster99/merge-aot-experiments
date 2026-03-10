#!/bin/bash
set -e

log()  { echo -e "\033[1;32m[$(date '+%H:%M:%S')] $*\033[0m"; }
info() { echo -e "\033[1;34m  >> $*\033[0m"; }
sep()  { echo -e "\033[0;90m  $(printf '─%.0s' {1..50})\033[0m"; }

# Run a labeled timed command. Usage: timed <label> <cmd...>
timed() {
  local label="$1"; shift
  info "$label"
  local start=$(($(date +%s%N) / 1000000))
  "$@" 2>/dev/null
  local elapsed=$(( $(date +%s%N) / 1000000 - start ))
  printf "  \033[1;33m%-20s\033[0m \033[1;37m%dms\033[0m\n" "$label" "$elapsed"
}

log "Java version:"
java -version
echo

log "sub"
sep
timed "default"    java -jar math/target/math-1.0-SNAPSHOT.jar
timed "no CDS"     java -Xshare:off -jar math/target/math-1.0-SNAPSHOT.jar
timed "AOT cache"  java -XX:AOTCache=sub/sub.aot -jar math/target/math-1.0-SNAPSHOT.jar
echo

log "add"
sep
timed "default"    java -jar math/target/math-1.0-SNAPSHOT.jar
timed "no CDS"     java -Xshare:off -jar math/target/math-1.0-SNAPSHOT.jar
timed "AOT cache"  java -XX:AOTCache=add/add.aot -jar math/target/math-1.0-SNAPSHOT.jar
echo

log "mul"
sep
timed "default"    java -jar math/target/math-1.0-SNAPSHOT.jar
timed "no CDS"     java -Xshare:off -jar math/target/math-1.0-SNAPSHOT.jar
timed "AOT cache"  java -XX:AOTCache=mul/mul.aot -jar math/target/math-1.0-SNAPSHOT.jar
echo

log "math"
sep
timed "default"    java -jar math/target/math-1.0-SNAPSHOT.jar
timed "no CDS"     java -Xshare:off -jar math/target/math-1.0-SNAPSHOT.jar
timed "AOT cache"  java -XX:AOTCache=math/math.aot -jar math/target/math-1.0-SNAPSHOT.jar
