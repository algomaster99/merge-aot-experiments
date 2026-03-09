### Merging AOT cache using mutliple `-XX:AOTCache`

```shell
java -XX:AOTCacheOutput=a.aot  -jar target/A-1.0-SNAPSHOT.jar
java -XX:AOTCacheOutput=b.aot  -jar target/B-1.0-SNAPSHOT.jar
java -XX:AOTCache=../B/b.aot -XX:AOTCache=../A/a.aot -Xlog:class+load=info,aot+codecache=debug:file=production.log:level,tags  -jar target/app-1.0-SNAPSHOT.jar
```

This creates a `production.log` file and only the later cache is used.
Multiple caches are not supported.
```
[info][class,load] com.example.B source: shared objects file
[info][class,load] com.example.Main source: file:/home/aman/Desktop/experiments/jit-testing/multiple-aotcache/app/target/app-1.0-SNAPSHOT.jar
[info][class,load] com.example.A source: file:/home/aman/Desktop/experiments/jit-testing/multiple-aotcache/app/target/app-1.0-SNAPSHOT.jar
```
```
[info][class,load] com.example.A source: shared objects file
[info][class,load] java.util.zip.ZipFile$Source$$Lambda/0x0000000016000000 source: java.util.zip.ZipFile
[info][class,load] com.example.Main source: file:/home/aman/Desktop/experiments/jit-testing/multiple-aotcache/app/target/app-1.0-SNAPSHOT.jar
[info][class,load] com.example.B source: file:/home/aman/Desktop/experiments/jit-testing/multiple-aotcache/app/target/app-1.0-SNAPSHOT.jar
```
> as you can see the first log shows that only `B` is loaded from the cache and the second log shows that only `A` is loaded from the cache.
This is because the second cache specified overrides the first one.

This is verified with:
```
openjdk version "27-internal" 2026-09-15
OpenJDK Runtime Environment (build 27-internal-adhoc.aman.jdk)
OpenJDK 64-Bit Server VM (build 27-internal-adhoc.aman.jdk, mixed mode, sharing)
```

### Merging CDS archive using by combining `classlist` files

```shell
java -Xshare:off -XX:DumpLoadedClassList=a.classlist -jar target/A-1.0-SNAPSHOT.jar
java -Xshare:off -XX:DumpLoadedClassList=b.classlist -jar target/B-1.0-SNAPSHOT.jar
```

This creates two classlist files `a.classlist` and `b.classlist` which can be merged into a single file `combined.classlist` by concatenating the two files and removing duplicates.
> I did it naively and only added
`com/example/B id: 718
@cp com/example/B 1 2 10 15 17 18 22 23`
to the `merged.classlist` file and it worked as expected.

Then I created a CDS archive using the merged classlist file:
```shell
java -Xshare:dump -XX:SharedArchiveFile=combined.jsa -XX:SharedClassListFile=../combined.classlist -jar target/app-1.0-SNAPSHOT.jar
```