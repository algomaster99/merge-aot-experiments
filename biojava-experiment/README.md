# BioJava AOT Cache Experiment

This experiment measures the startup-time impact of AOT class-data caches across
bioinformatics workloads that load **disjoint** algorithm/parser subtrees on a
shared sequence/compound core — the profile where a merged TreeCache beats a
single monolithic AOTCache.

BioJava comes from the DaCapo 2025 suite. It was previously deferred over a
`module-info` risk; this experiment documents and applies the mitigation.

---

## The module-info mitigation

`biojava-core` and `biojava-alignment` declare a **log4j** binding
(`log4j-slf4j2-impl` + `log4j-api` + `log4j-core`) and `jakarta.xml.bind` /
`jaxb-runtime` as compile-scope dependencies. Both `log4j-core` and
`jaxb-runtime` ship `module-info` (the same blocker that rejected Log4j2), which
breaks AOT cache creation when present on the classpath.

Mitigation, applied in `benchmark/pom.xml`:

1. **BioJava logs only through `slf4j-api`** — no direct `org.apache.logging.log4j`
   use exists in any BioJava module's main source (verified). The log4j binding
   is therefore swappable: it is **excluded** and replaced with `slf4j-simple`.
2. **JAXB is never referenced** in any BioJava module's main source (verified),
   so `jakarta.xml.bind-api` and `jaxb-runtime` are **excluded** as unused.
3. **`forester`** (pulled by `biojava-alignment` for phylogenetics) drags in
   `openchart` from a dead JBoss repo; `openchart` is **excluded** (only the
   phylo/MSA code paths use it — pairwise alignment does not). `forester 1.039`
   itself has **no** `module-info` (verified).

After mitigation the only `module-info`-bearing JARs left are **slf4j-api** /
**slf4j-simple**, which the existing **slf4j fork** (reused from the thymeleaf
experiment) already strips. The BioJava library classes themselves are clean.

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

| Artifact | Version | Role | Cache source |
|---|---|---|---|
| `org.biojava:biojava-core` | 7.2.5 | Sequences, compounds, FASTA/GenBank I/O, transcription | Test suite — `mvn test -P tree-merge` (log4j excluded) |
| `org.biojava:biojava-alignment` | 7.2.5 | Pairwise dynamic-programming aligners + matrices | Test suite — `mvn test -P tree-merge` |
| `org.biojava.thirdparty:forester` | 1.039 | Phylogenetics (pulled by alignment; not on the pairwise path) | Custom workload (no usable test suite; no module-info) |
| `commons-codec:commons-codec` | 1.5 | forester utility dependency | Test suite — reuse commons-codec fork |
| `org.slf4j:slf4j-api` | 2.x | Logging façade | Reuse slf4j fork (module-info stripped) |

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

# 2. AOTCache baseline: one single-{op}.aot per workload
./create-single-aot.sh

# 3. TreeCache: merge the per-dependency cache.aot files into tree.aot
#    (record the dependency caches first — see orchestrate-combine.sh)
./orchestrate-combine.sh

# 4. Timed comparison (no-AOT vs AOTCache cross-workload vs TreeCache)
RUNS=30 ./workload-timed.sh
```
