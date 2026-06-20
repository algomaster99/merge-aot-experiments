package dev.detektexp

import java.io.File
import java.nio.file.Path

fun main(args: Array<String>) {
    if (args.size < 2) {
        System.err.println("Usage: Main <command> <workdir>")
        System.err.println("Commands: prepare, analyze-complexity, analyze-style, analyze-naming, analyze-bugs, analyze-coroutines")
        System.exit(1)
    }
    val cmd = args[0]
    val workDir = Path.of(args[1])
    when (cmd) {
        "prepare"            -> prepare(workDir)
        "analyze-complexity" -> ComplexityWorkload.run(workDir)
        "analyze-style"      -> StyleWorkload.run(workDir)
        "analyze-naming"     -> NamingWorkload.run(workDir)
        "analyze-bugs"       -> BugsWorkload.run(workDir)
        "analyze-coroutines" -> CoroutinesWorkload.run(workDir)
        else -> { System.err.println("Unknown command: $cmd"); System.exit(1) }
    }
}

fun prepare(workDir: Path) {
    workDir.toFile().mkdirs()
    extractResource("kotlin-samples/Sample.kt", workDir.resolve("Sample.kt").toFile())
    extractResource("kotlin-samples/CoroutinesSample.kt", workDir.resolve("CoroutinesSample.kt").toFile())
    println("prepared: ${workDir.toAbsolutePath()}")
}

private fun extractResource(resource: String, dest: File) {
    val stream = object {}.javaClass.classLoader.getResourceAsStream(resource)
        ?: error("Resource not found: $resource")
    dest.writeBytes(stream.readBytes())
}
