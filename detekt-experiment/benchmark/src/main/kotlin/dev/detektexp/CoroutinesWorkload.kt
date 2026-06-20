package dev.detektexp

import io.gitlab.arturbosch.detekt.rules.coroutines.CoroutinesProvider
import java.nio.file.Path

object CoroutinesWorkload {
    fun run(workDir: Path) {
        // coroutines rules need BindingContext for most findings; use the coroutines sample
        val env = io.github.detekt.parser.createKotlinCoreEnvironment(printStream = System.err)
        val compiler = io.github.detekt.parser.KtCompiler(env)

        val sampleFile = workDir.resolve("CoroutinesSample.kt")
        require(sampleFile.toFile().isFile) { "Run 'prepare' first: $sampleFile not found" }

        val ktFile = compiler.compile(workDir, sampleFile)
        val provider = CoroutinesProvider()
        val ruleSet = provider.instance(io.gitlab.arturbosch.detekt.api.Config.empty)

        var count = 0
        for (rule in ruleSet.rules) {
            (rule as io.gitlab.arturbosch.detekt.api.BaseRule).visitFile(
                ktFile, org.jetbrains.kotlin.resolve.BindingContext.EMPTY
            )
            count += rule.findings.size
        }
        println("analyze-coroutines: $count findings")
    }
}
