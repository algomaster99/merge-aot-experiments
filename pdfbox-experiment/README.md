# pdfbox AOT cache experiment

Steps to run once `tree.aot` is in hand (produced by `orchestrate-combine-4.sh`).
All commands run from **`pdfbox-experiment/`**.

---

## Excluded dependencies

**picocli** is a direct dependency of `pdfbox-tools` but is excluded from the AOT cache experiment. Its classes are compiled to bytecode version 49 (Java 5), which the AOT cache mechanism automatically skips — there is nothing to include.

---

## Prerequisites

- Java 24+ with AOT cache support
- Maven 3.9+, Python 3
- `aotp` jar at `~/Desktop/chains/aotp/aotp/target/aotp-0.0.1-SNAPSHOT.jar`
  (override with `AOTP_JAR=...`)

---

## Step 1 — Build the pdfbox app jar

```bash
cd pdfbox && mvn package -P tree-merge -DskipTests && cd ..
```

Produces `pdfbox/app/target/pdfbox-app-3.0.7.jar`.

---

## Step 2 — Record runtime class loads

```bash
./record-runtime-classes.sh
```

Runs ten PDFBox operations with `-Xlog:class+load=info -XX:AOTCache=tree.aot`.
Writes to `../aot-analysis/pdfbox/runtime/`:

| File | Contents |
|---|---|
| `tree-aot.classes` | Classes served from `tree.aot` at runtime |
| `tree-fs.classes` | Classes loaded from the filesystem (not in cache — hidden/generated) |

---

## Step 3 — Dump static tree.aot class list

```bash
../aot-analysis/record.sh -o ../aot-analysis/pdfbox/per-cache tree.aot
```

Writes `../aot-analysis/pdfbox/per-cache/tree.classes` (aotp dump of the merged cache).

---

## Step 4 — Coverage funnel

```bash
../aot-analysis/coverage.sh ../aot-analysis/pdfbox/coverage.conf
```

Dumps per-artifact `cache.aot` class lists via `aotp` → `../aot-analysis/pdfbox/per-cache/`
and prints:

```
Module                      Source  cache.aot     %  tree.aot     %
io                            XXXX       XXXX   XX%      XXXX   XX%
fontbox                       XXXX       XXXX   XX%      XXXX   XX%
pdfbox                        XXXX       XXXX   XX%      XXXX   XX%
tools                         XXXX       XXXX   XX%      XXXX   XX%
...
TOTAL                         XXXX       XXXX   XX%      XXXX   XX%
```

---

## Analysis directory layout

```
../aot-analysis/pdfbox/
  source/         class lists from target/classes or shaded JARs
  per-cache/      aotp dumps of each cache.aot and tree.aot
  runtime/        class+load output from the workload run
  set-operations/ treemap inputs and intersection files
```

---

## AOT Analysis

### A1 — Extract per-cache class lists

```bash
../aot-analysis/record.sh -o ../aot-analysis/pdfbox/per-cache \
  pdfbox/io/cache.aot \
  pdfbox/fontbox/cache.aot \
  pdfbox/pdfbox/cache.aot \
  pdfbox/tools/cache.aot \
  pdfbox-deps/pdfbox-jbig2/cache.aot \
  pdfbox-deps/apache-commons-io/cache.aot \
  pdfbox-deps/commons-logging-workload/cache.aot \
  pdfbox-deps/bc-java-prov-workload/cache.aot \
  pdfbox-deps/bc-java-util-workload/cache.aot \
  pdfbox-deps/bc-java-pkix-workload/cache.aot \
  tree.aot
```

### A2 — Classify tree.aot (JDK / Hidden / App)

```bash
../aot-analysis/classify.sh \
  -o ../aot-analysis/pdfbox/first-classification \
  ../aot-analysis/pdfbox/per-cache/tree.classes
```

Writes `tree-jdk.classes`, `tree-hidden.classes`, `tree-app.classes` into `first-classification/`.

### A3 — Extract source class lists

