package dev.detektexp

import io.gitlab.arturbosch.detekt.api.BaseRule
import io.gitlab.arturbosch.detekt.api.Config
import io.gitlab.arturbosch.detekt.api.RuleSetProvider
import io.github.detekt.parser.KtCompiler
import io.github.detekt.parser.createKotlinCoreEnvironment
import org.jetbrains.kotlin.resolve.BindingContext
import java.nio.file.Path

fun runWorkload(name: String, workDir: Path, providerFn: () -> RuleSetProvider) {
    val env = createKotlinCoreEnvironment(printStream = System.err)
    val compiler = KtCompiler(env)

    val sampleFile = workDir.resolve("Sample.kt")
    require(sampleFile.toFile().isFile) { "Run 'prepare' first: $sampleFile not found" }

    val ktFile = compiler.compile(workDir, sampleFile)

    val provider = providerFn()
    val ruleSet = provider.instance(Config.empty)

    var count = 0
    for (rule in ruleSet.rules) {
        (rule as BaseRule).visitFile(ktFile, BindingContext.EMPTY)
        count += rule.findings.size
    }
    println("$name: $count findings")
}
