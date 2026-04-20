# Distributed AOT Cache Model for Commons Compress

## Context

Goal: establish the same **distributed AOT cache model** used for pdfbox — each Maven artifact
gets a companion `.aot` file; per-artifact caches are **merged** into a single `tree.aot` for
production use, mirroring how JARs are placed on a classpath.

**One-step AOT workflow** (used throughout):
```bash
java -XX:AOTCacheOutput=cache.aot -cp <classpath> <MainClass or -version>
```

---

## Execution model

Executed **one dependency at a time**, with an explicit pause after each configuration step
so the user can drive AOT cache generation themselves. Do **not** batch-run multiple
dependencies: each is a separate, reviewable unit.

For every missing cache the loop is:

1. **Clone** upstream source into `commons-compress-experiment/commons-compress-deps/`.
2. **Configure** the build and verify the JAR builds locally.
3. **PAUSE for user review.** Stop here — let the user generate the per-artifact AOT cache.
4. If the cache was created → continue to the next dependency.
5. If the cache could not be created → fall back to the **workload pattern** (see below).
   Pause again after the workload is in place.
6. Once all per-artifact caches exist, regenerate `tree.aot` and run verification.

The agent driving this plan must **stop and wait** between each numbered step. Do not
proceed past a PAUSE marker without explicit user confirmation.

### Workload-pattern fallback

When a dependency's own test suite cannot produce an AOT cache, build a small standalone
Maven project under `commons-compress-experiment/commons-compress-deps/<dep>-workload/`:

- `pom.xml` with only the target dependency + `maven-shade-plugin` for a fat jar.
- `WorkloadApplication.java` whose `main()` exercises the public API enough to load the
  classes that matter.
- `mvn package`, then `java -XX:AOTCacheOutput=cache.aot -jar target/...jar`.

Reference implementation: `dependencies/picocli-experiment/`.

---

## Dependency Inventory

From `commons-compress:1.28.0` dependency tree (optional deps excluded from cache):

```
commons-compress:1.28.0   ← commons-compress-experiment/commons-compress/
commons-lang3:3.18.0      ← commons-compress-deps/commons-lang/
commons-codec:1.19.0      ← commons-compress-deps/commons-codec/
commons-io:2.20.0         ← commons-compress-deps/apache-commons-io/
```

Optional deps (`zstd-jni`, `dec`/brotli, `xz`, `asm`) are **skipped** — they are
optional and are not required by downstream users.

---

## Current State

Location: `commons-compress-experiment/`

| Cache | Path | Status |
|---|---|---|
| commons-lang3 | `commons-compress-deps/commons-lang/cache.aot` | ✓ exists |
| commons-codec | `commons-compress-deps/commons-codec/cache.aot` | ✓ exists |
| commons-io | `commons-compress-deps/apache-commons-io/cache.aot` | ✓ exists |
| commons-compress | `commons-compress/cache.aot` | ✓ exists |
| **tree.aot** | `tree.aot` | **MISSING** |

Already in place:
- `orchestrate-combine.sh` — merges all 4 per-artifact caches into `tree.aot`.
- `workload-timed.sh` — runs the benchmark (no-AOT vs tree-AOT) over `RUNS` iterations.
- `record-runtime-classes.sh` — records which classes are served from AOT vs loaded from FS.
- `benchmark/` — fat-jar benchmark project (`dev.compressexp.Main`) with workloads:
  `zip-roundtrip`, `tar-roundtrip`, `gzip-roundtrip`, `list-archives`.

---

## Remaining Steps

### Step 1 — Build the benchmark fat jar

```bash
cd commons-compress-experiment/benchmark
mvn package -DskipTests
```

Expected: `benchmark/target/benchmark-1.0-SNAPSHOT.jar`

**PAUSE — let the user run this. Do not proceed until confirmed.**

### Step 2 — Merge per-artifact caches into `tree.aot`

```bash
cd commons-compress-experiment
./orchestrate-combine.sh
```

Expected: `tree.aot` created and non-empty.

**PAUSE — let the user run this. Do not proceed until confirmed.**

### Step 3 — Run the timed benchmark

```bash
cd commons-compress-experiment
./workload-timed.sh        # RUNS=10 by default
```

Records median/min/max ms for each workload operation under no-AOT and tree-AOT modes,
plus a class-load source summary per operation.

**PAUSE — let the user run this. Do not proceed until confirmed.**

### Step 4 — Record runtime class sources (optional analysis)

```bash
cd commons-compress-experiment
./record-runtime-classes.sh
```

Outputs:
- `aot-analysis/commons-compress/classes/runtime-tree.classes` — classes served from AOT
- `aot-analysis/commons-compress/classes/runtime-tree-fs.classes` — classes loaded from FS

---

## Files Reference

| File | Status | Notes |
|---|---|---|
| `commons-compress/` | cloned | Main artifact, `cache.aot` exists |
| `commons-compress-deps/commons-lang/` | cloned | `cache.aot` exists |
| `commons-compress-deps/commons-codec/` | cloned | `cache.aot` exists |
| `commons-compress-deps/apache-commons-io/` | cloned | `cache.aot` exists |
| `benchmark/` | exists | Needs `mvn package` |
| `orchestrate-combine.sh` | exists | Ready to run |
| `workload-timed.sh` | exists | Ready after tree.aot exists |
| `record-runtime-classes.sh` | exists | Optional post-merge analysis |

---

## End-to-end verification sequence

1. `benchmark/target/benchmark-1.0-SNAPSHOT.jar` exists
2. `./orchestrate-combine.sh` produces `tree.aot` without errors
3. `./workload-timed.sh` completes — captures no-AOT vs tree-AOT timing table
4. `./record-runtime-classes.sh` produces class-source breakdown (optional)
