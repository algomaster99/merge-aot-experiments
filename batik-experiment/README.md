# Apache Batik AOT Cache Experiment

This experiment measures the startup-time impact of AOT class-data caches built from
different coverage sources — a full test suite versus a hand-written workload — across
multiple workload types.

---

## Dependency Map

All caches are merged into `tree.aot`. `single.aot` is recorded on the `svg-to-png`
workload only and represents the narrowest useful cache.

| Artifact | Version | Role | Cache source |
|---|---|---|---|
| `org.apache.xmlgraphics:batik-transcoder` | 1.19 | Entry point; pulls in all batik-\* submodules | Test suite — `mvn test -P tree-merge` in `batik/batik-transcoder/` |
| `org.apache.xmlgraphics:xmlgraphics-commons` | 2.11 | Image codec utilities, always loaded | Test suite — `mvn test -P tree-merge` in `batik-deps/xmlgraphics-commons/` |
| `commons-io:commons-io` | 2.17.0 | Stream/file utilities used by xmlgraphics-commons | Test suite — `mvn test` (argLine patched in pom) in `batik-deps/commons-io/` |
| `commons-logging:commons-logging` | 1.3.0 | Logging façade used by xmlgraphics-commons | Custom workload — `batik-deps/commons-logging-workload/` |
| `xml-apis:xml-apis` | 1.4.01 | W3C DOM / SAX / JAXP interface stubs | Custom workload — `batik-deps/xml-apis-workload/` |
| `xml-apis:xml-apis-ext` | 1.3.04 | SVG DOM interface stubs (`org.w3c.dom.svg.*`) | Custom workload — `batik-deps/xml-apis-ext-workload/` |


---

## When We Choose a Custom Workload Instead

A test-suite recording is not always possible or useful. We fall back to a custom
workload in three situations:

### 1. The test suite requires a complex external environment

**commons-logging** has integration tests that expect specific classloader
configurations and system properties to be set before Surefire launches. Replicating
that environment reliably across machines is fragile. A focused workload that calls
`LogFactory.getLog()`, exercises every log level, and drives `SimpleLog` directly
captures every class the library loads under normal use without the setup complexity.

### 2. The artifact contains only interfaces — there is nothing to test

**xml-apis** and **xml-apis-ext** are pure stub JARs: every type they ship is a Java
`interface` (W3C DOM, SAX, JAXP, SVG DOM, SMIL DOM). There are no concrete classes and
no test suite in either artifact. Their value to the AOT cache is purely that batik
loads these interfaces at startup; we need those interface classes pre-resolved.

Each artifact gets its own recording project:

- **`xml-apis-workload/`** exercises the concrete JAXP entry points —
  `DocumentBuilderFactory`, `SAXParserFactory`, `TransformerFactory` — which trigger
  loading of the `org.w3c.dom` and `org.xml.sax` interface hierarchies as a side effect.
- **`xml-apis-ext-workload/`** force-loads every SVG DOM interface (`org.w3c.dom.svg.*`)
  via `Class.forName`. The `org.w3c.dom.smil.*` package is not present in version
  1.3.04. xml-apis is on its classpath because the SVG interfaces extend `org.w3c.dom`
  types.