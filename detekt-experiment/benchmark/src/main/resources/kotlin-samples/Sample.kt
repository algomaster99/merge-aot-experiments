// Sample Kotlin file for detekt analysis workloads.
// Contains patterns that trigger complexity, style, naming, and bug rules.

package dev.detektsample

import java.io.*
import java.util.*

// naming: class should be UpperCamelCase — this is fine, but the members below have issues
class DataProcessor {

    // complexity: LongParameterList, CyclomaticComplexMethod
    fun processRecord(
        id: Int,
        name: String,
        value: Double,
        flag: Boolean,
        category: String,
        subCategory: String,
        priority: Int
    ): String {
        // style: MagicNumber
        if (id < 0 || id > 99999) return "invalid"
        if (name.length < 2 || name.length > 256) return "bad-name"
        if (value < 0.0 || value > 1000000.0) return "out-of-range"

        val result = StringBuilder()
        if (flag) {
            when (category) {
                "A" -> result.append("alpha")
                "B" -> result.append("beta")
                "C" -> result.append("gamma")
                "D" -> result.append("delta")
                "E" -> result.append("epsilon")
                else -> result.append("unknown")
            }
        } else {
            if (priority > 5) {
                result.append("high-").append(subCategory)
            } else if (priority > 2) {
                result.append("mid-").append(subCategory)
            } else {
                result.append("low-").append(subCategory)
            }
        }

        // style: MagicNumber
        if (result.length > 100) result.setLength(100)
        return result.toString()
    }

    // complexity: NestedBlockDepth
    fun findNested(matrix: List<List<List<Int>>>, target: Int): Triple<Int, Int, Int>? {
        for (i in matrix.indices) {
            for (j in matrix[i].indices) {
                for (k in matrix[i][j].indices) {
                    if (matrix[i][j][k] == target) {
                        return Triple(i, j, k)
                    }
                }
            }
        }
        return null
    }

    // style: ThrowsCount, TooGenericExceptionCaught, TooGenericExceptionThrown
    fun riskyOperation(input: String): Int {
        try {
            return input.trim().toInt()
        } catch (e: Exception) {
            try {
                return input.trim().toDouble().toInt()
            } catch (e2: Exception) {
                throw Exception("Cannot parse: $input", e2)
            }
        }
    }

    // naming: FunctionNaming (non-conventional name)
    fun compute_sum(a: Int, b: Int) = a + b

    // naming: VariableNaming (single letter)
    fun buildList(): List<String> {
        val l = mutableListOf<String>()
        for (i in 0 until 10) {
            val s = "item-$i"
            l.add(s)
        }
        return l
    }

    // style: UnusedPrivateMember, MagicNumber
    private val LIMIT = 42

    fun checkLimit(x: Int): Boolean = x < LIMIT

    // complexity: LongMethod
    fun longComputation(values: List<Double>): Map<String, Double> {
        val result = mutableMapOf<String, Double>()
        if (values.isEmpty()) return result

        var sum = 0.0
        var min = values[0]
        var max = values[0]
        for (v in values) {
            sum += v
            if (v < min) min = v
            if (v > max) max = v
        }
        val mean = sum / values.size

        var variance = 0.0
        for (v in values) variance += (v - mean) * (v - mean)
        variance /= values.size

        val sorted = values.sorted()
        val median = if (sorted.size % 2 == 0)
            (sorted[sorted.size / 2 - 1] + sorted[sorted.size / 2]) / 2.0
        else sorted[sorted.size / 2]

        result["sum"] = sum
        result["min"] = min
        result["max"] = max
        result["mean"] = mean
        result["variance"] = variance
        result["median"] = median
        result["count"] = values.size.toDouble()
        return result
    }
}

// style: WildcardImport (import java.io.*, java.util.* above)
// naming: ObjectNaming
object config {
    const val MAX_RETRIES = 3
    const val TIMEOUT_MS = 5000L
}

// potential-bugs: UnreachableCode, UseCheckOrError
fun validate(x: Int): Boolean {
    if (x < 0) return false
    if (x == 0) return false
    return true
    @Suppress("UNREACHABLE_CODE")
    return false
}

// complexity: CyclomaticComplexMethod with early returns
fun classify(score: Int): String {
    if (score < 0) return "invalid"
    if (score < 10) return "F"
    if (score < 20) return "D"
    if (score < 40) return "C"
    if (score < 60) return "B-"
    if (score < 70) return "B"
    if (score < 80) return "B+"
    if (score < 90) return "A-"
    if (score < 95) return "A"
    return "A+"
}

// naming: PackageNaming, TopLevelPropertyNaming
val globalCache = HashMap<String, Any>()

class EventBus {
    private val listeners = mutableMapOf<String, MutableList<(Any) -> Unit>>()

    fun subscribe(event: String, handler: (Any) -> Unit) {
        listeners.getOrPut(event) { mutableListOf() }.add(handler)
    }

    fun publish(event: String, payload: Any) {
        listeners[event]?.forEach { it(payload) }
    }

    // complexity: LargeClass proxy methods — counts towards class size
    fun subscribeAll(events: List<String>, handler: (Any) -> Unit) =
        events.forEach { subscribe(it, handler) }

    fun publishAll(events: Map<String, Any>) =
        events.forEach { (k, v) -> publish(k, v) }
}

// potential-bugs: EqualsAlwaysReturnsTrueOrFalse
data class Point(val x: Int, val y: Int) {
    fun distanceTo(other: Point): Double {
        val dx = (x - other.x).toDouble()
        val dy = (y - other.y).toDouble()
        return Math.sqrt(dx * dx + dy * dy)
    }

    // style: MagicNumber
    fun isOrigin(): Boolean = x == 0 && y == 0

    fun scale(factor: Double) = Point((x * factor).toInt(), (y * factor).toInt())
}

// naming: ClassNaming (non-UpperCamelCase — lowercase first)
class matrix(val rows: Int, val cols: Int) {
    private val data = Array(rows) { DoubleArray(cols) }

    operator fun get(r: Int, c: Int) = data[r][c]
    operator fun set(r: Int, c: Int, v: Double) { data[r][c] = v }

    // complexity: LongMethod
    fun multiply(other: matrix): matrix {
        require(cols == other.rows) { "Dimension mismatch: $cols != ${other.rows}" }
        val result = matrix(rows, other.cols)
        for (i in 0 until rows) {
            for (j in 0 until other.cols) {
                var s = 0.0
                for (k in 0 until cols) s += data[i][k] * other.data[k][j]
                result[i, j] = s
            }
        }
        return result
    }
}
