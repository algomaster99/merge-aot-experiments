# JIT Replay Testing

## Prerequisites

Use a **debug build of JDK**. Example:

```
openjdk version "27-internal" 2026-09-15
OpenJDK Runtime Environment (build 27-internal-adhoc.aman.jdk)
OpenJDK 64-Bit Server VM (build 27-internal-adhoc.aman.jdk, mixed mode, sharing)
```

---

## Workflow

### 1. Dump replay data

Run:

```bash
java -XX:+UnlockDiagnosticVMOptions -XX:+PrintCompilation -XX:+LogCompilation -XX:+PrintAssembly -XX:CompileCommand=DumpReplay,\*::\* -jar pdfbox-app-3.0.4.jar
```
> The payload simply prints the help message and exits.

This creates two types of files:

- `hotspot_pid<pid>.log`
- `replay_pid<pid>_compid<compid>.log`

### 2. Extract assembly from original compilation

**Goal:** Check whether replay produces the same assembly as the original compilation.

Run `extract_nmethods.py` to extract assembly from `hotspot_pid<pid>.log`. Each output file is named:

`<compile_id>,<method_name>,<c1|c2>.log`

- **Compilation ID** — ensures the correct replay file is used.
- **Method name** — ensures the correct ASM code is compared.

Output goes to the `replay_dump` directory.

### 3. Replay and capture assembly

For each file in `replay_dump`, run a replay with the matching `replay_pid<pid>_compid<compid>.log` file. This is done by running `replay_and_diff.py`.

It runs a command like:

```bash
java -XX:+UnlockDiagnosticVMOptions -XX:+PrintCompilation -XX:+LogCompilation -XX:+PrintAssembly -XX:+ReplayCompiles -XX:ReplayDataFile=replay_pid<pid>_compid<compid>.log -XX:+ReplayIgnoreInitErrors -XX:LogFile=lol.log -jar pdfbox-app-3.0.4.jar
```

- Replay output is written to a temporary file `lol.log`.
- The script saves the replayed assembly into the `replay_individual` directory.

### 4. Diff original vs replayed assembly

Compare assembly in `replay_dump` (original) with `replay_individual` (replayed) after three normalizations:

1. **Hex addresses** → `0x0`
2. **Compiled method timestamp / compile_id / level** → `0`
3. **Whitespace-only changes** → ignored

All diffs are stored in the `diff` directory.

---

## Example diffs

| Type | File |
|------|------|
| Difference in runtime call name | [2,java.lang.String::hashCode,c1.diff](diff/2,java.lang.String::hashCode,c1.diff) |
| Difference in registers used | [691,sun.reflect.annotation.AnnotationParser::parseAnnotations,c1.diff](diff/691,sun.reflect.annotation.AnnotationParser::parseAnnotations,c1.diff) |
| Difference in application class | [1547,picocli.CommandLine$Model$Interpolator::interpolate,c1.diff](diff/1547,picocli.CommandLine$Model$Interpolator::interpolate,c1.diff) |
| Difference in instructions (possible refactor) | [1241,jdk.internal.classfile.impl.DirectCodeBuilder$4::generateStackMaps,c1.diff](diff/1241,jdk.internal.classfile.impl.DirectCodeBuilder$4::generateStackMaps,c1.diff) |
