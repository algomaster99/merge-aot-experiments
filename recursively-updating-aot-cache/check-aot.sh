#!/bin/bash
set -e

log() { echo -e "\033[1;32m[$(date '+%H:%M:%S')] $*\033[0m"; }

PASS="\033[1;32mPASS\033[0m"
FAIL="\033[1;31mFAIL\033[0m"

check_module() {
    local name=$1
    local aot=$2
    local jar=$3

    log "Checking $name..."
    local output
    output=$(java -Xlog:class+load=info -XX:AOTCache="$aot" -jar "$jar" 2>&1 | grep "com.example")

    local all_pass=true
    while IFS= read -r line; do
        local class
        class=$(echo "$line" | grep -oP '(?<=\] )[\w.$]+')
        if echo "$line" | grep -q "shared objects file"; then
            echo -e "  [$PASS] $class"
        else
            echo -e "  [$FAIL] $class (not from AOT cache)"
            all_pass=false
        fi
    done <<< "$output"

    $all_pass && echo -e "  All classes loaded from AOT cache." || true
}

check_module "sub"  "sub/sub.aot"   "sub/target/sub-1.0-SNAPSHOT.jar"
check_module "add"  "add/add.aot"   "add/target/add-1.0-SNAPSHOT.jar"
check_module "mul"  "mul/mul.aot"   "mul/target/mul-1.0-SNAPSHOT.jar"
check_module "math" "math/math.aot" "math/target/math-1.0-SNAPSHOT.jar"
