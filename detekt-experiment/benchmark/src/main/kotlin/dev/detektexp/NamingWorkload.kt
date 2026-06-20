package dev.detektexp

import io.gitlab.arturbosch.detekt.rules.naming.NamingProvider
import java.nio.file.Path

object NamingWorkload {
    fun run(workDir: Path) = runWorkload("analyze-naming", workDir) { NamingProvider() }
}
