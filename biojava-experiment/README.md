# BioJava AOT Cache Experiment

This experiment measures the startup-time impact of AOT class-data caches across
bioinformatics workloads that load **disjoint** algorithm/parser subtrees on a
shared sequence/compound core — the profile where a merged TreeCache beats a
single monolithic AOTCache.

BioJava comes from the DaCapo 2025 suite. It was previously deferred over a
`module-info` risk; this experiment documents and applies the mitigation.

---

## Dependencies and module-info mitigation

### Full declared dependency tree

```
biojava-core:7.2.5
├── slf4j-api:2.0.12                          ✔ kept
├── log4j-slf4j2-impl:2.25.4 (runtime)        ✘ excluded
├── log4j-api:2.25.4 (runtime)                ✘ excluded
├── log4j-core:2.25.4 (runtime)               ✘ excluded  ← ships module-info.class
├── jakarta.xml.bind-api:4.0.0                ✘ excluded
│   └── jakarta.activation-api:2.1.0          ✘ excluded  (transitive)
└── jaxb-runtime:4.0.3 (runtime)              ✘ excluded  ← ships module-info.class
    └── jaxb-core / txw2 / istack / angus     ✘ excluded  (transitive)

biojava-alignment:7.2.5
├── biojava-core:7.2.5                         ✔ kept (see above)
├── forester:1.039                             ✔ kept
│   ├── commons-codec:1.5                      ✔ kept
│   └── openchart:1.4.2                        ✘ excluded  (dead JBoss repo)
├── slf4j-api:2.0.12                           ✔ kept
├── log4j-slf4j2-impl / log4j-api / log4j-core ✘ excluded  (same as above)
```

### Why each dependency is excluded

| Dependency | Reason |
|---|---|
| `log4j-core` | Ships `module-info.class` — breaks AOT cache creation. BioJava never calls log4j directly; it uses only the `slf4j-api` façade, so the binding is swappable. Replaced with `slf4j-simple` in the benchmark. |
| `log4j-slf4j2-impl`, `log4j-api` | Co-removed with `log4j-core`; a slf4j binding requires all three together. |
| `jaxb-runtime` | Ships `module-info.class` — breaks AOT cache creation. No BioJava main-source code references JAXB directly (verified). |
| `jakarta.xml.bind-api` | Direct dependency of `jaxb-runtime`; removed together. Its transitive (`jaxb-core`, `txw2`, `istack-commons-runtime`, `angus-activation`) are also dropped. |
| `openchart` | Hosted on a defunct JBoss repository (unresolvable at build time). Only used by the phylogenetics GUI path; the pairwise-alignment code path the benchmark exercises does not reference it. |

### What remains on the runtime classpath

After exclusions, the only `module-info`-bearing JARs left are **`slf4j-api`**
and **`slf4j-simple`** — handled by the existing **slf4j fork** (reused from
the thymeleaf experiment) which already strips `module-info`. The BioJava
library classes themselves are clean.

---

## Empirical workload diversity (measured on JDK 21, `-Xlog:class+load`)

BioJava (`org.biojava.*`) classes loaded per workload over the shared inputs:

| Workload      | BioJava classes | Module |
|---------------|-----------------|--------|
| fasta-parse   | 35  | biojava-core (FASTA reader) |
| genbank-parse | 57  | biojava-core (GenBank reader) |
| transcribe    | 72  | biojava-core (transcription engine) |
| revcomp-gc    | 29  | biojava-core (compound stats) |
| align-global  | 57  | biojava-alignment (Needleman–Wunsch) |
| align-local   | 54  | biojava-alignment (Smith–Waterman) |

- **18** classes are loaded by **all six** workloads (shared sequence/compound core).
- **139** classes in the **union**.
- ⇒ ~**87%** of the loaded BioJava surface is workload-specific (e.g. 37 alignment
  classes are loaded by `align-global` but never by `fasta-parse`).

