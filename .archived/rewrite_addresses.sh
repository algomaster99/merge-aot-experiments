#!/bin/bash

if [ $# -eq 0 ]; then
    echo "Usage: $0 <file1> [file2] [file3] ..."
    exit 1
fi

# Use sed to replace all hexadecimal addresses (0x followed by hex digits) with 0x0000000000000000
# The pattern matches 0x followed by one or more hexadecimal digits
for FILE in "$@"; do
    if [ ! -f "$FILE" ]; then
        echo "Error: File '$FILE' does not exist, skipping..."
        continue
    fi
    
    sed --in-place 's/0x[0-9a-fA-F]\+/0x0000000000000000/g' "$FILE"
    echo "Rewritten all memory addresses in '$FILE' to 0x0000000000000000"
done