```bash
BASE=$(cd .. && pwd)
../aot-analysis/source.sh \
  -o ../aot-analysis/pdfbox/source \
  "io:$BASE/pdfbox-experiment/pdfbox/io/target/classes" \
  "fontbox:$BASE/pdfbox-experiment/pdfbox/fontbox/target/classes" \
  "pdfbox:$BASE/pdfbox-experiment/pdfbox/pdfbox/target/classes" \
  "tools:$BASE/pdfbox-experiment/pdfbox/tools/target/classes" \
  "pdfbox-jbig2:$BASE/pdfbox-experiment/pdfbox-deps/pdfbox-jbig2/target/classes" \
  "commons-io:$BASE/pdfbox-experiment/pdfbox-deps/apache-commons-io/target/classes" \
  "commons-logging:$BASE/pdfbox-experiment/pdfbox-deps/commons-logging-workload/target/commons-logging-workload-1.0-SNAPSHOT.jar" \
  "bcprov:$BASE/pdfbox-experiment/pdfbox-deps/bc-java-prov-workload/target/bc-java-prov-workload-1.0-SNAPSHOT.jar" \
  "bcutil:$BASE/pdfbox-experiment/pdfbox-deps/bc-java-util-workload/target/bc-java-util-workload-1.0-SNAPSHOT.jar" \
  "bcpkix:$BASE/pdfbox-experiment/pdfbox-deps/bc-java-pkix-workload/target/bc-java-pkix-workload-1.0-SNAPSHOT.jar"
```

### A4 — Per-dependency contribution funnel

Shows, for each dependency: how many source classes made it into (a) the module's own `cache.aot` and (b) the final `tree-app.classes`. Classes missing from the last stage are candidates for investigation.

```bash
../aot-analysis/funnel.sh \
  ../aot-analysis/pdfbox/first-classification/tree-app.classes \
  "io:../aot-analysis/pdfbox/source/io.classes:../aot-analysis/pdfbox/per-cache/io.classes" \
  "fontbox:../aot-analysis/pdfbox/source/fontbox.classes:../aot-analysis/pdfbox/per-cache/fontbox.classes" \
  "pdfbox:../aot-analysis/pdfbox/source/pdfbox.classes:../aot-analysis/pdfbox/per-cache/pdfbox.classes" \
  "tools:../aot-analysis/pdfbox/source/tools.classes:../aot-analysis/pdfbox/per-cache/tools.classes" \
  "pdfbox-jbig2:../aot-analysis/pdfbox/source/pdfbox-jbig2.classes:../aot-analysis/pdfbox/per-cache/pdfbox-jbig2.classes" \
  "commons-io:../aot-analysis/pdfbox/source/commons-io.classes:../aot-analysis/pdfbox/per-cache/apache-commons-io.classes" \
  "commons-logging:../aot-analysis/pdfbox/source/commons-logging.classes:../aot-analysis/pdfbox/per-cache/commons-logging-workload.classes" \
  "bcprov:../aot-analysis/pdfbox/source/bcprov.classes:../aot-analysis/pdfbox/per-cache/bc-java-prov-workload.classes" \
  "bcutil:../aot-analysis/pdfbox/source/bcutil.classes:../aot-analysis/pdfbox/per-cache/bc-java-util-workload.classes" \
  "bcpkix:../aot-analysis/pdfbox/source/bcpkix.classes:../aot-analysis/pdfbox/per-cache/bc-java-pkix-workload.classes"
```

---

## Ad-hoc utilities

```bash
# Classify a class list (JDK / Lambda / Hidden / App breakdown)
../aot-analysis/classify.sh ../aot-analysis/pdfbox/runtime/tree-aot.classes

# Compare static cache contents vs runtime-served
../aot-analysis/compare.sh \
  ../aot-analysis/pdfbox/per-cache/tree.classes \
  ../aot-analysis/pdfbox/runtime/tree-aot.classes

# Dump classes in any .aot file
java -jar "$AOTP_JAR" tree.aot --list-classes | wc -l
```
