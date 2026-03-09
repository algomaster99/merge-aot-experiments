#!/usr/bin/env python3
"""
Extract nmethod sections from a HotSpot log file using XML-like <print_nmethod>...</print_nmethod>.
Only creates replay_dump/: assembly content (between tags). Named <compile_id>,<method name>,<c1|c2>.log.
"""

import re
import sys
from pathlib import Path

# Opening tag: <print_nmethod compile_id='N' compiler='c1'|'c2' ...>
PRINT_NMETHOD_OPEN = re.compile(
    r"<print_nmethod\s+compile_id='(\d+)'\s+compiler='c([12])'",
    re.IGNORECASE
)
# "Compiled method (c1) 56    1       3       java.lang.Byte::toUnsignedInt (6 bytes)" (for filename)
COMPILED_METHOD_LINE = re.compile(
    r"Compiled method \(c([12])\)\s+\d+\s+(\d+)\s+.*?\s+([^\s]+::[^\s]+)\s+\(\d+ bytes\)"
)


def sanitize_for_filename(name: str) -> str:
    """Replace path separators and other chars invalid in filenames."""
    return name.replace("/", "_").replace("\\", "_")


def extract_sections(log_path: Path):
    log_path = Path(log_path)
    replay_dir = log_path.parent
    out_dir = replay_dir / "replay_dump"
    out_dir.mkdir(exist_ok=True)

    with open(log_path, "r", encoding="utf-8", errors="replace") as f:
        lines = f.readlines()

    i = 0
    sections_found = 0
    while i < len(lines):
        m = PRINT_NMETHOD_OPEN.search(lines[i])
        if not m:
            i += 1
            continue

        open_line = i
        compile_id = m.group(1)
        compiler_tag = f"c{m.group(2)}"

        # Find closing tag </print_nmethod>
        close_line = None
        for j in range(open_line + 1, len(lines)):
            if "</print_nmethod>" in lines[j]:
                close_line = j
                break
        if close_line is None:
            i += 1
            continue

        # Content = lines between opening and closing tag (exclude the tag lines)
        content_lines = lines[open_line + 1 : close_line]

        # Get method name from "Compiled method (c1) ..." line within content (for filename)
        method_name = None
        for line in content_lines:
            cm = COMPILED_METHOD_LINE.match(line.rstrip())
            if cm:
                method_name = cm.group(3)
                break
        if not method_name:
            i = close_line + 1
            continue

        safe_method = sanitize_for_filename(method_name)
        filename = f"{compile_id},{safe_method},{compiler_tag}.log"
        out_path = out_dir / filename
        out_path.write_text("".join(content_lines), encoding="utf-8")
        sections_found += 1
        print(f"  {filename}")

        i = close_line + 1

    return sections_found



def main():
    if len(sys.argv) < 2:
        log_file = Path(__file__).parent / "hotspot_pid189601.log"
        print(f"Usage: {sys.argv[0]} [hotspot.log]\nUsing default: {log_file}")
    else:
        log_file = Path(sys.argv[1])

    if not log_file.is_file():
        print(f"Error: not a file: {log_file}", file=sys.stderr)
        sys.exit(1)

    replay_dir = log_file.parent
    out_dir = replay_dir / "replay_dump"
    print(f"Extracting nmethod sections from {log_file}")
    print(f"replay_dump: {out_dir}\n")

    n = extract_sections(log_file)
    print(f"\nWrote {n} section(s) to replay_dump")


if __name__ == "__main__":
    main()
