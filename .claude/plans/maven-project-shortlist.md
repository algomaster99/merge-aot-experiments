# Maven Project Shortlist

## Goal

Pick Maven-based projects for AOT/cache experiments.  
Constraints: Maven only, JDK > 5, no `module-info.java` (source or MR-JAR) anywhere in project or transitive deps, no instrumentation (no AspectJ/ByteBuddy/Javassist used at runtime).

> Note: `Automatic-Module-Name` in MANIFEST.MF is **not** a module descriptor — it does not trigger JPMS resolution and is safe.

---

## Verified Candidates

### 1. Thymeleaf 3.1.5.RELEASE
- **Repo:** thymeleaf/thymeleaf (tag `thymeleaf-3.1.5.RELEASE`)
- **Build:** Maven, Java 8 source/target
- **module-info:** Only `slf4j-api:2.0.17` (MR-JAR, dep JAR — strip before recording); Thymeleaf JAR itself is clean
- **Instrumentation:** OGNL pulls in `javassist:3.29.0-GA` for runtime bytecode generation — exclude Javassist from classpath; OGNL falls back to reflection
- **Dep tree (compile):** `ognl:3.3.4`, `attoparser:2.0.7.RELEASE`, `unbescape:1.1.6.RELEASE`, `slf4j-api:2.0.17`
- **Workload ideas:**
  - HTML templates with `th:each` / `th:if` iteration and conditionals
  - Fragment inclusion (`th:replace`, `th:insert`)
  - Inline expressions (`[[...]]`, `[(...)]`)
  - Text-mode templates (non-HTML)
- **Notes:** Template compilation is cold per unique template. Each workload loads different processor class subtrees.

### 2. Apache Velocity Engine 2.3
- **Repo:** apache/velocity-engine
- **Build:** Maven
- **module-info:** None found in source tree or published JARs
- **Instrumentation:** None
- **Dep tree:** slf4j-api + binding, commons-lang3, commons-collections4 — all pre-JPMS
- **Workload idea:** Render a set of Velocity templates (`.vm` files) covering loops, macros, and conditionals
- **Notes:** Template rendering is hermetic (no network). Medium dep tree overlaps somewhat with commons-configuration.

---

## Rejected / Deferred

| Project | Reason |
|---------|--------|
| `jetty` | `module-info.java` + `--patch-module` required; AOT dump incompatible |
| `gson`, `jackson-*` | Self-contained / no compile-scope dep tree; JPMS/module descriptors in newer jackson versions |
| Apache POI 4.1.x | MR-JAR embeds `module-info.class` in `META-INF/versions/9`; XmlBeans dep also has JPMS descriptors |
| jsoup | Only dep is `jspecify` (annotation-only, zero runtime classes); `com.google.re2j` added in 1.22.2 but declared optional — no mandatory runtime deps to distribute |
| packageurl-java 1.5.0 | Build fails: `bad class file: wrong version 69.0, should be 53.0` — JDK mismatch, not fixable without downgrading |
| picocli 4.7.7 | Gradle build system; Gradle itself fails with `Unsupported class file major version 69` |
| dagger | Gradle build system; Gradle version parsing fails |
| Commons Math (3.6.1 / 4.0-beta1) | 3.6.1 has zero deps (low AOT benefit); 4.0-beta1 adds commons-numbers-core but still low value — dropped |
| HttpClient5 5.6.1 | HTTP/1.1 vs HTTP/2 is the only class-level split (two workloads); all other paths (TLS, auth, multipart) get JIT-compiled at runtime — insufficient workload diversity |
| Guava 33.6.0-jre | All transitive compile deps are annotations only — effectively zero real dep tree, low AOT benefit |
| FreeMarker 2.3.x | Gradle build system |
| Mozilla Rhino 1.7.x | Gradle build system |
| Apache POI 5.5.1 | Gradle build system |
| Apache Xerces2 | Ant build system |
| MyBatis 3.5.x | No compile-scope transitive deps — self-contained, low AOT benefit |
| H2 Database 2.4.x | No compile-scope transitive deps — self-contained, low AOT benefit |
| JaCoP 4.10.0 | `scala-library` + `scala-compiler` as compile deps (heavy, JPMS risk); constraint propagation gets JIT-hot quickly — thin cold surface |
| Handlebars.java 4.5.1 | `module-info.class` in the main handlebars JAR itself |
| Woodstox 5.4.x | `module-info.java` injected via moditect into published JAR |
| Log4j2 2.17.x | MR-JAR `module-info` present since 2.10 in both log4j-api and log4j-core |
| XStream 1.4.21 | Dep `mxparser` compiles to Java 1.4 bytecode — AOT recorder skips its classes entirely; `aotp --list-classes` on `mxparser/cache.aot` returned only `MXParserTest`, no library classes |

---

---

## Candidates from JACT thesis dataset (Sävås 2025, KTH)

30 Maven open-source projects evaluated. Constraint: **< 6 total runtime deps** (direct + indirect combined) since each dep must be built manually. poi-tl already rejected (Apache POI). Projects below are filtered on that constraint and ranked by workload diversity.

### Passed constraint (< 6 total runtime deps)

| Project | Direct | Indirect | Total | Workload diversity |
|---------|--------|----------|-------|--------------------|
| tika-core | 2 | 0 | 2 | **Excellent** — parsing PDF vs DOCX vs HTML vs images loads completely independent parser class hierarchies; single-workload cache is essentially useless on other formats |
| pf4j | 3 | 0 | 3 | Low — plugin lifecycle operations share most classes |
| commons-validator | 4 | 0 | 4 | **Good** — email, URL, IP address, credit card, date, ISBN validators each use distinct regex/parse class subtrees |
| java-faker | 3 | 1 | 4 | Medium — data categories (name, address, number, lorem) share most infrastructure |
| pdfbox | 4 | 1 | 5 | **Good** — already in experiment |
| undertow | 4 | 2 | 6 | **Good** — different handler types (static files, servlet, WebSocket, HTTP/2) load distinct handler class trees; but uses `xnio` which may have module issues |

### Top picks (not yet in experiment or rejected list)

**1. commons-validator** — best combination of feasibility and workload diversity within the constraint. Validators for email, URL, IP, credit card, ISBN, and date each invoke different parsing/regex subtrees. All deps are pre-JPMS Apache Commons libraries — high confidence no `module-info`.

**2. tika-core** — exceptional workload divergence (each file type loads a separate parser), but very thin dep tree (2 deps). Worth testing if the AOT benefit from 2 deps is still measurable.

**3. undertow** — if workload diversity is the priority, HTTP static-file vs servlet vs WebSocket handlers differ substantially. But needs module-info check on `xnio-api` and `jboss-logging`.

