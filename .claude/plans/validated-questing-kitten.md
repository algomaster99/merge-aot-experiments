# Plan: picocli-experiment

## Context

The goal is a reusable toy workload that exercises picocli so its classes get recorded into an AOT cache. That cache can later be merged with the cache of any app that depends on picocli (e.g. MCS). Instead of cloning picocli, the workload simply pulls it from Maven Central. Multiple Maven profiles set the picocli version to match whichever downstream app the cache is being built for.

---

## Directory Structure

```
picocli-experiment/
└── workload/
    ├── pom.xml                      # picocli from Maven Central; version profiles per app
    └── src/main/java/com/example/
        └── App.java                 # Simple picocli command
```

---

## Files to Create

### 1. `workload/pom.xml`

- `groupId`: `com.example`, `artifactId`: `workload`, `version`: `1.0-SNAPSHOT`
- `maven.compiler.release`: 24
- Default `picocli.version` property: `4.7.7`
- **Profiles** (each overrides `picocli.version` to match a consuming app):
  - `mcs` → `4.7.7` (matches `mcs-experiment/mcs`)
- Dependency: `info.picocli:picocli:${picocli.version}`
- Build: `maven-shade-plugin` producing fat jar with `Main-Class: com.example.App`

### 2. `workload/src/main/java/com/example/App.java`

A single `@Command` class exercising picocli's core paths:
- `--name` (String option, default `"World"`)
- `--count` (int option, default `100`)
- `--upper` (boolean flag)
- `mixinStandardHelpOptions = true`
- `call()` loops `count` times printing a greeting

```java
@Command(name = "greet", mixinStandardHelpOptions = true, version = "1.0",
         description = "Picocli AOT workload")
public class App implements Callable<Integer> {
    @Option(names = {"-n", "--name"}, defaultValue = "World") String name;
    @Option(names = {"-c", "--count"}, defaultValue = "100")  int count;
    @Option(names = {"--upper"})                               boolean upper;

    public static void main(String[] args) {
        System.exit(new CommandLine(new App()).execute(args));
    }

    @Override
    public Integer call() {
        for (int i = 0; i < count; i++) {
            String msg = "Hello, " + name + "! (run " + (i+1) + ")";
            System.out.println(upper ? msg.toUpperCase() : msg);
        }
        return 0;
    }
}
```

---

## Usage

**Build** (once, per target app):
```bash
cd picocli-experiment/workload
mvn package -Pmcs
```

**Record AOT cache** (caller customises output path and args to taste):
```bash
java -XX:AOTCacheOutput=picocli-mcs.aot \
     -jar target/workload-1.0-SNAPSHOT.jar \
     --name Alice --count 500
```

Output `picocli-mcs.aot` is then ready to be merged with MCS's own cache.

---

## Verification

1. `mvn package -Pmcs` → produces `target/workload-1.0-SNAPSHOT.jar`
2. Record command above → produces `picocli-mcs.aot`
3. `java -XX:AOTCache=picocli-mcs.aot -jar target/workload-1.0-SNAPSHOT.jar --name Bob --count 5` → runs cleanly
