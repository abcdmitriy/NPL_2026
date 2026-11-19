import java.io.File
import java.util.Random
import java.util.concurrent.ExecutionException
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

class BlockMatrix(val n: Int, val b: Int) {

    init {
        require(n > 0) { "Размер матрицы должен быть положительным" }
        require(b > 0) { "Размер блока должен быть положительным" }
        require(n % b == 0) { "N=$n не кратно B=$b" }
    }

    val numBlocks = n / b

    val blocks: Array<Array<IntArray>> =
        Array(numBlocks) {
            Array(numBlocks) {
                IntArray(b * b)
            }
        }

    fun get(r: Int, c: Int): Int {
        require(r in 0 until n && c in 0 until n)
        return blocks[r / b][c / b][(r % b) * b + (c % b)]
    }

    fun set(r: Int, c: Int, v: Int) {
        require(r in 0 until n && c in 0 until n)
        blocks[r / b][c / b][(r % b) * b + (c % b)] = v
    }

    fun copy(): BlockMatrix {
        val m = BlockMatrix(n, b)

        for (i in 0 until numBlocks) {
            for (j in 0 until numBlocks) {
                System.arraycopy(
                    blocks[i][j], 0,
                    m.blocks[i][j], 0,
                    b * b
                )
            }
        }

        return m
    }

    fun printMatrix() {
        for (i in 0 until n) {
            for (j in 0 until n) {
                print("%4d".format(get(i, j)))
            }
            println()
        }
    }
}

fun transposeBlockInPlace(blk: IntArray, b: Int) {
    for (r in 0 until b) {
        for (c in r + 1 until b) {
            val i1 = r * b + c
            val i2 = c * b + r

            val t = blk[i1]
            blk[i1] = blk[i2]
            blk[i2] = t
        }
    }
}

fun transposeSequential(m: BlockMatrix) {
    val nb = m.numBlocks
    val b = m.b
    val blocks = m.blocks

    for (i in 0 until nb) {
        for (j in i until nb) {
            if (i == j) {
                transposeBlockInPlace(blocks[i][i], b)
            } else {
                transposeBlockInPlace(blocks[i][j], b)
                transposeBlockInPlace(blocks[j][i], b)

                val t = blocks[i][j]
                blocks[i][j] = blocks[j][i]
                blocks[j][i] = t
            }
        }
    }
}

fun transposeParallel(m: BlockMatrix, threads: Int) {
    require(threads > 0) {
        "Количество потоков должно быть положительным"
    }

    val ex = Executors.newFixedThreadPool(threads)
    val nb = m.numBlocks
    val b = m.b
    val blocks = m.blocks

    val futures = mutableListOf<java.util.concurrent.Future<*>>()

    try {
        for (i in 0 until nb) {
            for (j in i until nb) {
                val ii = i
                val jj = j

                futures.add(ex.submit {
                    if (ii == jj) {
                        transposeBlockInPlace(blocks[ii][ii], b)
                    } else {
                        transposeBlockInPlace(blocks[ii][jj], b)
                        transposeBlockInPlace(blocks[jj][ii], b)

                        val t = blocks[ii][jj]
                        blocks[ii][jj] = blocks[jj][ii]
                        blocks[jj][ii] = t
                    }
                })
            }
        }

        for (future in futures) {
            future.get()
        }

    } catch (e: InterruptedException) {
        futures.forEach { it.cancel(true) }
        Thread.currentThread().interrupt()
        throw IllegalStateException(
            "Ожидание выполнения задач было прервано", e
        )

    } catch (e: ExecutionException) {
        futures.forEach { it.cancel(true) }
        throw IllegalStateException(
            "Ошибка при параллельном транспонировании",
            e.cause ?: e
        )

    } finally {
        ex.shutdown()

        if (!ex.awaitTermination(1, TimeUnit.HOURS)) {
            ex.shutdownNow()

            if (!ex.awaitTermination(1, TimeUnit.HOURS)) {
                throw IllegalStateException(
                    "Пул потоков не завершил работу"
                )
            }
        }
    }
}

fun transpose(
    m: BlockMatrix,
    inPlace: Boolean,
    threads: Int
): BlockMatrix {
    val result = if (inPlace) m else m.copy()

    transposeParallel(result, threads)

    return result
}

fun matricesEqual(a: BlockMatrix, b: BlockMatrix): Boolean {
    if (a.n != b.n || a.b != b.b) return false

    for (i in 0 until a.numBlocks) {
        for (j in 0 until a.numBlocks) {
            for (k in 0 until a.b * a.b) {
                if (a.blocks[i][j][k] != b.blocks[i][j][k]) {
                    return false
                }
            }
        }
    }

    return true
}

