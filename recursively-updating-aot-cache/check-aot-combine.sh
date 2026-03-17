#!/bin/bash
set -e

log() { echo -e "\033[1;32m[$(date '+%H:%M:%S')] $*\033[0m"; }

PASS="\033[1;32mPASS\033[0m"
FAIL="\033[1;31mFAIL\033[0m"

ALL_CLASSES=(
    "com.example.Subtractor"
    "com.example.Adder"
    "com.example.Multiplier"
    "com.example.MathApp"
)

check_combined() {
    local aot="tree-combined.aot"
    local jar="math/target/math-1.0-SNAPSHOT.jar"

    if [[ ! -f "$aot" ]]; then
        echo "Missing $aot. Run ./orchestrate-combine.sh first."
        exit 1
    fi
    if [[ ! -f "$jar" ]]; then
        echo "Missing $jar. Build first (e.g. mvn package)."
        exit 1
    fi

    log "Checking combined/tree AOT cache..."

    local output class line
    output=$(java -Xlog:class+load=info -XX:AOTCache="$aot" -jar "$jar" 2>&1 | grep -E "\] com\.example\.[A-Za-z0-9_$.]+" || true)

    declare -A from_aot=()
    while IFS= read -r line; do
        class=$(echo "$line" | grep -oP '(?<=\] )[\w.$]+')
        [[ -z "$class" ]] && continue
        if [[ "$line" == *"shared objects file"* ]]; then
            from_aot["$class"]=true
        else
            from_aot["$class"]=false
        fi
    done <<< "$output"

    local all_pass=true
    local c
    for c in "${ALL_CLASSES[@]}"; do
        if [[ -z "${from_aot[$c]+x}" ]]; then
            echo -e "  [$FAIL] $c (class not loaded)"
            all_pass=false
            continue
        fi

        if [[ "${from_aot[$c]}" == "true" ]]; then
            echo -e "  [$PASS] $c (from AOT)"
        else
            echo -e "  [$FAIL] $c (expected from AOT, but wasn't)"
            all_pass=false
        fi
    done

    if [[ "$all_pass" == "true" ]]; then
        echo -e "  Expected classes loaded from combined/tree AOT cache."
        return 0
    fi

    return 1
}

check_combined

