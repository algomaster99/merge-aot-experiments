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
> tree **plus** real workload divergence — is satisfied almost only by Closure
> Compiler below. Most lean CLI apps fail on one axis (see rejected table).

#### A. Google Closure Compiler ⭐ (best application fit)
- **Repo:** google/closure-compiler. **App:** JavaScript optimizer/minifier CLI.
- **Build:** Maven. **`module-info` window:** pre-`v20220803` jars have **no**
  `module-info` (automatic module); `v20220803`+ erroneously bundle a
  `module-info.class` (from jspecify) — **pin to a pre-2022 release** (e.g.
  `v20211201`).
- **Deps:** `guava`, `gson`, `args4j`, `protobuf-java`, `jspecify` — ~5, all
  pre-JPMS at the pinned version (protobuf-java is chunky but a single clean jar).
- **Diversity: good.** Optimization levels (`WHITESPACE_ONLY` / `SIMPLE` /
  `ADVANCED`) and ES transpilation targets activate distinct compiler-pass subtrees
  (`com.google.javascript.jscomp.*`). Hermetic (reads `.js` files).

#### B. ANTLR4 tool — borderline-lean
- **Repo:** antlr/antlr4 (`tool/`). **App:** grammar → parser code generator CLI.
- **Build:** Maven (needs Maven 3.8+).
- **Deps:** `antlr4-runtime`, `antlr-runtime 3.5.3`, `ST4 4.3.4`,
  `treelayout 1.0.3`, **`icu4j 72.1`** (⚠️ ~13 MB — **not lean**; heavy to fork
  manually; verify it carries only Automatic-Module-Name, not `module-info`).
- **Diversity: good.** Code-gen targets (Java / C# / Python / JS / Go / Swift) each
  load distinct StringTemplate + target subtrees. Hermetic (reads `.g4` grammars).
- **Verdict:** keep only if the lean bar is relaxed for icu4j; otherwise defer.

#### Evaluated and rejected for the lean bar
| App | Reason |
|-----|--------|
| graphhopper | (1) ~20 runtime deps — too many to fork manually; (2) **needs OpenStreetMap data files at runtime** → not hermetic. (per git history) |
| Checkstyle | `Saxon-HE` (`module-info`) **and** `javassist` (runtime instrumentation) — double blocker (cf. PMD + Thymeleaf) |
| PlantUML | Monolithic shaded jar → **no distributable external dep tree** (jsoup pattern); GPL |
| CFR / Procyon | Decompilers with **zero (CFR) / near-zero (Procyon) external deps** → nothing to merge (jsoup pattern) |
| google-java-format | Lean deps (guava) but **low workload diversity** (formatting is one mode) **and** needs `--add-exports` for JDK-internal `com.sun.tools.javac` on JDK 16+ |
| Eclipse JGit (pgm) | OSGi bundles + JPMS schemas (`module-info` risk) and `JSch` (network) — not clean-lean |
| Spoon (INRIA) | Research-relevant, but dominated by `org.eclipse.jdt.core` (~10 MB OSGi bundle) — **not lean**; deferred unless the bar is relaxed |
| Soot | Chains-project-relevant (Jimple/Baf/Grimp IR diversity) but ~6–8 deps (heros, jasmin, asm, axml…) — **over the lean budget**; deferred |
