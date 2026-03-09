Here I am trying to demonstrate if CDS archive can be created instead of AOT cache and used as a replacement for it.
Experiment is done with JDK `27+7`.

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

I create CDS archive with:
```
java -Xshare:off -XX:DumpLoadedClassList=pdfbox-27+7.classlist -jar workload-with-pdfbox.jar # creates pdfbox-27+7.classlist file
java -Xshare:dump -XX:SharedArchiveFile=pdfbox-27+7.jsa -XX:SharedClassListFile=pdfbox-27+7.classlist -jar workload-with-pdfbox.jar # creates pdfbox-27+7.jsa file
```

The second command gives a warning:
```
[0,705s][warning][cds] Preload Warning: Verification failed for org.apache.commons.logging.impl.Log4jApiLogFactory because a java.lang.NoClassDefFoundError was thrown: org/apache/logging/log4j/spi/LoggerAdapter
[1,823s][warning][cds] Skipping org/apache/commons/logging/impl/Log4jApiLogFactory: Failed verification
```

### As a client, I do:

```
java -XX:SharedArchiveFile=/home/aman/Desktop/experiments/jit-testing/pdfbox-as-application/pdfbox-27+7.jsa -jar app/target/pdfbox-app-3.0.4.jar export:text -i /tmp/resume.pdf
```

This does not load any classes from shared archive possibly due to
```
[0.017s][info][class,path] Checking app classpath (with longest common prefix substitution)
[0.017s][info][class,path] - expected : 'app/target/workload-with-pdfbox.jar'
[0.017s][info][class,path] - actual   : 'app/target/pdfbox-app-3.0.4.jar'
[0.017s][info][class,path] Checking [1] 'workload-with-pdfbox.jar' file
[0.017s][warning][cds       ] Required classpath entry does not exist: workload-with-pdfbox.jar
[0.017s][info   ][class,path] Archived app classpath validation: failed
```