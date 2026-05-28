# Apache FOP AOT Cache Experiment

This experiment measures the startup-time impact of AOT class-data caches across
multiple **output formats** of the same XSL-FO document. FOP shares one front-end
(the fop-core layout engine, plus batik for embedded SVG and fontbox for fonts)
but loads a completely independent renderer / document-handler class subtree per
output format — an ideal profile for the TreeCache (merged per-dependency cache)
approach to beat a single monolithic AOTCache.

---

## Why FOP

FOP was selected from the DaCapo 2025 suite and the `sbom.exe` rq3/rq4 audit set
(`chains-project/exploits-for-sbom.exe`). It satisfies all project filters:

- **Build system:** Maven (Ant build is deprecated since FOP 2.2). No Gradle.
- **No `module-info.java`** anywhere in the FOP source tree (verified on trunk).
- **No runtime instrumentation** (no AspectJ/ByteBuddy/Javassist on the runtime path).
- **Dependency tree reuses existing forks.** FOP 2.10's runtime deps are
  batik 1.18, xmlgraphics-commons 2.10, commons-io 2.11.0, commons-logging 1.3.0
  and fontbox — the same artifacts already forked for the batik and pdfbox
  experiments. `pdfbox`, `xalan`, `jai`, `bouncycastle`, `ant` and the servlet
  API are `provided`/`test` scope and are **not** on the runtime classpath.

### Empirical workload diversity (measured on JDK 21, `-Xlog:class+load`)

Library classes (`org.apache.{fop,batik,xmlgraphics,commons,fontbox}`) loaded per
workload, over the shared sample FO document:

| Workload   | Lib classes | `render.*`-specific |
|------------|-------------|---------------------|
| fo-to-pdf  | 1360        | 223 |
| fo-to-ps   | 1251        | 212 |
| fo-to-pcl  | 1177        | 194 |
| fo-to-rtf  |  915        | 214 |
| fo-to-txt  | 1125        | 162 |
| fo-to-png  | 1193        | 199 |

- **808** classes are loaded by **all six** workloads (the shared FO front-end).
- **1612** classes in the **union** across workloads.
- ⇒ roughly **half** of the loaded library surface is workload-specific.

A monolithic `single-{op}.aot` trained on one format misses the ~200 renderer
classes of every other format; `tree.aot`, built from the dependency test suites,
covers the union. This is the same divergence that gave TreeCache its largest win
in the batik experiment.

---

## Dependency Map

All caches are merged into `tree.aot`. `single-{op}.aot` is recorded per workload
and represents the narrowest useful cache for the AOTCache baseline.

| Artifact | Version | Role | Cache source |
|---|---|---|---|
| `org.apache.xmlgraphics:fop-core` | 2.10 | Entry point; FO parsing + layout engine + all renderers | Test suite — `mvn test -P tree-merge` in `fop/fop-core/` |
| `org.apache.xmlgraphics:batik-*` | 1.18 | SVG handling for `fo:instream-foreign-object` + raster output | Test suite — reuse batik fork (`batik-test-old`) |
| `org.apache.xmlgraphics:xmlgraphics-commons` | 2.10 | Image I/O, PS/PDF graphics utilities | Test suite — `mvn test -P tree-merge` |
| `commons-io:commons-io` | 2.11.0 | Stream/file utilities | Test suite — `mvn test` (argLine patched) |
| `commons-logging:commons-logging` | 1.3.0 | Logging façade | Custom workload (test suite needs special classloader setup) |
| `org.apache.pdfbox:fontbox` | (managed) | TrueType/Type1 font parsing | Test suite — reuse pdfbox fork |

---

## Workloads

Each renders the same `sample.fo` (page sequence with a table, list, leader and
inline styling) to a different format via `FopFactory` + a format-specific MIME
type. The FO layout is identical; only the renderer subtree differs.

| Workload   | MIME | Renderer subtree exercised |
|------------|------|----------------------------|
| fo-to-pdf  | `application/pdf`        | `org.apache.fop.render.pdf.*` + PDF library |
| fo-to-ps   | `application/postscript` | `org.apache.fop.render.ps.*` |
| fo-to-pcl  | `application/x-pcl`      | `org.apache.fop.render.pcl.*` |
| fo-to-rtf  | `application/rtf`        | `org.apache.fop.render.rtf.*` (rtflib) |
| fo-to-txt  | `text/plain`            | `org.apache.fop.render.txt.*` |
| fo-to-png  | `image/png`             | `org.apache.fop.render.bitmap.*` + Java2D/ImageIO raster |

---

## Running

> Requires a Leyden/AOT-capable JDK (24+/25). The benchmark itself compiles and
> runs on any JDK 8+; the AOT steps need the custom JDK used in CI.

```bash
# 1. Build the fat-jar benchmark (bundles fop-core + all runtime deps)
cd benchmark && mvn package -DskipTests && cd ..

# 2. AOTCache baseline: one single-{op}.aot per workload
./create-single-aot.sh

# 3. TreeCache: merge the per-dependency cache.aot files into tree.aot
#    (record the dependency caches first — see orchestrate-combine.sh)
./orchestrate-combine.sh

# 4. Timed comparison (no-AOT vs AOTCache cross-workload vs TreeCache)
RUNS=30 ./workload-timed.sh
```

`workload-timed.sh` prints a per-workload table plus a LaTeX row block
(`workload-tmp/latex-rows.tex`) in the same format as the other experiments, where
AOTCache is measured cross-workload (a cache trained on op A run on op B) and
TreeCache uses the single merged `tree.aot`.
