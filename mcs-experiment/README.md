### packageurl-java v1.5.0

`packageurl-java` v1.5.0 is required but it won't build because:
```
[ERROR] Failed to execute goal org.apache.maven.plugins:maven-compiler-plugin:3.11.0:compile (default-compile) on project packageurl-java: Compilation failure
[ERROR] /home/aman/Desktop/experiments/jit-testing/mcs-experiment/mcs-deps/packageurl-java/src/main/java/com/github/packageurl/validator/PackageURLConstraintValidator.java:[32,8] cannot access java.lang.Object
[ERROR]   bad class file: /modules/java.base/java/lang/Object.class
[ERROR]     class file has wrong version 69.0, should be 53.0
[ERROR]     Please remove or make sure it appears in the correct subdirectory of the classpath.
```

### jackson-jr-objects v2.12.2

The test fails for other modules but not for `jackson-jr-objects`.

TODO: the other two modules are gradle.

### picocli v4.7.7

❯ ./gradlew test -Ptree-merge
Downloading https://services.gradle.org/distributions/gradle-8.13-bin.zip
.............10%.............20%.............30%.............40%.............50%.............60%.............70%.............80%.............90%.............100%
WARNING: A restricted method in java.lang.System has been called
WARNING: java.lang.System::load has been called by net.rubygrapefruit.platform.internal.NativeLibraryLoader in an unnamed module (file:/home/aman/.gradle/wrapper/dists/gradle-8.13-bin/5xuhj0ry160q40clulazy9h7d/gradle-8.13/lib/native-platform-0.22-milestone-28.jar)
WARNING: Use --enable-native-access=ALL-UNNAMED to avoid a warning for callers in this module
WARNING: Restricted methods will be blocked in a future release unless native access is enabled

To honour the JVM settings for this build a single-use Daemon process will be forked. For more on this, please refer to https://docs.gradle.org/8.13/userguide/gradle_daemon.html#sec:disabling_the_daemon in the Gradle documentation.
Daemon will be stopped at the end of the build 

FAILURE: Build failed with an exception.

* What went wrong:
BUG! exception in phase 'semantic analysis' in source unit '_BuildScript_' Unsupported class file major version 69
> Unsupported class file major version 69

* Try:
> Run with --stacktrace option to get the stack trace.
> Run with --info or --debug option to get more log output.
> Run with --scan to get full insights.
> Get more help at https://help.gradle.org.

### dagger 

for some reason Gradle itself fails to parse the version
```
❯ ./gradlew test -Ptree-merge
WARNING: A restricted method in java.lang.System has been called
WARNING: java.lang.System::load has been called by net.rubygrapefruit.platform.internal.NativeLibraryLoader in an unnamed module (file:/home/aman/.gradle/wrapper/dists/gradle-8.14.3-bin/cv11ve7ro1n3o1j4so8xd9n66/gradle-8.14.3/lib/native-platform-0.22-milestone-28.jar)
WARNING: Use --enable-native-access=ALL-UNNAMED to avoid a warning for callers in this module
WARNING: Restricted methods will be blocked in a future release unless native access is enabled

To honour the JVM settings for this build a single-use Daemon process will be forked. For more on this, please refer to https://docs.gradle.org/8.14.3/userguide/gradle_daemon.html#sec:disabling_the_daemon in the Gradle documentation.
Daemon will be stopped at the end of the build 
Calculating task graph as no cached configuration is available for tasks: test

FAILURE: Build failed with an exception.

* What went wrong:
25
```