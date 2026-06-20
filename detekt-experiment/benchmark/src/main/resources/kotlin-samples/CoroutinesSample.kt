// Sample file for coroutines workload.
// Uses coroutines patterns that exercise CoroutinesProvider rules (structural only — no type resolution needed).

package dev.detektsample

import kotlinx.coroutines.*

// coroutines: RedundantSuspendModifier (suspend fun with no suspension points)
suspend fun plainSuspend(): String {
    return "no suspension here"
}

// coroutines: SuspendFunWithFlowReturnType placeholder
fun createScope() = CoroutineScope(Dispatchers.Default)

class CoroutineService {
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    // coroutines: GlobalCoroutineUsage
    fun fireAndForget(block: suspend () -> Unit) {
        GlobalScope.launch { block() }
    }

    fun launchTask(name: String): Job = scope.launch {
        delay(100)
        println("done: $name")
    }

    fun cancel() = scope.cancel()

    // coroutines: InjectDispatcher — dispatcher hardcoded
    suspend fun fetchData(): List<String> = withContext(Dispatchers.IO) {
        delay(50)
        listOf("a", "b", "c")
    }

    // coroutines: RedundantSuspendModifier
    suspend fun syncComputation(x: Int, y: Int): Int {
        return x + y
    }
}

// coroutines: SleepInsteadOfDelay
suspend fun waitForEvent() {
    delay(500)
}

// coroutines: DeferredResultUnused
suspend fun unusedDeferred() {
    val scope = CoroutineScope(Dispatchers.Default)
    scope.async { "result" }
    delay(200)
    scope.cancel()
}