### Filtered out (too many deps)
| Project | Total deps | Reason |
|---------|-----------|--------|
| graphhopper | 20 | Too many deps to build manually |
| Recaf | 56 | Too many deps |
| lettuce | 44 | Too many deps; also needs Redis server at test time |
| Chronicle-Map | 34 | Too many deps |
| OpenPDF | 36 | Too many deps |
| mybatis-3 | 8 | Too many; also needs DB at test time |
| jimfs | 9 | Too many |

---

## Decision Queue

- [ ] Confirm commons-validator as next experiment (best workload diversity within dep constraint)
- [ ] Verify: no `module-info` in commons-validator dep tree (commons-lang3, commons-beanutils, commons-collections4, commons-digester)
- [ ] Investigate tika-core as secondary candidate if commons-validator has low AOT benefit
- [ ] Check `xnio-api` for `module-info` if undertow is considered
- [ ] Drop Velocity 2.3 if commons-validator clears verification (similar dep domain)

---
---

## DaCapo Chopin (ASPLOS 2025) + sbom.exe rq3/rq4 audit

Source projects from Blackburn et al., *Rethinking Java Performance Analysis*
(DaCapo 23.11-chopin, ASPLOS 2025) and the audited application set in
`chains-project/exploits-for-sbom.exe/rq3_rq4`. Each candidate was checked
against the standard filters: **Maven** (no Gradle/Ant), **no `module-info.java`**
in source or transitive deps, **no runtime instrumentation**, **hermetic**
(no network/DB/server), and a **non-trivial but buildable dep tree**.

### Full DaCapo Chopin verdict table (22 benchmarks)

| Benchmark | Underlying lib/app | Build | Verdict |
|---|---|---|---|
| **batik** | Apache Batik (SVG) | Maven | ✅ **DONE** (existing experiment) |
| **pdfbox** *(via fop/sbom)* | Apache PDFBox | Maven | ✅ **DONE** (existing experiment) |
| **fop** | Apache FOP (XSL-FO → PDF/PS/PCL/RTF/TXT/PNG) | Maven | ✅ **IMPLEMENTED — see `fop-experiment/`** |
| biojava | BioJava (bioinformatics) | Maven | ✅ **IMPLEMENTED — see `biojava-experiment/`** (log4j/jaxb excluded; mitigation applied) |
| pmd | PMD (static analysis) | Maven | ⚠️ Candidate — Saxon-HE 12.9 ships a real `module-info` (blocker unless excluded) |
| zxing | ZXing (barcodes) | Maven | ❌ `core` has **zero** compile deps → no dep tree to distribute (like jsoup/guava) |
| xalan | Apache Xalan-J (XSLT) | Ant | ❌ Ant build (cf. Xerces2) |
| sunflow | Sunflow (ray tracer) | Ant | ❌ Ant build; pulls `janino` (runtime compiler) |
| h2 | H2 Database | Ant/custom | ❌ Self-contained DB, no compile-scope deps (already rejected) |
| avrora | AVR simulator | binary/Ant | ❌ Binary only, pre-Maven, no source build |
| eclipse | Eclipse JDT | (PDE/Tycho) | ❌ OSGi/Equinox + bundle module system |
| graphchi | GraphChi-java | Maven+Scala | ❌ Scala compile failure (cf. JaCoP) |
| jython | Jython | Ant/Gradle | ❌ Build system; generates bytecode at runtime (instrumentation) |
| spring | Spring Boot petclinic | Gradle | ❌ Gradle; cglib/ByteBuddy runtime instrumentation |
| tomcat | Apache Tomcat | Ant | ❌ Server app, Ant, needs network |
| tradebeans/tradesoap | DayTrader on Geronimo | (app server) | ❌ Full Jakarta EE app server |
| luindex/lusearch | Apache Lucene | Gradle | ❌ Gradle; Lucene ships `module-info` |
| kafka | Apache Kafka | Gradle | ❌ Gradle; needs broker |
| cassandra | Apache Cassandra | Ant | ❌ Ant; DB server |
| h2o | H2O ML | Gradle | ❌ Gradle |
| jme | jMonkeyEngine | Gradle | ❌ Gradle |

### sbom.exe rq3/rq4 extras (not already covered above)

| Project | Build | Verdict |
|---|---|---|
| graphhopper | Maven | ⏸️ Deferred — ~20 deps to fork manually; needs OSM data files at runtime |
| ttorrent | Maven | ❌ BitTorrent — network/peers required, thin workload diversity |

---

## New verified candidate: Apache FOP — IMPLEMENTED

**Status:** scaffolded in `fop-experiment/` (benchmark + scripts + README),
benchmark compiled and all six workloads executed on JDK 21.

- **Repo:** apache/xmlgraphics-fop (release `fop-2.10`)
- **Build:** Maven (Ant deprecated since 2.2). **No `module-info.java`** in source.
- **Runtime deps (compile scope of fop-core 2.10):** batik 1.18 (anim, awt-util,
  bridge, extension, gvt, transcoder, codec), xmlgraphics-commons 2.10,
  commons-io 2.11.0, commons-logging 1.3.0, fontbox, fop-events, fop-util.
  `pdfbox`, `xalan`, `jai`, `bouncycastle`, `ant`, servlet-api are `provided`/`test`
  → **not** on the runtime classpath.
- **Fork reuse:** the dep tree is the union of the existing **batik** and **pdfbox**
  experiments' forks (batik, xmlgraphics-commons, commons-io, commons-logging,
  fontbox). Only fop-core/events/util are new — low setup cost.
- **Workloads (6):** `fo-to-pdf`, `fo-to-ps`, `fo-to-pcl`, `fo-to-rtf`,
  `fo-to-txt`, `fo-to-png` — same FO document, different renderer subtree.
- **Why TreeCache should win (measured):** 808 classes shared by all six
  workloads, **1612** in the union — ~50% of the loaded library surface is
  workload-specific (~200 disjoint `render.*` classes per format). A monolithic
  single-workload cache misses the other renderers; the merged `tree.aot` (from
  dep test suites) covers the union. This is the same divergence that produced
  TreeCache's biggest margin in batik (1.61x vs 1.23x).

## Secondary candidates (need module-info mitigation)

### biojava 7.2.5 — IMPLEMENTED (mitigation confirmed)
- **Build:** Maven. No `module-info.java` in source.
- **Diversity:** highest ratio of any candidate — only **18** classes shared by
  all six workloads vs **139** in the union (~87% workload-specific), measured on
  JDK 21. Absolute counts are small (lightweight library).
