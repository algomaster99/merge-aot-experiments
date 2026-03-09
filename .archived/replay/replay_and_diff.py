#!/usr/bin/env python3
"""
For each file in replay_dump (named compile_id,method_name,compiler.log):
  1. Find replay_pid*_compid<compile_id>.log in the same directory as this script.
  2. Run Java with -XX:+ReplayCompiles -XX:ReplayDataFile=... to produce lol.log.
  3. Extract assembly from lol.log (same as extract_nmethods.py) and verify method name.
  4. Save to replay_individual/<same_filename>.
Then normalize all addresses to 0x0000000000000 in both replay_dump and replay_individual,
diff them, and report which are equal and which are not.
"""

import re
import subprocess
import sys
import tempfile
from pathlib import Path


class ReplayRequiresDebugVM(Exception):
    """Raised when the JVM reports that ReplayCompiles requires a debug build."""
    def __init__(self, stderr: str):
        self.stderr = stderr
        super().__init__(stderr)

# Same as extract_nmethods.py
PRINT_NMETHOD_OPEN = re.compile(
    r"<print_nmethod\s+compile_id='(\d+)'\s+compiler='c([12])'",
    re.IGNORECASE,
)
COMPILED_METHOD_LINE = re.compile(
    r"Compiled method \(c([12])\)\s+\d+\s+(\d+)\s+.*?\s+([^\s]+::[^\s]+)\s+\(\d+ bytes\)",
)

# Hex address (e.g. 0x000076fcb3be5500) -> 0x0 for normalization
HEX_ADDRESS = re.compile(r"0x[0-9a-fA-F]+")
NORMALIZED_ADDRESS = "0x0"

# "Compiled method (c1) 75    3       3       method::name" or " ... 19324 1069   !   3       method::name" -> normalize timestamp, compile_id, level to 0 (allow optional tokens like ! between)
COMPILED_METHOD_NORMALIZE = re.compile(
    r"(Compiled method \(c[12]\))\s+\d+\s+\d+(?:\s+\S+)*\s+\d+(\s+)",
    re.IGNORECASE,
)


def script_dir() -> Path:
    return Path(__file__).resolve().parent


def parse_replay_dump_filename(filename: str) -> tuple[str | None, str | None, str | None]:
    """Return (compile_id, method_name, compiler) or (None, None, None) if invalid."""
    if not filename.endswith(".log"):
        return (None, None, None)
    name = filename[:-4]  # strip .log
    parts = name.split(",")
    if len(parts) < 3:
        return (None, None, None)
    compile_id = parts[0]
    compiler = parts[-1]  # c1 or c2
    if compiler not in ("c1", "c2"):
        return (None, None, None)
    method_name = ",".join(parts[1:-1])
    return (compile_id, method_name, compiler)


def find_replay_file(replay_dir: Path, compile_id: str) -> Path | None:
    """Find replay_pid*_compid<compile_id>.log in replay_dir."""
    pattern = f"replay_pid*_compid{compile_id}.log"
    matches = list(replay_dir.glob(pattern))
    if not matches:
        return None
    return matches[0]


def extract_sections_from_log(log_path: Path) -> list[tuple[str, str, list[str]]]:
    """Extract (compile_id, method_name, content_lines) for each <print_nmethod> in log."""
    with open(log_path, "r", encoding="utf-8", errors="replace") as f:
        lines = f.readlines()

    result = []
    i = 0
    while i < len(lines):
        m = PRINT_NMETHOD_OPEN.search(lines[i])
        if not m:
            i += 1
            continue
        open_line = i
        compile_id = m.group(1)
        compiler_tag = f"c{m.group(2)}"
        close_line = None
        for j in range(open_line + 1, len(lines)):
            if "</print_nmethod>" in lines[j]:
                close_line = j
                break
        if close_line is None:
            i += 1
            continue
        content_lines = lines[open_line + 1 : close_line]
        method_name = None
        for line in content_lines:
            cm = COMPILED_METHOD_LINE.match(line.rstrip())
            if cm:
                method_name = cm.group(3)
                break
        if method_name is not None:
            result.append((compile_id, method_name, content_lines))
        i = close_line + 1
    return result


