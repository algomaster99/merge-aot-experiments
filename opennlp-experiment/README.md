# opennlp-morfologik AOT cache experiment

## Compile-scope dependency tree

```
opennlp-morfologik-addon:2.5.9
├── morfologik-stemming:2.1.9          ✓ included
│   └── morfologik-fsa:2.1.9           ✗ excluded — no test suite
├── morfologik-tools:2.1.9             ✓ included
│   ├── morfologik-fsa-builders:2.1.9  ✓ included
│   │   └── hppc:0.7.2                 ✗ excluded — Gradle build
│   └── jcommander:1.78                ✗ excluded — Gradle build; CLI utility covered by morfologik-tools tests
├── slf4j-api:2.0.17                   ✗ excluded — logging facade, no meaningful classes to cache
└── opennlp-tools:2.5.9               ✓ included
```

`opennlp-morfologik-addon` itself is also included (✓).

## Included submodules (contribute a cache to `tree.aot`)

| Module | Submodule path |
|---|---|
| `opennlp-tools` | `opennlp/opennlp-tools` |
| `opennlp-morfologik-addon` | `opennlp/opennlp-morfologik-addon` |
| `morfologik-fsa-builders` | `opennlp-deps/morfologik/morfologik-fsa-builders` |
| `morfologik-stemming` | `opennlp-deps/morfologik/morfologik-stemming` |
| `morfologik-tools` | `opennlp-deps/morfologik/morfologik-tools` |

## Excluded dependencies

| Dependency | Reason |
|---|---|
| `morfologik-fsa` | No test suite; its classes are recorded in `morfologik-fsa-builders` cache |
| `hppc` | Gradle build (not Maven); its classes are recorded in `morfologik-fsa-builders` cache |
| `jcommander` | Gradle build (not Maven); CLI utility covered by `morfologik-tools` tests |
| `slf4j-api` | Logging facade only; no meaningful classes to cache |
