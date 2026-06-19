# OpenNLP CLI — AOT cache experiment plan

## Why this one
Chosen as the **genuine diverse-workload application** (CLI, not a library) after a long
candidate sweep. It has the FOP/commons-compress/biojava property — different workloads
load **disjoint, large class subtrees** — but exposed as a real command-line tool
(`opennlp <Tool> …`), which is what we want over libraries (Tika) and frameworks (Jena).

## Verified facts (2026-06-16)
- **Build:** Apache **Maven**, multi-module. Main branch needs **JDK 21 + Maven 3.9**
  (fine for the Leyden/AOT toolchain); pin a stable release tag for reproducibility.
- **External deps:** **`org.slf4j:slf4j-api` is the *only* external dependency.**
  Everything else is OpenNLP's own modules. Reuse the existing **slf4j fork**
  (strip its MR-JAR `module-info`).
- **Module status:** **Automatic-Module-Name** (`org.apache.opennlp.tools`) — **no
  `module-info.java`** anywhere. Safe.
- **No runtime instrumentation.** Hermetic (no network/DB once models are bundled).
- **CLI entry point:** `opennlp.tools.cmdline.CLI` (declared `mainClass` in
  `opennlp-tools`). Invoked `opennlp <ToolName> <model.bin> < input.txt`.
- **Models:** distributed as **Maven artifacts** (`apache/opennlp-models`,
  `org.apache.opennlp:opennlp-models-*`). Add as deps → bundled, **offline/hermetic**.

## Fork / dependency set (biojava-shaped)
- **Fork `apache/opennlp`** (one repo → modules: `opennlp-api`, `opennlp-runtime`,
  `opennlp-tools`, `opennlp-cli`, `opennlp-formats`, `opennlp-model-resolver`,
  `opennlp-ml-commons`, and ML backends `opennlp-ml-{perceptron,maxent,bayes,libsvm}`).
- **slf4j** — reuse existing fork.
- **Models** — `opennlp-models-*` as Maven deps (bundled fat-jar). Confirm exact
  coordinates + which are mandatory vs trainable from bundled sample data.

## Workloads (each = one `opennlp <Tool>` invocation → disjoint subtree)
| Workload | CLI tool | Model | Workload-specific subtree |
|---|---|---|---|
| `tokenize`   | `TokenizerME`      | en-token       | `opennlp.tools.tokenize` |
| `sentdetect` | `SentenceDetector` | en-sent        | `opennlp.tools.sentdetect` |
| `pos`        | `POSTagger`        | en-pos-*       | `opennlp.tools.postag` |
| `ner`        | `TokenNameFinder`  | en-ner-*       | `opennlp.tools.namefind` |
| `chunk`      | `Chunker`          | en-chunker     | `opennlp.tools.chunker` |
| `parse`      | `Parser`           | en-parser      | `opennlp.tools.parser` (largest) |
| `lemmatize`  | `LemmatizerME`     | en-lemma       | `opennlp.tools.lemmatizer` |
| `doccat`     | `DoccatTool`       | trained/sample | `opennlp.tools.doccat` |

- **Shared intersection (kept small):** `opennlp-api` / `-runtime` / `-ml-commons` +
  the ME model deserialization path. Everything else is per-task.
- **Secondary divergence axis:** different models use different **ML backends**
  (perceptron vs maxent vs bayes) → extra disjoint `opennlp.ml.*` subtrees.
- **Expectation:** high workload-specific fraction (biojava measured ~87% of the union
  was workload-specific) → strong TreeCache margin.

## Measurement protocol (repo standard)
1. Per-workload: run each tool under `-XX:AOTCacheOutput=<tool>.aot`.
2. `aotp --list-classes` each cache → sorted SBOMs; compute pairwise/union/intersection.
3. Build `tree.aot` from the OpenNLP modules' **test suites**; compare TreeCache vs a
   monolithic single-workload cache across all tools.

## Open items to confirm when scaffolding
- Stable release tag to pin (latest 2.5.x line) + JDK pin.
- Exact `opennlp-models-*` coordinates; whether the `Parser` model is published
  (en-parser-chunking is large) or skip `parse`.
- Whether `opennlp-cli` is a separate jar or folded into `opennlp-tools` for the run.
