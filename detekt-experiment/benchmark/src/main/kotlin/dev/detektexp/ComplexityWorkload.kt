package dev.detektexp

import io.gitlab.arturbosch.detekt.rules.complexity.ComplexityProvider
import java.nio.file.Path

object ComplexityWorkload {
    fun run(workDir: Path) = runWorkload("analyze-complexity", workDir) { ComplexityProvider() }
}