BioJava is a lightweight library, so the absolute class count is small relative
to FOP/batik; the *diversity ratio*, however, is the highest of any candidate —
a single-workload `single-{op}.aot` covers little of the others, while the merged
`tree.aot` (from the per-module test suites) covers the union.

---

## Dependency Map

| Artifact | Version | Role | Cache source | Submodule path |
|---|---|---|---|---|
| `org.biojava:biojava-core` | 7.2.5 | Sequences, compounds, FASTA/GenBank I/O, transcription | `mvn test -P tree-merge` (log4j + JAXB excluded) | `biojava/` (`aotcache-setup-biojava`) |
| `org.biojava:biojava-alignment` | 7.2.5 | Pairwise dynamic-programming aligners + matrices | `mvn test -P tree-merge` (log4j + openchart excluded) | `biojava/` (`aotcache-setup-biojava`) |
| `org.biojava.thirdparty:forester` | 1.039 | Phylogenetics (pulled by alignment; not on the pairwise path) | Custom workload — `mvn test -P tree-merge` in `biojava-deps/forester/` | `biojava-deps/forester/` (local module, no fork — no test suite upstream) |
| `commons-codec:commons-codec` | 1.5 | forester utility dependency | `mvn test -P tree-merge` | `biojava-deps/commons-codec/` (`aotcache-setup`) |
| `org.slf4j:slf4j-api` | 2.x | Logging façade (module-info stripped) | `mvn test -P tree-merge` | `biojava-deps/slf4j/` (`aotcache-setup`, reused from thymeleaf) |


---

## Workloads

| Workload      | What it does | Subtree exercised |
|---------------|--------------|-------------------|
| fasta-parse   | Parse a multi-record FASTA DNA file | `core.sequence.io` FASTA reader |
| genbank-parse | Parse a GenBank record | `core.sequence.io` GenBank reader |
| transcribe    | DNA → RNA → protein | `core.sequence.transcription` engine |
| revcomp-gc    | Reverse complement + GC count over 20 kb | `core.sequence` compound views |
| align-global  | Needleman–Wunsch global protein alignment | `alignment` + BLOSUM62 matrix |
| align-local   | Smith–Waterman local protein alignment | `alignment` + BLOSUM62 matrix |

---

## Running

> Requires a Leyden/AOT-capable JDK (24+/25) for the AOT steps. The benchmark
> compiles and runs on any JDK 11+.

```bash
# 1. Build the fat-jar benchmark (log4j excluded, slf4j-simple bundled)
cd benchmark && mvn package -DskipTests && cd ..

# 2. Record per-dependency cache.aot files (run each from the repo root)

# biojava-core and biojava-alignment — single command, two modules, one fork each
cd biojava/
mvn test -P tree-merge -pl biojava-core,biojava-alignment
cd ..
# → biojava/biojava-core/cache.aot
# → biojava/biojava-alignment/cache.aot

# forester — custom workload (no upstream test suite)
cd biojava-deps/forester/
mvn package
java -XX:AOTCacheOutput=cache.aot -jar target/forester-workload-fat.jar
cd ../..
# → biojava-deps/forester/cache.aot

# commons-codec (forester's dep)
cd biojava-deps/commons-codec/
mvn test -P tree-merge
cd ../..
# → biojava-deps/commons-codec/cache.aot

# slf4j (module-info stripped in the fork; only slf4j-api is needed)
cd biojava-deps/slf4j/
mvn test -P tree-merge -pl slf4j-api
cd ../..
# → biojava-deps/slf4j/slf4j-api/cache.aot

# 3. AOTCache baseline: one single-{op}.aot per workload
./create-single-aot.sh

# 4. TreeCache: merge all cache.aot files into tree.aot
./orchestrate-combine.sh

# 5. Timed comparison (no-AOT vs AOTCache cross-workload vs TreeCache)
RUNS=30 ./workload-timed.sh
```