- **Blocker → resolved:** `biojava-core`/`-alignment` declared `log4j-core`
  (MR-JAR `module-info`) and `jaxb-runtime` (`module-info`). Confirmed via
  `git grep` that BioJava logs **only** through `slf4j-api` and **never**
  references JAXB in main source ⇒ both excluded; `slf4j-simple` provides the
  binding. `forester 1.039` (alignment's phylo dep) has no `module-info`; its
  dead `openchart` transitive dep is excluded (not on the pairwise path).
  Remaining `module-info` JARs are slf4j-api/-simple, stripped by the existing
  slf4j fork. **Benchmark compiles and all six workloads run on JDK 21.**
- **Forks needed:** biojava (one fork → core + alignment modules), forester
  (custom workload), commons-codec (reuse), slf4j (reuse). See
  `biojava-experiment/README.md` and `.github/workflows/biojava-aot-cache.yml`.

### pmd 7.x
- **Build:** Maven. No real `module-info.java` (only a test fixture).
- **Diversity:** different rulesets (best-practices/design/errorprone/performance)
  and languages (Java/JS/XML) load distinct rule + parser subtrees.
- **Dep tree:** slf4j-api, antlr4-runtime, commons-lang3, asm, gson, pcollections,
  nice-xml-messages — a healthy distributable tree.
- **Blocker:** `Saxon-HE 12.9` (used for XPath rules, core to PMD) ships a real
  `module-info.class`. Unless Saxon can be excluded (it largely cannot for XPath
  rules), pmd is blocked — same class of issue as Woodstox/Log4j2.

---
---

## GitHub "java application" sweep (2026-06-08) — candidates to vet

Sourced by web-searching GitHub for Maven Java libraries/apps and filtering on
the standard constraints (Maven, JDK > 5, no `module-info.java` in project or
transitive deps incl. MR-JARs, no runtime instrumentation, hermetic, small but
non-trivial dep tree, high workload diversity). Preliminary checks below; **all
need final vetting** (build a fork, `aotp --list-classes` sanity check).

### Strong candidates

#### 1. Apache Commons Imaging ⭐ (top new pick)
- **Repo:** apache/commons-imaging (latest `1.0.0-alpha6` / master)
- **Build:** Maven, Java 8 source/target. **Verified clean:** only
  `Automatic-Module-Name` (safe), no `module-info`.
- **Deps (compile):** `commons-io 2.22.0`, `commons-lang3 3.20.0` — **both already
  forked** in the fop/pdfbox experiments (neither ships `module-info`, only
  Automatic-Module-Name). Near-zero new setup cost.
- **Diversity: excellent.** Pure-Java codecs for PNG, GIF, BMP, TIFF, JPEG, ICO,
  PCX, PNM, PSD, RGBE, WBMP, XBM, XPM, DCX — each format is a disjoint
  reader/writer class subtree. This is the **image analogue of commons-compress**
  (which already showed strong TreeCache margins on format divergence).
- **Workloads (proposed):** decode + re-encode one image per format
  (`png`, `gif`, `bmp`, `tiff`, `jpeg`, `pnm`, `psd`, …) → each loads a separate
  `org.apache.commons.imaging.formats.*` tree; merged `tree.aot` covers the union.
- **Caveat to vet:** dep tree is thin (2 deps, both already owned) — but format
  diversity is the highest-value axis, so worth it. Confirm AOT benefit is
  measurable with such a small distributable tree (cf. tika-core caveat).

#### 2. JGraphT (jgrapht-core)
- **Repo:** jgrapht/jgrapht (`jgrapht-core`, latest `1.5.x`)
- **Build:** Maven, Java 8.
- **Deps (compile):** `org.jheaps:jheaps` (verified clean — no deps,
  Automatic-Module-Name only, Java 8) and **`org.apfloat:apfloat` (⚠️ BLOCKER RISK
  — modern apfloat is modularized / likely ships `module-info`; needs verification
  and possible exclusion).** apfloat is only used by a subset of algorithms, so an
  exclusion may be viable.
- **Diversity: good.** Distinct algorithm packages — shortest path
  (Dijkstra/BellmanFord/A*/Johnson), max-flow, matching, graph coloring, spanning
  tree, connectivity/cycle detection, clustering — each a separate `alg.*` subtree.
- **Caveat to vet:** graph algorithms can become JIT-hot quickly (cf. JaCoP
  rejection), but the cold class surface across distinct `alg.*` packages is large.
  Resolve the apfloat `module-info` question first.

#### 3. OpenCSV
- **Repo:** opencsv (SourceForge/Bitbucket; published as `com.opencsv:opencsv`)
- **Build:** Maven. Deps are all pre-JPMS Apache Commons → **no `module-info`
  expected** (verify): `commons-lang3`, `commons-text`, `commons-beanutils`,
  `commons-collections4` (+ transitive `commons-collections 3.2.2`,
  `commons-logging`) — a healthy 4–6 dep distributable tree.
- **Diversity: moderate.** CSV parse vs write, bean-binding (annotation-driven
  `CsvToBean`/`StatefulBeanToCsv`), custom separators/quoting, MultiValuedMap
  binding — partially overlapping infrastructure.
- **Caveat:** same Apache-commons dep domain as commons-validator; if both are
  taken, dep-tree overlap reduces marginal novelty.

#### 4. Apache Commons VFS2
- **Repo:** apache/commons-vfs (`commons-vfs2`)
- **Build:** Maven. **Required** runtime deps only `commons-logging` +
  `commons-lang3` (most providers — sftp/http/hdfs — are `optional`, off the
  classpath). No `module-info` (pre-JPMS Apache commons).
- **Diversity: moderate.** Hermetic providers each load a distinct
  `provider.*` subtree: `local`, `ram`, `res`, `temp`, plus archive providers
  `zip`/`jar`/`tar`/`gz`/`bz2` (the archive set pulls optional
  `commons-compress` — itself already forked).
- **Caveat:** thin required tree; archive diversity depends on opting commons-compress in.

### Secondary candidate (needs mitigation)

#### openhtmltopdf (Flying Saucer successor)
- **Repo:** openhtmltopdf/openhtmltopdf, Java 8.
- **Build:** Maven. Reuses **PDFBox (already forked)** + `de.rototor.pdfbox:graphics2d`;
  SVG (Batik — also forked) and MathML are pluggable modules.
- **Diversity:** XML/CSS layout → PDF, plus SVG/MathML plugin subtrees.
- **Caveat:** overlaps the pdfbox/fop rendering domain; verify `graphics2d` and the
  SVG plugin carry no `module-info`.

### Rejected from this sweep

| Project | Reason |
|---------|--------|
| commonmark-java | Core has **zero external runtime deps**; extensions depend only on core — same self-contained pattern as jsoup/guava/zxing |
| flexmark-java | Only its own `flexmark-util-*` modules + JetBrains `annotations` (annotation-only) → effectively zero external runtime deps |
| Apache Santuario (xmlsec) | Ships its **own** `module-info` **and** depends on `woodstox-core` (also `module-info`) — double blocker (cf. Woodstox/Saxon) |

### Runnable applications (CLI tools, not libraries) — **lean only**

> All existing experiments (batik, pdfbox, fop, thymeleaf, biojava, commons-*) are
> libraries driven by a benchmark harness. opencsv / commons-imaging above are also
> libraries. This subsection collects genuine **end-user CLI applications** (the
> category graphhopper belongs to).
>
> **Decision (user, 2026-06-08): keep apps LEAN** — small forkable dep tree
> (≲ 6 deps), fully hermetic, no `module-info`/instrumentation.
>
> ⚠️ **Tension:** "lean" fights the experiment's premise. The TreeCache value comes
> from a *mergeable* dep tree with *divergent* class subtrees, so a 0–1-dep app
> gives almost nothing to merge. The narrow intersection — a small *non-zero* dep
> tree **plus** real workload divergence — is **barely met by any lean app**. After
> Closure Compiler turned out to be Bazel (see rejected table), the only remaining
> Maven candidate is the ANTLR4 tool, and it's only lean if icu4j is tolerated.

#### A. ANTLR4 tool — lead remaining candidate (borderline-lean)
- **Repo:** antlr/antlr4 (`tool/`). **App:** grammar → parser code generator CLI.
- **Build:** Maven (needs Maven 3.8+).
- **Deps:** `antlr4-runtime`, `antlr-runtime 3.5.3`, `ST4 4.3.4`,
  `treelayout 1.0.3`, **`icu4j 72.1`** (⚠️ ~13 MB — **not lean**; heavy to fork
  manually; verify it carries only Automatic-Module-Name, not `module-info`).
- **Diversity: good.** Code-gen targets (Java / C# / Python / JS / Go / Swift) each
  load distinct StringTemplate + target subtrees. Hermetic (reads `.g4` grammars).
- **Verdict:** the only lean-ish Maven app left; viable only if the lean bar is
  relaxed for the single heavy dep (icu4j).

#### Evaluated and rejected for the lean bar
| App | Reason |
|-----|--------|
| **Google Closure Compiler** | **Bazel build** (`BUILD.bazel` at repo root; no buildable `pom-main.xml` on master — the `maven/*.pom.xml` files are packaging templates Bazel publishes to Maven Central). Build-system blocker, same class as Gradle/Ant rejections. *(Originally listed as Maven in error — corrected after user flagged it.)* |
| graphhopper | (1) ~20 runtime deps — too many to fork manually; (2) **needs OpenStreetMap data files at runtime** → not hermetic. (per git history) |
| Checkstyle | `Saxon-HE` (`module-info`) **and** `javassist` (runtime instrumentation) — double blocker (cf. PMD + Thymeleaf) |
| PlantUML | Monolithic shaded jar → **no distributable external dep tree** (jsoup pattern); GPL |
| CFR / Procyon | Decompilers with **zero (CFR) / near-zero (Procyon) external deps** → nothing to merge (jsoup pattern) |
| google-java-format | Lean deps (guava) but **low workload diversity** (formatting is one mode) **and** needs `--add-exports` for JDK-internal `com.sun.tools.javac` on JDK 16+ |
| Eclipse JGit (pgm) | OSGi bundles + JPMS schemas (`module-info` risk) and `JSch` (network) — not clean-lean |
| Spoon (INRIA) | Research-relevant, but dominated by `org.eclipse.jdt.core` (~10 MB OSGi bundle) — **not lean**; deferred unless the bar is relaxed |
| Soot | Chains-project-relevant (Jimple/Baf/Grimp IR diversity) but ~6–8 deps (heros, jasmin, asm, axml…) — **over the lean budget**; deferred |

#### User-suggested projects (2026-06-09) — all rejected
| Project | Build | Verdict |
|---|---|---|
| BuildCLI/BuildCLI | Maven, Java 21 | ❌ **Not hermetic.** Lean deps (slf4j/logback/picocli), but it's an orchestrator — each command shells out to external `mvn`/`docker`/`git` (and AI/network for doc-gen). The in-JVM surface per command is thin (picocli dispatch + file templating + `ProcessBuilder`); the real work runs in external processes AOT can't capture → almost no cold class divergence. |
| scouter-project/scouter | Gradle | ❌ **Triple blocker.** (1) Gradle build; (2) it's an APM **Java agent doing bytecode instrumentation** via ASM/BCI — the exact thing the no-instrumentation rule forbids; (3) agent + collector-server + RCP viewer → network/server, not hermetic. |
| TomerAberbach/mano-simulator | Maven, Java 18 | ❌ **JavaFX app.** All deps are `org.openjfx:javafx-*` 19.0.2.1 — genuine JPMS modules that **ship `module-info`** (hard blocker); GUI-only entry point (`SuperMain`, no headless CLI) → not hermetic/headless; and the simulator is a toy (two-pass assembler + ~25-instruction interpreter loop) → tiny class surface, JIT-hot, no diversity. |

#### Swept sources that yielded nothing (don't re-tread)
- **`github.com/topics/java-applications` (top by forks, 2026-06-15):** all 14 top
  results are awesome-lists (useful-java-links), build/packaging plugins
  (JavaPackager, easypack, HaikuVMPlugin), Swing GUI educational viz (CADApps), or
  toy/student/training repos (KBC, Bank-Demo, Quiz, TicTacToe, core-java-training…).
  Zero hermetic, dep-bearing, divergent candidates. The topic is loosely applied —
  better mined via specific format/parser libraries than the generic topic tag.

---
---

## Format-divergence library sweep (2026-06-15)

Pivoted back to the pattern that actually wins (format/codec/parser divergence with
a real mergeable tree), since every "application" lead failed structurally.

### Strong new candidates

#### TwelveMonkeys ImageIO ⭐⭐ (best new find)
- **Repo:** haraldk/TwelveMonkeys. **Build:** Maven, Java 8. **Verified clean:**
  `Automatic-Module-Name` only (`${project.jpms.module.name}` via maven-jar-plugin),
  **no `module-info.java`**; parent POM declares **no third-party runtime deps**.
- **Structure = the mergeable tree:** a multi-module suite — `common-lang`,
  `common-io`, `common-image`, `imageio-core`, `imageio-metadata`, plus **one Maven
  module per image format** (`imageio-jpeg`, `imageio-tiff`, `imageio-psd`,
  `imageio-bmp`, `imageio-pnm`, `imageio-pict`, `imageio-icns`, `imageio-pcx`,
  `imageio-sgi`, `imageio-iff`, `imageio-tga`, `imageio-thumbsdb`, `imageio-hdr`,
  `imageio-webp`, …). Same one-fork-many-modules shape as biojava, each plugin with
  its own test suite to feed `tree.aot`.
- **Diversity: excellent.** Decoding JPEG vs TIFF vs PSD vs WebP vs PICT loads
  **completely disjoint** `com.twelvemonkeys.imageio.plugins.*` subtrees — the image
  analogue of commons-compress, but with the formats already split into separate
  modules. Hermetic (reads image files).
- **Verdict:** top priority to vet — arguably stronger than commons-imaging
  (richer per-format module tree, more formats).

#### metadata-extractor
- **Repo:** drewnoakes/metadata-extractor. **Build:** Maven (has `pom.xml`; also a
  `build.gradle`). Java 8.
- **Deps:** one external — `com.adobe.xmp:xmpcore:6.1.11` (verify it + the lib carry
  only Automatic-Module-Name, not `module-info` — low risk).
- **Diversity: good.** Reads Exif/IPTC/XMP/ICC from JPEG, TIFF, PNG, WebP, HEIF,
  PSD, BMP, GIF, ICO, PCX, and camera-RAW — each format has its own
  `com.drew.metadata.*` / `com.drew.imaging.*` reader subtree. Hermetic.
- **Caveat:** thin external tree (1 dep, like commons-imaging) — but per-format
  reader divergence is the value.

### Rejected / deferred from this sweep
| Project | Verdict |
|---|---|
| JFreeChart 1.5.x | Automatic-Module (safe), but **zero external deps** since JCommon was removed — self-contained → nothing to merge (jsoup/guava pattern). Chart-type diversity wasted. |
| dom4j / JDOM2 | Real but **heavy/ancient** tree (`jaxen` → `xalan`, plus `xerces`); only moderate DOM/SAX/XPath/XSLT diversity — deferred below the image candidates. |
| Apache OpenNLP | ⏸️ Candidate worth a look: multi-module (`opennlp-tools`/`-runtime`/`-ml-maxent`) + per-task **model** artifacts; task diversity (tokenize / sentence / POS / NER / chunk / lemmatize / parse). Needs `module-info` check and confirmation that required models ship as bundlable Maven artifacts (data files, not network). |

### Second sweep (2026-06-15) — crypto / JOSE / office / AST / serialization

#### Bouncy Castle (bc-java) — strong divergence, but recording-host caveat
- **Modules (the mergeable tree):** `bcprov` (crypto/JCE), `bcutil` (ASN.1),
  `bcpkix` (X.509/CMS/PKIX/OCSP/CMP), `bcpg` (OpenPGP), `bctls` (TLS 1.0–1.3),
  `bcmail` (S/MIME) — `-jdk18on`, Java 8, **Automatic-Module-Name** (no `module-info`).
  Inter-module deps only (biojava/TwelveMonkeys shape).
- **Diversity: excellent.** crypto vs PKIX/certs vs OpenPGP vs TLS vs S/MIME are
  largely disjoint `org.bouncycastle.*` subtrees.
- **⚠️ Recording-host blocker (already proven in this repo):** bc-java's upstream
  build is **Gradle with `test { forkEvery = 1 }`**; HotSpot's AOT recorder can't
  archive classes loaded by Gradle's test-worker **child** classloader, so the dep
  test-suite path yields a `cache.aot` with **zero** `org/bouncycastle/*` classes
  (see `pdfbox-experiment/pdfbox-deps/bc-java-prov-workload/README.md`). The
  workaround is a **hand-written synthetic fat-jar workload per module** that drives
  the published jar's public API under `-XX:AOTCacheOutput`.
- **Status / cost:** `bcprov`, `bcpkix`, `bcutil` workloads **already exist** under
  `pdfbox-deps`. A standalone crypto-divergence experiment would hand-author
  `bcpg`/`bctls`/`bcmail` workloads (bctls needs a loopback/test-vector peer).
  Feasible but manual — does **not** get the automatic "merge the deps' test suites"
  benefit. (This is also the general reason Gradle projects are blocked.)

#### Nimbus JOSE+JWT — lean, algorithm divergence
- **Repo:** `com.nimbusds:nimbus-jose-jwt`. Maven, Java 7+.
- **Diversity: good.** JWS/JWE algorithm families (RSASSA, ECDSA, HMAC, AES-GCM,
  AES-CBC-HMAC, ECDH-ES, PBES2) map to distinct handler/provider classes.
- **⚠️ Dep caveat:** `json-smart` → `accessors-smart` → **ASM** (runtime bytecode
  generation for bean accessors) — an instrumentation flag to verify (may not be
  triggered for JOSE parsing, or excludable). Otherwise a lean (~2-dep) hermetic tree.

#### Rejected from second sweep
| Project | Verdict |
|---|---|
| JavaParser | `javaparser-core` is **zero-dep** (jsoup pattern); `javaparser-symbol-solver-core` pulls **`javassist`** (runtime instrumentation — the exact dep excluded in Thymeleaf) + guava → blocked either way. |
| Apache Avro | Depends on **Jackson** (`module-info` in fasterxml ≥ 2.12) + commons-compress + slf4j — same `module-info` blocker as the rejected jackson family. |
| jOpenDocument | ⏸️ ODF doc-type diversity (text/spreadsheet + PDF export), but old SourceForge project — Maven-**published** yet source build/deps unverified. If pursuing ODF, prefer **`odftoolkit/odfdom`** (Apache, Maven). Deferred pending build + `module-info` check. |

---

## Third sweep — APPLICATION-focused (2026-06-16)

> User re-emphasised **applications, not libraries.** Hard reality reconfirmed:
> almost every real app fails on the same axes — non-Maven build (Ant/Gradle/Bazel),
> runtime instrumentation, `module-info` deps, zero dep tree, or non-hermetic. Net
> result: the **only two surviving Maven application candidates are Apache OpenNLP
> CLI and the ANTLR4 tool.**

#### Apache OpenNLP (opennlp-cli) ⭐ — best surviving application
- **Repo:** apache/opennlp. **Build:** **Maven**, multi-module (main branch: JDK 21 +
  Maven 3.9). The `opennlp-cli` module is the runnable CLI app (train / evaluate /
  run); `opennlp-tools` is the engine; `opennlp-model-resolver` fetches models.
- **Diversity: excellent (app-level).** Distinct NLP tasks — tokenize, sentence
  detect, POS, lemmatize, chunk, **NER**, parse — each load disjoint
  `opennlp.tools.{tokenize,postag,namefind,parser,…}` subtrees. App-level analogue of
  FOP renderers / Tika parsers.
- **Mergeable tree:** its own multi-module set (opennlp-tools/-cli/-formats/-model-resolver)
  + per-task **model** artifacts shipped as Maven jars (data, **bundlable → hermetic**,
  no network at runtime).
- **Verify before building:** (1) `module-info` status on opennlp-tools/-cli (newer
  Apache projects sometimes add one — historically only Automatic-Module-Name);
  (2) the external dep tree of opennlp-tools (slf4j + ?); (3) which models are
  mandatory vs trainable from bundled sample data.

#### ANTLR4 tool — second surviving application
- See "Runnable applications" above. Maven, codegen-target + grammar-feature
  diversity; only blemish is the heavy `icu4j` fork. Recommend a quick
  intersection/union probe before committing (its class-level divergence is modest).

#### Rejected from this app sweep
| App | Verdict |
|-----|---------|
| Stanford CoreNLP | **Ant + Ivy build** (`cd CoreNLP; ant`) — Maven jar is only a published output. Build-system blocker (cf. Xalan/Xerces). *Painful loss:* its annotator diversity (tokenize/POS/NER/parse/coref/sentiment) is the best of any app. |
| Soot | Carries **`javassist` at runtime scope** (bytecode instrumentation blocker) on top of a heavy ~8-dep tree (asm*, dexlib2, heros, jasmin, axml, commons-io, slf4j). |
| Apache Tika (tika-app) | Best format diversity of any app, but the runnable app bundles **POI (MR-JAR `module-info`)** + dozens of parser deps → `module-info` blocker + huge tree. A curated subset collapses back to the existing **tika-core** library candidate. |
| JavaCC | A parser-generator app, but generates **zero-runtime-dep** code and is itself **self-contained** → nothing to merge (jsoup pattern). |

#### User-suggested (2026-06-16): tinystruct/tinystruct — rejected
**What it is:** a lightweight modular Java web/CLI framework (Maven, Java 17, no own
`module-info`, no direct instrumentation). The shell looks fine; the **mandatory
dep tree sinks it.** All 12 non-test deps are compile-scope (none `optional`/`provided`):

| Dep | Problem |
|---|---|
| `jakarta.activation-api:2.1.4`, `com.sun.mail:jakarta.mail:2.0.2` | Jakarta API jars **ship real `module-info`** → hard blocker (cf. jetty/POI); mail also needs an SMTP/IMAP server |
| `org.apache.kafka:kafka-clients:4.3.0` | Needs a **Kafka broker** → not hermetic (kafka already rejected) |
| `io.lettuce:lettuce-core:7.6.0` | Redis client → needs **Redis server**; pulls Netty + Reactor (heavy) (lettuce already rejected: "44 deps; needs Redis") |
| `com.h2database:h2:2.4.240`, `org.xerial:sqlite-jdbc` | **Databases**; H2 already rejected; sqlite-jdbc bundles **native JNI** libs |
| `net.java.dev.jna:jna:5.18.1` | **Native/JNI** code |
| `org.openjdk.nashorn:nashorn-core:15.7` | JS engine that **generates JVM bytecode at runtime** (pulls ASM) — instrumentation-class concern |
| `com.google.zxing:core`, `io.jsonwebtoken:jjwt-*`, `org.brotli:dec` | The only benign ones |

**Verdict:** ❌ multiple independent hard blockers — `module-info` deps (jakarta.*),
**non-hermetic** core deps (Kafka/Redis/mail/DB), native JNI (jna/sqlite), and
runtime bytecode gen (nashorn). It also re-pulls three already-rejected projects
(kafka, lettuce, h2) as *mandatory* deps. A gutted "core-only" fork (drop everything
but zxing/jjwt/brotli) could compile, but that discards the app's real surface and
leaves little diversity — not worth it.

#### User-suggested (2026-06-16): Konloch/bytecode-viewer — rejected (best diversity, unbuildable tree)
**What it is:** a Swing-GUI Java/Android reverse-engineering suite. **Maven**, Java 8,
maven-shade fat jar — the build shell is fine.
- **Diversity: the best we've seen.** Same input class, **6 independent decompiler
  engines** (CFR, Procyon, Fernflower, Krakatau, JADX, JD) + disassemblers/assemblers
  — each a **completely disjoint** engine subtree. The ultimate "same input, different
  backend" shape (stronger than FOP renderers).
- **Why it still fails:**
  1. **50+ compile dependencies** — far beyond hand-forkable (graphhopper died at ~20).
     The experiment forks each dep and merges its *test suite*; you cannot fork/run 50.
  2. **Swing GUI app** (darklaf, jgraphx, rsyntaxtextarea, bined-swing). A headless
     `-i/-o/-t` decompile CLI exists, but most deps are GUI-only and never exercised
     headlessly.
  3. **Non-hermetic / non-Java engines:** Krakatau is **Python** (invoked externally);
     the Android path pulls apktool/smali/dex2jar/JADX (heavy, partly Gradle upstream).
  4. **The diversity doesn't convert:** the engines are individually **zero-/near-zero-dep**
     (CFR, Procyon, Fernflower — already rejected on the jsoup pattern), so there are no
     dep test suites to merge; BCV only *aggregates* them via an unforkable 50-dep jar.
- **Verdict:** ❌ on dep-count + GUI + external engines. Noted as the most compelling
  *divergence* story — but it's exactly the case where great workload diversity can't
  be realised because the backends have no mergeable dependency tree.

---
---

## "Like pdfbox" sweep (2026-06-16)

Goal: another **document/format toolkit** with pdfbox's good properties — Maven,
modest forkable tree, **operation-level diversity** (extract vs render vs forms vs
sign → disjoint subtrees), hermetic, no `module-info`.

### Candidates
- **iText 5 — `com.itextpdf:itextpdf` 5.5.13.x ⭐ (closest analogue, low setup)**
  - PDF toolkit, Maven, Java 5–8, maintenance mode. **No `module-info`** (old).
  - **Diversity (pdfbox-like):** PDF generation, content/text extraction (`parser`),
    AcroForms, **digital signatures** (`security` → bouncycastle), stamping/overlay,
    PDF/A.
  - **Deps:** bouncycastle (`bcprov`+`bcpkix`, `jdk15on`/`jdk15to18`) for crypto —
    **already forked in this repo** (bc-java). Verify required-vs-optional scope.
  - **License: AGPL** (acceptable for research; note it). Low setup since BC forks exist.
- **icepdf — `com.github.pcorless.icepdf:core` 7.2.5**
  - Actively-maintained fork of ICEpdf, **Apache 2.0** (cleaner license than iText),
    Maven, AWT rendering. Diversity: render pages, extract text/images, annotations.
  - Verify: dep tree (may be thin/self-contained) + `module-info`.
- **Sejda SAMBox — `org.sejda:sambox` (defer, redundant)**
  - Literally a **PDFBox 2.0 fork** (deps: slf4j-api, jcl-over-slf4j, sejda-io,
    sejda-commons, fontbox). ⚠️ Same codebase/diversity as the **existing pdfbox
    experiment** → low marginal value; only novelty is sejda-io (nio FileChannel/
    MappedByteBuffer) + slf4j logging.

### Rejected
- **Apache POI** (office analogue) — stays rejected: messy MR-JAR `module-info` history
  across 5.x + **xmlbeans** (poi-ooxml) JPMS descriptors + heavy tree.

## mybatis/mybatis-3 (user-suggested 2026-06-16) — rejected (reconciles earlier notes)
The plan previously listed mybatis twice with differing reasons ("self-contained /
low benefit" vs "~8 deps, needs DB"). Verified and consolidated:
- **Build:** Maven.
- **❌ Instrumentation, shaded & non-excludable:** compile-scope **`javassist` 3.30.2-GA**
  + **`cglib` 3.3.0** (proxy / lazy-loading bytecode generation) + **`ognl`** (itself
  uses javassist). MyBatis **shades ognl + javassist into its own jar**, so — unlike
  Thymeleaf, which simply excluded Javassist from the classpath — they're embedded and
  cannot be removed. Runtime bytecode-instrumentation blocker.
- **❌ Non-hermetic:** it's a SQL mapper — meaningless without a **database** (its own
  tests run on HSQLDB/Derby); the DB category is excluded.
- **Verdict:** ❌ (instrumentation + DB). Supersedes the older "self-contained" note,
  which predated the ognl/javassist/cglib compile-scope deps.

---
---

## Scala / Kotlin + build-tool conversion (2026-06-16)

User opened the search to **Scala/Kotlin** apps and is willing to **rewrite the build
to Maven** (so Gradle/sbt is no longer an auto-blocker — via scala-maven-plugin /
kotlin-maven-plugin, when the build is a plain compile).

### Gating facts (verified)
- **scala-library: clean** — no `module-info`, at most Automatic-Module-Name. Scala
  apps are safe on the module axis. (Scala 3's `_3` artifact suffix only causes an
  *Automatic-Module-Name* derivation warning, not a `module-info`.)
- **kotlin-stdlib: MR-JAR `module-info`** (`libraries/stdlib/jvm/java9/module-info.java`
  → `module kotlin.stdlib` under `META-INF/versions/9`). **Strippable, same as slf4j**
  (already handled in this repo) — friction, not a blocker. Every Kotlin app inherits it.
- ⚠️ **Mavenization caveat:** plain Scala/Kotlin compiles convert cleanly; builds that
  rely on macros, codegen, KSP/kapt, multiplatform, or native-image do **not**.

### Candidates
- **scalafix (scalacenter/scalafix)** — Scala refactor/lint **app** (a Scala PMD).
  Rule + rewrite diversity over scalameta; scala-library is clean. **Caveats:** (1)
  PMD/checkstyle trap — rules share a huge scalameta front-end, so per-rule class
  divergence is thin (cf. ANTLR axis-B, google-java-format); (2) deeply sbt-integrated
  — `scalafix-cli` exists but Scala+scalameta is non-trivial to Mavenize.
- **kotlinx.serialization (Kotlin)** — multi-module **format** divergence
  (JSON / CBOR / Protobuf / HOCON / Properties), the codec-divergence pattern we like.
  **Caveats:** it's a *library* not an app; needs the kotlin-stdlib strip; serialization
  paths may go JIT-hot fast (small per-format surface).
- **ktlint / detekt (Kotlin)** — linters; both lean on **kotlin-compiler-embeddable**
  (huge single dep) and have the same thin per-rule divergence. Weak — deprioritise.

### Honest assessment
The language relaxation broadens options but does **not** clearly beat the Java
front-runners. Scala/Kotlin apps cluster into (a) linters/formatters with the PMD trap
(thin divergence + heavy compiler/parser dep) or (b) libraries. And reopening
**Java** projects previously rejected *only* for Gradle (FreeMarker, Rhino) doesn't help
— those are **zero-runtime-dep** engines (nothing to merge) and/or do runtime bytecode
gen (Rhino). Net standing recommendation unchanged: **Commons Imaging / iText 5 /
OpenNLP CLI** remain the cleanest build-ready picks; **scalafix** is the best Scala
app if a JVM-language data point is specifically wanted.

---
---

## Re-examined on request (2026-06-16)

### Checkstyle — re-verified current tree; still rejected, mitigation possible
Re-checked `checkstyle/checkstyle@master` pom (Java **21** now required). It **is** a
genuine Maven CLI **application** with a healthy tree — `picocli 4.7.7`,
`antlr4-runtime 4.13.2`, `guava 33.6.0-jre`, `commons-beanutils 1.11.0`,
`slf4j-api/-simple` — and good rule-category breadth (whitespace / naming / imports /
coding / design / metrics / javadoc). Blockers:
- **`net.sf.saxon:Saxon-HE 12.9` ships a real `module-info`** → primary blocker,
  **identical to the PMD rejection.** Saxon backs only the XPath features
  (`SuppressionXpathFilter`, `SuppressionXpathSingleFilter`, `MatchXpath`, xpath query) —
  a subset.
- **`org.reflections:reflections 0.10.2` → `javassist`** still in the transitive tree
  (used for package-scanning check discovery, not runtime self-instrumentation).
- **Mitigation (biojava-style surgery):** exclude Saxon by running only AST-visitor
  checks (no XPath) and loading checks by explicit name (drop Reflections→javassist).
  Feasible but invasive, and you lose XPath checks.
- **Divergence caveat:** even mitigated, it's the **PMD/ANTLR-axis-B trap** — all checks
  share the one antlr4 Java-grammar front-end (huge intersection), so per-check class
  divergence is thin. Net: **stays rejected**; only worth it if a static-analyzer app
  is specifically wanted and the Saxon/Reflections surgery is acceptable.

### Spotless (diffplug/spotless) — rejected
- **Not a standalone app — a build-system *plugin*.** It runs as `mvn spotless:apply` /
  a Gradle task (same category as the already-rejected JavaPackager/easypack plugins).
- **Aggregator of external formatters**, each a `Function<String,String>`: many are
  **zero-dep** (google-java-format, ktlint → nothing to merge, BCV pattern) and several
  are **npm/Node-based** (prettier, tsfmt) → **non-hermetic** (needs a Node runtime).
- **Spotless itself is Gradle-built.**
- **Verdict:** ❌ build plugin + zero-dep/Node backends + Gradle — fails on three axes.

---
---

## Applications with *really diverse* workloads (2026-06-16) — the key target

User refocus: find **apps whose workloads load genuinely disjoint, large subtrees**
(the FOP/commons-compress/biojava property that makes TreeCache win), not the PMD trap
(shared front-end + thin per-mode branches). The pattern that delivers this is
**multi-format parsers** and **multi-backend exporters** — and the recurring blocker
(POI's MR-JAR `module-info`) is **avoidable by curating the format/backend set.**

### Apache Tika (curated parser modules) ⭐⭐ — best diverse-workload app
- **Repo:** apache/tika. **Build:** Maven (Java 11+ for 3.x). **Fully modular in 3.x:**
  `tika-core` + one artifact **per format** (`tika-parser-pdf-module`,
  `-html-module`, `-text-module`, `-xml-module`, `-image-module`, `-microsoft-module`…).
- **Diversity: the best of any candidate (already rated "Excellent" for tika-core).**
  Parsing PDF vs HTML vs XML vs RTF vs EPUB vs image feeds **completely independent
  parser class hierarchies**; a single-format cache is essentially useless on the
  others. Workloads = feed one file per format; shared intersection is just
  tika-core (detection/SAX/metadata).
- **Dodging the blocker:** only the **microsoft/ooxml** module pulls **POI/xmlbeans**
  (`module-info`). **Curate to PDF + HTML + XML + text + image + RTF + EPUB** → no POI,
  no `module-info`, all hermetic (the "standard" parsers need no native bins/network).
- **Fork reuse:** `tika-parser-pdf-module` → **PDFBox (already forked)** + fontbox;
  image → metadata-extractor/commons-imaging (candidates above); html → tagsoup (old,
  no `module-info`). Multi-module mergeable tree like biojava/TwelveMonkeys.
- **Vet:** confirm each chosen parser module's transitive tree is `module-info`-free
  (esp. xml-module — avoid woodstox; prefer the SAX/commons path).

### JasperReports — export-backend diversity (FOP-shaped)
- **Repo:** Jaspersoft/jasperreports. **Build:** **Maven** (Ant removed), only
  Automatic-Module-Name on its own jars.
- **Diversity: excellent (FOP-like).** One filled report → **PDF / HTML / XML / CSV /
  RTF / XLSX / DOCX / PPTX** exporters, each a disjoint `engine.export.*` subtree.
- **Dodging the blocker:** XLSX/DOCX/PPTX exporters need **POI**; **PDF (OpenPDF) +
  HTML + XML + CSV + RTF** do not → curate to those for a POI-free, `module-info`-free
  set. PDF reuses bouncycastle; SVG uses **Batik (already forked)**.
- **Caveat:** heavier base library than Tika and more POI-entangled; curation is more
  work. Second choice after Tika.

### Principle
For "really diverse workloads," target **format/backend fan-out** apps and **curate the
format set to exclude POI/module-info modules.** Tika (parse-side) and JasperReports
(export-side) are the two that fit and reuse existing pdfbox/batik forks.

> **User clarification:** Tika/JasperReports read as **libraries**. We want genuine
> **applications** — a CLI you execute (subcommands/operations) or a UI — with that
> same fan-out diversity (the existing **pdfbox tools** are exactly this shape:
> `extracttext` / `render` / `encrypt` / `overlay` …, each a disjoint operation).

## Genuine diverse-workload *applications* (2026-06-16)

### Apache Jena — `riot` / `arq` CLI ⭐ (best genuine app found)
- **What:** Apache's RDF/SPARQL toolkit with real **command-line apps** — `riot`
  (parse/convert RDF), `arq`/`sparql` (run SPARQL), `qparse`, plus per-format
  `turtle`/`ntriples`/`rdfxml`/`trig`/`nquads`.
- **Build:** **Maven**, multi-module (`jena-core`, `jena-arq`, `jena-iri`,
  `jena-shaded-guava`). Own jars carry **Automatic-Module-Name** (no real `module-info`).
- **Diversity: excellent & genuinely app-level.** Workloads = convert
  Turtle→RDF/XML, →N-Triples, →TriG/N-Quads (disjoint parser/writer subtrees, the
  commons-compress pattern **for RDF**) **plus** `arq` SPARQL SELECT/CONSTRUCT/ASK
  (a whole query-algebra engine subtree) **plus** inference/reasoners. Far past the
  PMD trap — these are independent engines, not branches off one parser.
- **Hermetic:** operates on **local** RDF files/datasets; the server (Fuseki) and
  remote/HTTP bits are separate modules to leave out.
- **Curate the one blocker:** **JSON-LD** support pulls `jackson`/`titanium-json-ld`
  (`module-info`). Drop JSON-LD → the core formats (Turtle/NT/RDF-XML/TriG/NQ) +
  SPARQL need no jackson. Real multi-module mergeable tree (jena-core/arq/iri + commons).
- **Verdict:** ⭐ top genuine-application candidate — CLI, diverse engines, Maven,
  hermetic, clean module status. Vet: confirm `jena-arq` doesn't hard-require jackson
  once JSON-LD is excluded.

### pdftk-java — PDF-operations CLI
- **What:** a Java port of `pdftk` — CLI with many operations (merge / split / rotate /
  `fill_form` / stamp / background / encrypt / decrypt / burst / attach). Each
  operation = disjoint subtree (pdfbox-tools shape).
- **Build:** **Gradle** → would need Maven conversion (simple structure; user OK with it).
- **Deps:** lean external tree — **bcprov (already forked)** + commons-lang3; **iText 5
  is vendored** into the source.
- **Caveat:** operation diversity lives in the *app* (+vendored iText), so the external
  dep tree to merge is thin, and it overlaps the existing pdfbox PDF domain. Decent, but
  below Jena/OpenNLP.

### Apache OpenNLP — `opennlp` CLI (still a top pick)
- Already covered above: Maven, multi-module, real **task** subcommands
  (tokenize/POS/NER/parse/…) = disjoint subtrees, models as bundlable data. Genuine CLI app.

**Recommendation:** **Apache Jena (`riot`+`arq`)** is the strongest genuine diverse-workload
application — build it next; **OpenNLP CLI** is the safe second.