def normalize_for_diff(text: str) -> str:
    """Normalize text for diff: hex addresses -> 0x0; Compiled method timestamp/compile_id/level -> 0."""
    text = HEX_ADDRESS.sub(NORMALIZED_ADDRESS, text)
    text = COMPILED_METHOD_NORMALIZE.sub(r"\1 0 0 0\2", text)
    return text


def normalize_method_name_for_compare(name: str) -> str:
    """Decode HTML entities so filename method name matches log method name."""
    return name.replace("&lt;", "<").replace("&gt;", ">").replace("&apos;", "'")


def run_replay_and_extract(
    replay_dir: Path,
    replay_data_file: Path,
    jar_path: Path,
    expected_method: str,
    work_log: Path,
) -> str | None:
    """Run Java replay; extract single nmethod content; verify method name. Return content or None."""
    cmd = [
        "java",
        "-XX:+UnlockDiagnosticVMOptions",
        "-XX:+PrintCompilation",
        "-XX:+LogCompilation",
        "-XX:+PrintAssembly",
        "-XX:+ReplayCompiles",
        f"-XX:ReplayDataFile={replay_data_file}",
        "-XX:+ReplayIgnoreInitErrors",
        f"-XX:LogFile={work_log}",
        "-jar",
        str(jar_path),
    ]
    try:
        proc = subprocess.run(
            cmd,
            cwd=str(replay_dir),
            capture_output=True,
            timeout=120,
            check=False,
            text=True,
            errors="replace",
        )
        stderr = (proc.stderr or "").strip()
        # ReplayCompiles is develop-only; requires debug VM
        if proc.returncode != 0 and stderr:
            if "ReplayCompiles" in stderr or "debug version" in stderr.lower():
                raise ReplayRequiresDebugVM(stderr)
    except ReplayRequiresDebugVM:
        raise
    except subprocess.TimeoutExpired:
        return None
    except FileNotFoundError:
        return None

    if not work_log.is_file():
        return None
    sections = extract_sections_from_log(work_log)
    # Replay of one compile_id should give at most one nmethod; match by method name
    expected_norm = normalize_method_name_for_compare(expected_method)
    for _cid, method_name, content_lines in sections:
        if normalize_method_name_for_compare(method_name) == expected_norm:
            return "".join(content_lines)
    # If no exact match, return first section content if any (for reporting)
    if sections:
        return "".join(sections[0][2])
    return None


