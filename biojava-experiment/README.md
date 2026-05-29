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

## Empirical workload diversity

> The class-load counts below were measured on the original 6-workload set.
> They are kept for reference but do not reflect the current 7-workload set
> (`genbank-parse` and `align-local` removed; `codon-usage`, `genbank-write`,
> `msa` added). Re-measure with `-Xlog:class+load` after updating.

BioJava (`org.biojava.*`) classes loaded per workload (old set, JDK 21, `-Xlog:class+load`):

| Workload      | BioJava classes | Module |
|---------------|-----------------|--------|
| fasta-parse   | 35  | biojava-core (FASTA reader) |
| genbank-parse | 57  | biojava-core (GenBank reader) — *removed* |
| transcribe    | 72  | biojava-core (transcription engine) |
| revcomp-gc    | 29  | biojava-core (compound stats) |
| align-global  | 57  | biojava-alignment (Needleman–Wunsch) |
| align-local   | 54  | biojava-alignment (Smith–Waterman) — *removed* |

- **18** classes were loaded by all six workloads (shared sequence/compound core).
- **139** classes in the union — ~**87%** workload-specific.

BioJava is a lightweight library so absolute counts are small, but the diversity
ratio is the highest of any candidate — a single-workload `single-{op}.aot`
covers little of the others, while the merged `tree.aot` covers the union.

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

| Workload | What it does | Class subtree |
|---|---|---|
| `fasta-parse` | Reads a multi-record FASTA file via `FastaReaderHelper`; sums total sequence length. FASTA is the simplest sequence format: `>header` lines followed by raw nucleotide strings. | `core.sequence.io` — FASTA reader + header parser |
| `transcribe` | Builds a synthetic DNA string, converts it to RNA via `dna.getRNASequence()`, then translates to protein via `rna.getProteinSequence()`. | `core.sequence.transcription` — `DNAToRNATranslator`, `RNAToAminoAcidTranslator`, codon→amino-acid lookup |
| `revcomp-gc` | Builds a 20,000-base random DNA sequence, computes its reverse complement, and counts GC bases. Computationally trivial; cost is almost entirely class loading. | `core.sequence` — sequence-view and complement-operation subtree |
| `align-global` | Pairwise Needleman–Wunsch global alignment of two short protein sequences using the BLOSUM62 substitution matrix. | `alignment` — dynamic-programming aligner, gap-penalty, substitution-matrix |
| `codon-usage` | Loads `IUPACParser`, which reads the IUPAC genetic code tables from an **XML resource file via SAX**. Enumerates all 64 codons of the standard genetic code and counts which amino acid each encodes. The SAX class tree, `IUPACParser`, `Table.Codon`, and `RNACompoundSet` are completely disjoint from the parser and alignment workloads. | `core.sequence.io.IUPACParser` — SAX parser, `Table.Codon`, `RNACompoundSet`, `AminoAcidCompoundSet` |
| `genbank-write` | Reads the GenBank record from disk (reader path), then serialises the same sequences twice to `ByteArrayOutputStream`: once as FASTA via `FastaWriterHelper` and once as GenBank via `GenbankWriterHelper`. The **writer** class subtree (`FastaWriter`, `GenbankWriter`, `GenericFastaHeaderFormat`) is distinct from the reader side used in format-parsing workloads. | `core.sequence.io` — `FastaWriter`, `GenbankWriter`, `GenbankWriterHelper`, `GenericFastaHeaderFormat` |
| `msa` | Progressive multiple sequence alignment of 4 protein sequences via `Alignments.getMultipleSequenceAlignment()`. BioJava builds a guide tree (UPGMA-style), then iteratively aligns profile pairs. Requires `ConcurrencyTools.shutdown()` to prevent JVM hang — BioJava's internal thread pool uses non-daemon threads that outlive the computation. | `alignment` — `GuideTree`, `SimpleProfileProfileAligner`, `FractionalIdentityInProfileScorer`, `AbstractProfileProfileAligner` |

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
