All experiments are run using
```
openjdk version "27-internal" 2026-09-15
OpenJDK Runtime Environment (build 27-internal-adhoc.aman.jdk)
OpenJDK 64-Bit Server VM (build 27-internal-adhoc.aman.jdk, mixed mode, sharing)
```

and PDFBox 3.0.4.

I first run `mvn clean package -DskipTests` to build the PDFBox library.
This gives `classes` and `test-classes` directories.
Since AOTCache creation is [not compatible with directories on classpath](https://stackoverflow.com/a/79790050/5264537), I create `main.jar` and `tests.jar` in every module that has tests like so:
```
jar cf target/main.jar -C target/classes .
jar cf target/tests.jar -C target/test-classes .
```

Then my idea was to run the test via command-line so I relied on `junit-standalone` to run the tests.

The classpath is built using manually concatenating the outputs of `mvn dependency:build-classpath` for each module.
See [full-classpath.txt](full-classpath.txt) for the full classpath.

```
/home/aman/Desktop/tools/jdk/build/linux-x86_64-server-release/images/jdk/bin/java -XX:+UnlockDiagnosticVMOptions   -XX:AOTCacheOutput=pdfbox.aot -jar ~/.m2/repository/org/junit/platform/junit-platform-console-standalone/1.11.3/junit-platform-console-standalone-1.11.3.jar  -cp <full-classpath> --scan-classpath
```

This creates a `pdfbox.aot` file.
Then I list classes in the `pdfbox.aot` file.

In terms of contents of classes, the `pdfbox.aot` seems to be non-reproducible as shown if [1.txt](1.txt) and [2.txt](2.txt) are `diff`-ed.
