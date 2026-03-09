# What does it mean to merge shared archives?

The idea is to merge shared archives like CDS and AOTCache from different dependencies into a single shared archive.

## Why do we want to merge them?

I imagined a scenario where a library developer like github.com/INRIA/spoon would provide a CDS archive and an AOTCache file for their library.
A user would then be able to use *this already trained shared archive* to speed up the startup of their application.
Note, for an application merging is not required.
Merging comes into play when the user wants to build on top of their shared archive and share it with their downstream users.

## How do we merge them?

In each of the examples below, the library maintainer will create a shared archive using a "comprehensive" workload.

Then the user will try to simply use this shared archive as-is.
If the user cannot use it as-is, then of course merging would not work either.

### AOTCache

AOTCache is a memory mapped file.
A memory mapped file is a file that contains pointers to the classes and methods loaded by the application.
The advantage of a memory mapped file is that it can be reused by another process and this another process does not need to waste time doing IO operations and loading objects in the memory.
A memory mapped file directly maps into an application's address space.

The structure of an AOTCache is a header and then many OOPS objects like [class](https://github.com/chains-project/aotp/blob/main/src/main/java/io/github/chains_project/aotp/oops/klass/SPECIFICATION.md).

Merging it would require parsing the file and relocating the pointers which I could not find a way to do.
I could still parse `rw` and `ro` regions and merge them into a single file, but then JVM would throw an error that the shared archive is truncated.
It removes the bitmap region and the heap region.
I have no idea what the bitmap region is for and how to parse it.

### AOTConfiguration

AOTConfiguration is a file that contains the configuration for the AOTCache.
It is basically a subset of the AOTCache file without the heap region.
It has rw, ro, and bitmap region.
Hence, the same problem persists.

### CDS archive

I am not merging the CDS archive because it is also a memory mapped file


### CDS archive classlist

The classlist is a human readable text file which can be merged so I gave it a go.

Using as-is, throws an error:
```
[1,463s][warning][aot,resolve] class Workload is not (yet) loaded by one of the built-in loaders:
[1,463s][warning][aot,resolve] @cp Workload 2 9 11 12 19 21 22 27 31 39 53 60 64 68 69 127
[1,463s][warning][aot,resolve]     ^
```
so I commented out [this line](https://github.com/openjdk/jdk/blob/62c7e9aefd4320d9d0cd8fa10610f59abb4de670/src/hotspot/share/cds/classListParser.cpp#L834)
but can be left since it is just a warning.

```
java  -Xshare:off -XX:DumpLoadedClassList=pdfbox-27+7.classlist -jar workload-with-pdfbox.jar 
```
This gives us the classlist file `pdfbox-27+7.classlist`.

```
java -Xshare:dump -XX:SharedArchiveFile=pdfbox-27+7.jsa -XX:SharedClassListFile=pdfbox-27+7.classlist -jar pdfbox-app-3.0.4.jar export:text -i /tmp/resume.pdf
```

This atleast creates the shared archive file `.jsa`.

```
java -Xlog:class+load  -XX:SharedArchiveFile=pdfbox-27+7.jsa -jar pdfbox-app-3.0.4.jar export:text -i /tmp/resume.pdf > /tmp/only-io.txt
```
This shows that PDFBox classes are loaded from shared archive.
