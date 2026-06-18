Picocli 4.7.7 is a direct dependency of `pdfbox-tools` and `pdfbox-debugger`.

The published JAR on Maven Central has classes compiled to bytecode version 49 (Java 5),
which the AOT cache mechanism automatically skips.

## Fix

picocli's `build.gradle` already gates on the running JVM:

```groovy
if (!JavaVersion.current().isJava9Compatible()) {
    sourceCompatibility = JavaVersion.VERSION_1_5
    targetCompatibility = JavaVersion.VERSION_1_5
} else {
    sourceCompatibility = JavaVersion.VERSION_1_8
    targetCompatibility = JavaVersion.VERSION_1_8
}
```

When built with Java 9+, classes come out at bytecode 52 (Java 8) and are AOT-cacheable.

The fork at `algomaster99/picocli` (`aotcache-setup` branch) adds the tree-merge Gradle
property so `./gradlew test -Ptree-merge` emits `cache.aot`.
The submodule lives at `pdfbox-experiment/pdfbox-deps/picocli`.