def main() -> None:
    replay_dir = script_dir()
    replay_dump_dir = replay_dir / "replay_dump"
    replay_individual_dir = replay_dir / "replay_individual"
    jar_path = replay_dir / "../app/target/pdfbox-app-3.0.4.jar"
    jar_path = jar_path.resolve()
    work_log = replay_dir / "lol.log"

    if not replay_dump_dir.is_dir():
        print(f"Error: replay_dump not found: {replay_dump_dir}", file=sys.stderr)
        sys.exit(1)
    if not jar_path.is_file():
        print(f"Warning: JAR not found: {jar_path}", file=sys.stderr)
        print("Replay steps will be skipped; diff will use existing replay_individual if present.")

    replay_individual_dir.mkdir(exist_ok=True)
    diff_dir = replay_dir / "diff"
    diff_dir.mkdir(exist_ok=True)

    dump_files = sorted(replay_dump_dir.glob("*.log"))
    equal = []
    not_equal = []
    missing_individual = []
    missing_replay_file = []
    skipped_no_jar = []
    replay_failed = []

    total = len(dump_files)
    for idx, dump_path in enumerate(dump_files):
        name = dump_path.name
        parsed = parse_replay_dump_filename(name)
        if parsed[0] is None:
            continue
        compile_id, method_name, compiler = parsed
        replay_file = find_replay_file(replay_dir, compile_id)
        if replay_file is None:
            missing_replay_file.append(name)
            continue
        if not jar_path.is_file():
            skipped_no_jar.append(name)
            continue

        if (idx + 1) % 50 == 0 or idx == 0:
            print(f"Replay {idx + 1}/{total}: {name}", flush=True)
        try:
            content = run_replay_and_extract(
                replay_dir, replay_file, jar_path, method_name, work_log
            )
        except ReplayRequiresDebugVM as e:
            print(
                "\nError: ReplayCompiles requires a debug build of the JVM.\n"
                "Use a JDK built with --with-debug-level=fastdebug (or similar).\n",
                file=sys.stderr,
            )
            print(e.stderr, file=sys.stderr)
            sys.exit(1)
        if content is None:
            replay_failed.append(name)
            continue
        out_path = replay_individual_dir / name
        out_path.write_text(content, encoding="utf-8")

    # If we skipped due to no JAR, don't diff. Otherwise load replay_individual and diff.
    if skipped_no_jar and not any(
        (replay_individual_dir / f.name).exists() for f in dump_files
    ):
        print("Skipped replay (no JAR). No replay_individual files to diff.")
        return

    # Normalize and diff
    for dump_path in dump_files:
        name = dump_path.name
        parsed = parse_replay_dump_filename(name)
        if parsed[0] is None:
            continue
        ind_path = replay_individual_dir / name
        if not ind_path.is_file():
            if name not in missing_replay_file and name not in replay_failed:
                missing_individual.append(name)
            continue
        dump_text = dump_path.read_text(encoding="utf-8", errors="replace")
        ind_text = ind_path.read_text(encoding="utf-8", errors="replace")
        norm_dump = normalize_for_diff(dump_text)
        norm_ind = normalize_for_diff(ind_text)
        if norm_dump.strip() == norm_ind.strip():
            equal.append(name)
        else:
            not_equal.append(name)
            # Write unified diff to diff/<compid>,<method>,<compiler>.diff (ignore whitespace-only changes)
            diff_name = Path(name).with_suffix(".diff").name
            diff_path = diff_dir / diff_name
            with tempfile.NamedTemporaryFile(
                mode="w", suffix=".dump", delete=False, encoding="utf-8"
            ) as f_dump, tempfile.NamedTemporaryFile(
                mode="w", suffix=".ind", delete=False, encoding="utf-8"
            ) as f_ind:
                f_dump.write(norm_dump)
                f_dump.flush()
                f_ind.write(norm_ind)
                f_ind.flush()
                try:
                    result = subprocess.run(
                        ["diff", "-u", "--ignore-all-space", f_dump.name, f_ind.name],
                        capture_output=True,
                        text=True,
                        timeout=10,
                    )
                    # diff exits 0 if same, 1 if different (and prints diff), 2 on error
                    diff_path.write_text(result.stdout or "", encoding="utf-8")
                finally:
                    Path(f_dump.name).unlink(missing_ok=True)
                    Path(f_ind.name).unlink(missing_ok=True)

    # Report
    print("===== Replay / Diff Report =====")
    if missing_replay_file:
        print(f"\nMissing replay file (compile_id not found): {len(missing_replay_file)}")
        for n in missing_replay_file[:20]:
            print(f"  {n}")
        if len(missing_replay_file) > 20:
            print(f"  ... and {len(missing_replay_file) - 20} more")
    if replay_failed:
        print(f"\nReplay or extract failed: {len(replay_failed)}")
        for n in replay_failed[:20]:
            print(f"  {n}")
        if len(replay_failed) > 20:
            print(f"  ... and {len(replay_failed) - 20} more")
    if missing_individual:
        print(f"\nMissing in replay_individual: {len(missing_individual)}")
        for n in missing_individual[:10]:
            print(f"  {n}")
        if len(missing_individual) > 10:
            print(f"  ... and {len(missing_individual) - 10} more")

    print(f"\nEqual (normalized assembly matches): {len(equal)}")
    for n in equal[:30]:
        print(f"  {n}")
    if len(equal) > 30:
        print(f"  ... and {len(equal) - 30} more")

    print(f"\nNot equal (normalized assembly differs): {len(not_equal)}")
    for n in not_equal[:30]:
        print(f"  {n}")
    if len(not_equal) > 30:
        print(f"  ... and {len(not_equal) - 30} more")

    print("\n===== Summary =====")
    print(f"  Equal:   {len(equal)}")
    print(f"  Not equal: {len(not_equal)}")
    print(f"  Missing replay file: {len(missing_replay_file)}")
    print(f"  Replay failed: {len(replay_failed)}")
    print(f"  Missing individual: {len(missing_individual)}")


if __name__ == "__main__":
    main()