fun verify(
    original: BlockMatrix,
    transposed: BlockMatrix,
    sample: Int = 10000
): Boolean {
    require(original.n == transposed.n)
    require(original.b == transposed.b)
    require(sample >= 0)

    val rnd = Random()

    repeat(sample) {
        val r = rnd.nextInt(original.n)
        val c = rnd.nextInt(original.n)

        if (original.get(r, c) != transposed.get(c, r)) {
            return false
        }
    }

    val back = transposed.copy()
    transposeSequential(back)

    return matricesEqual(original, back)
}

fun readFromFile(path: String): BlockMatrix {
    val lines = File(path).readLines().filter {
        it.isNotBlank()
    }

    require(lines.isNotEmpty()) {
        "Файл пустой"
    }

    val header = lines[0].trim().split(Regex("\\s+"))

    require(header.size == 2) {
        "Первая строка должна содержать N и B"
    }

    val n = header[0].toIntOrNull()
        ?: throw IllegalArgumentException("Некорректный размер N")

    val b = header[1].toIntOrNull()
        ?: throw IllegalArgumentException("Некорректный размер B")

    val m = BlockMatrix(n, b)

    require(lines.size == n + 1) {
        "Ожидалось $n строк матрицы, получено ${lines.size - 1}"
    }

    for (i in 0 until n) {
        val row = lines[i + 1].trim()
            .split(Regex("\\s+"))

        require(row.size == n) {
            "Строка ${i + 1} должна содержать $n элементов"
        }

        for (j in 0 until n) {
            val value = row[j].toIntOrNull()
                ?: throw IllegalArgumentException(
                    "Некорректное число в строке ${i + 1}"
                )

            m.set(i, j, value)
        }
    }

    return m
}

fun generateRandom(n: Int, b: Int): BlockMatrix {
    val m = BlockMatrix(n, b)
    val r = Random()

    for (i in 0 until n) {
        for (j in 0 until n) {
            m.set(i, j, r.nextInt(100))
        }
    }

    return m
}

fun benchSequential(m: BlockMatrix, runs: Int): Double {
    require(runs > 0)

    var total = 0L

    repeat(runs) {
        val c = m.copy()

        val t0 = System.nanoTime()
        transposeSequential(c)
        val t1 = System.nanoTime()

        total += t1 - t0
    }

    return total / 1_000_000.0 / runs
}

fun benchParallel(
    m: BlockMatrix,
    threads: Int,
    runs: Int
): Double {
    require(runs > 0)
    require(threads > 0)

    var total = 0L

    repeat(runs) {
        val c = m.copy()

        val t0 = System.nanoTime()
        transposeParallel(c, threads)
        val t1 = System.nanoTime()

        total += t1 - t0
    }

    return total / 1_000_000.0 / runs
}

fun main() {
    println("=== Задача 1.2: Параллельное транспонирование блочной матрицы ===\n")

    println("--- Демонстрация транспонирования ---")

    val demo = if (File("input.txt").exists()) {
        println("Матрица прочитана из input.txt")
        readFromFile("input.txt")
    } else {
        println("input.txt не найден, генерируем матрицу 8x8")
        generateRandom(8, 2)
    }

    println("\nИсходная матрица:")
    demo.printMatrix()

    val originalCopy = demo.copy()

    val demoTransposed = transpose(
        demo,
        inPlace = false,
        threads = 4
    )

    println("\nТранспонированная матрица:")
    demoTransposed.printMatrix()

    val ok = verify(demo, demoTransposed)

    println(
        "\nПроверка корректности: ${
            if (ok) "OK" else "FAIL"
        }"
    )

    val originalPreserved = matricesEqual(demo, originalCopy)

    println(
        "Проверка сохранения оригинала: ${
            if (originalPreserved) "OK" else "FAIL"
        }\n"
    )

    println("=== Замеры производительности ===")

    val N = 4096
    val blockSizes = listOf(32, 64, 128)
    val threadCounts = listOf(1, 2, 4, 8, 16)
    val runs = 5

    val warmup = generateRandom(512, 32)

    transposeSequential(warmup.copy())
    transposeParallel(warmup.copy(), 4)

    for (B in blockSizes) {
        println("\n--- Размер блока B = $B, матрица N = $N ---")

        val original = generateRandom(N, B)

        val timeSeq = benchSequential(original, runs)

        println(
            "Последовательно (среднее за $runs прогонов): %.2f мс"
                .format(timeSeq)
        )

        println("  потоков | время, мс | ускорение")
        println("  --------+-----------+----------")

        for (th in threadCounts) {
            val timePar = benchParallel(original, th, runs)
            val speedup = timeSeq / timePar

            println(
                "  %7d | %9.2f | %.2fx"
                    .format(th, timePar, speedup)
            )
        }
    }

    println("\n=== Выполнение программы завершено ===")
}