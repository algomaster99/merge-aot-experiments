package dev.detektexp

import io.gitlab.arturbosch.detekt.rules.style.StyleGuideProvider
import java.nio.file.Path

object StyleWorkload {
    fun run(workDir: Path) = runWorkload("analyze-style", workDir) { StyleGuideProvider() }
}
