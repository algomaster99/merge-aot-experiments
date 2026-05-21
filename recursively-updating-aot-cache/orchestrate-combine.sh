#!/bin/bash
set -e

log() { echo -e "\033[1;32m[$(date '+%H:%M:%S')] $*\033[0m"; }

log "Java version:"
java -version

log "Deleting exisiting aot files"
find . -name "*.aot" -type f -delete

log "Building AOT cache for sub..."
java -XX:AOTCacheOutput=sub/sub.aot -jar sub/target/sub-1.0-SNAPSHOT.jar
log "sub.aot created."

log "Building AOT cache for add..."
java -XX:AOTCacheOutput=add/add.aot -jar add/target/add-1.0-SNAPSHOT.jar
log "add.aot created."

log "Building AOT cache for mul..."
java -XX:AOTCacheOutput=mul/mul.aot -jar mul/target/mul-1.0-SNAPSHOT.jar
log "mul.aot created."

log "Building AOT cache for math..."
java -XX:AOTCacheOutput=math/math.aot -jar math/target/math-1.0-SNAPSHOT.jar
log "math.aot created."

# It should not matter which is the base cache
log "Combining AOT caches..."
java -Xlog:aot+merge=info -XX:AOTMode=merge -XX:AOTCache=sub/sub.aot \
      -XX:AOTMergeInputs="add/add.aot:mul/mul.aot:math/math.aot" \
      -XX:AOTCacheOutput=tree-combined.aot \
      -cp "add/target/add-1.0-SNAPSHOT.jar:mul/target/mul-1.0-SNAPSHOT.jar:math/target/math-1.0-SNAPSHOT.jar" \
      -version

