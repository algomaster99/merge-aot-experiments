Experiment is to train a PDFBox application for AOTCache and then distribute the AOTCache file to a client.

### As a PDFBox maintainer, I do:

```shell
javac -cp pdfbox-app-3.0.4.jar Workload.java \                     
  && mkdir -p build \
  && cd build \
  && jar xf ../pdfbox-app-3.0.4.jar \
  && cp ../Workload.class . \
  && printf 'Main-Class: Workload\n' > manifest.mf \
  && jar cfm ../workload-with-pdfbox.jar manifest.mf .
```
This creates `workload-with-pdfbox.jar` file.

I run the workload with:
```
java -XX:AOTCacheOutput=pdfbox-25.aot -jar workload-with-pdfbox.jar
```

### As a client, I do:

```
java -Xlog:class+load=info,aot+codecache=debug:file=production.log:level,tags -Xlog:class+path -XX:AOTCache=/home/aman/Desktop/experiments/jit-testing/pdfbox-as-application/pdfbox-25.aot -jar app/target/pdfbox-app-3.0.4.jar export:text -i /tmp/resume.pdf
```

## Verdict

### JDK 25

It fails.
```
[0.004s][info][class,path] bootstrap loader class path=/home/aman/.sdkman/candidates/java/25-open/lib/modules
[0.023s][info][class,path] Reading classpath(s) from /home/aman/Desktop/experiments/jit-testing/pdfbox-as-application/pdfbox-25.aot (size = 2)
[0.023s][info][class,path] (boot  ) [0] = /home/aman/.sdkman/candidates/java/25-open/lib/modules
[0.023s][info][class,path] (app   ) [1] = workload-with-pdfbox.jar
[0.023s][info][class,path] Checking [0] (modules image)
[0.023s][info][class,path] ok
[0.023s][info][class,path] Modules image /home/aman/.sdkman/candidates/java/25-open/lib/modules validation: passed
[0.023s][info][class,path] Longest common prefix substitution in boot/app classpath matching: yes
[0.023s][info][class,path] Longest common prefix: app/target/ (11 chars)
[0.023s][info][class,path] Archived boot classpath validation: passed
[0.023s][info][class,path] Checking app classpath (with longest common prefix substitution)
[0.023s][info][class,path] - expected : 'app/target/workload-with-pdfbox.jar'
[0.023s][info][class,path] - actual   : 'app/target/pdfbox-app-3.0.4.jar'
[0.023s][info][class,path] Checking [1] 'workload-with-pdfbox.jar' file
[0.023s][warning][aot       ] Required classpath entry does not exist: workload-with-pdfbox.jar
[0.023s][info   ][class,path] Archived app classpath validation: failed
[0.023s][error  ][aot       ] An error has occurred while processing the AOT cache. Run with -Xlog:aot for details.
[0.023s][error  ][aot       ] shared class paths mismatch
[0.027s][error  ][aot       ] Unable to map shared spaces
Feb 06, 2026 4:01:13 PM org.apache.pdfbox.pdmodel.font.PDSimpleFont toUnicode
WARNING: No Unicode mapping for link (174) in font RGKYOA+FontAwesome
Feb 06, 2026 4:01:13 PM org.apache.pdfbox.pdmodel.font.PDSimpleFont toUnicode
WARNING: No Unicode mapping for github (135) in font RGKYOA+FontAwesome
Feb 06, 2026 4:01:13 PM org.apache.pdfbox.pdmodel.font.PDSimpleFont toUnicode
WARNING: No Unicode mapping for calendar (17) in font RGKYOA+FontAwesome
```

Apparently the classpath should match.

### JDK 27+7

It works.
Probably, because classpath validation is not strict.
This relaxation has been introduced in https://github.com/openjdk/jdk/commit/85715e1050fa774c3267dbbe2f749717aeeec8ff.
```
[0.004s][info][class,path] bootstrap loader class path=/home/aman/.sdkman/candidates/java/debug-build-27/lib/modules
[0.020s][info][class,path] Reading classpath(s) from /home/aman/Desktop/experiments/jit-testing/pdfbox-as-application/pdfbox-27+7.aot (size = 2)
[0.020s][info][class,path] (boot  ) [0] = /home/aman/.sdkman/candidates/java/debug-build-27/lib/modules
[0.020s][info][class,path] (app   ) [1] = workload-with-pdfbox.jar
[0.020s][info][class,path] Checking [0] (modules image)
[0.020s][info][class,path] ok
[0.020s][info][class,path] Modules image /home/aman/.sdkman/candidates/java/debug-build-27/lib/modules validation: passed
[0.020s][info][class,path] Longest common prefix substitution in boot/app classpath matching: yes
[0.020s][info][class,path] Longest common prefix: app/target/ (11 chars)
[0.020s][info][class,path] Archived boot classpath validation: passed
[0.020s][info][class,path] Archived module path validation: passed
Feb 06, 2026 4:11:20 PM org.apache.pdfbox.pdmodel.font.PDSimpleFont toUnicode
WARNING: No Unicode mapping for link (174) in font RGKYOA+FontAwesome
Feb 06, 2026 4:11:20 PM org.apache.pdfbox.pdmodel.font.PDSimpleFont toUnicode
WARNING: No Unicode mapping for github (135) in font RGKYOA+FontAwesome
Feb 06, 2026 4:11:20 PM org.apache.pdfbox.pdmodel.font.PDSimpleFont toUnicode
WARNING: No Unicode mapping for calendar (17) in font RGKYOA+FontAwesome
```
