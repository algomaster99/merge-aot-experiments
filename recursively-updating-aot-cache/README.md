# Recursively Updating AOT Cache

An experiment demonstrating how JVM AOT caches can be built incrementally (merged) across a chain of dependent JARs, so that downstream applications inherit the cached state of all upstream modules.

## Concept

We introduce a new AOT mode `merge` which allows an existing AOT cache to be extended rather than rebuilt from scratch.

```
sub.aot  →  add.aot  →  mul.aot  →  math.aot
```

Each `.aot` file includes all the cached work from every module before it.

## Running the experiment

```bash
./orchestrate.sh # to build the AOT cache chain
./performance-check.sh # to check the performance of the AOT cache chain
```

## Modules

| Module | Description |
|--------|-------------|
| `sub`  | Subtractor — the base module, no dependencies |
| `add`  | Adder — depends on `sub` |
| `mul`  | Multiplier — depends on `add` (and transitively `sub`) |
| `math` | Orchestrator — uses all three, performs a combined workload |

## Building the AOT Cache Chain

Run `orchestrate.sh` to build and merge all caches in order:

```bash
./orchestrate.sh
```

It does the following:

1. **sub** — create `sub/sub.aot` from scratch
   ```
   java -XX:AOTCacheOutput=sub/sub.aot -jar sub/target/sub-1.0-SNAPSHOT.jar
   ```

2. **add** — merge `sub.aot` into `add/add.aot`
   ```
   java -XX:AOTMode=merge -XX:AOTCache=sub/sub.aot -XX:AOTCacheOutput=add/add.aot -jar add/target/add-1.0-SNAPSHOT.jar
   ```

3. **mul** — merge `add.aot` into `mul/mul.aot`
   ```
   java -XX:AOTMode=merge -XX:AOTCache=add/add.aot -XX:AOTCacheOutput=mul/mul.aot -jar mul/target/mul-1.0-SNAPSHOT.jar
   ```

4. **math** — merge `mul.aot` into `math/math.aot`
   ```
   java -XX:AOTMode=merge -XX:AOTCache=mul/mul.aot -XX:AOTCacheOutput=math/math.aot -jar math/target/math-1.0-SNAPSHOT.jar
   ```

## Performance Results

Measured on OpenJDK 25 (build `25-internal-adhoc`). All times are wall-clock milliseconds for a single JVM startup + workload run.

### sub

| Mode      | Time  |
|-----------|-------|
| default   | 81ms  |
| no CDS    | 168ms |
| AOT cache | **67ms** |

### add

| Mode      | Time  |
|-----------|-------|
| default   | **91ms**  |
| no CDS    | 171ms |
| AOT cache | 115ms |

### mul

| Mode      | Time  |
|-----------|-------|
| default   | **88ms**  |
| no CDS    | 200ms |
| AOT cache | 103ms  |

### math

| Mode      | Time   |
|-----------|--------|
| default   | **90ms** |
| no CDS    | 179ms  |
| AOT cache | 122ms  |

### Summary

The AOT cache is the fastest only for `sub` — the base module whose cache was built from scratch. For `add`, `mul`, and `math`, the default mode is faster.

The key reason is **archive heap (hp) and AOT code (ac) region retention**. When `sub.aot` is built fresh, the JVM captures `Archived Heap` and `AOT Code` region specifically for `sub`'s workload. Those regions are directly usable at startup.
This is currently not implemented for merged caches.
