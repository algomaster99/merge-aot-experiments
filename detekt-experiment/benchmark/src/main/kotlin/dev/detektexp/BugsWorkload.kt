package dev.detektexp

import io.gitlab.arturbosch.detekt.rules.bugs.PotentialBugProvider
import java.nio.file.Path

object BugsWorkload {
    fun run(workDir: Path) = runWorkload("analyze-bugs", workDir) { PotentialBugProvider() }
}
