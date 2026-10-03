package com.flappedear.telemetry

import java.io.File
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream

// The import limits of packages/telemetry_core (TelemetryImportLimits and
// maximumRecordingBytes), so a shared or picked batch never fills the app's
// storage before Dart can reject it.

/** The largest recording copied in: 128 MiB. */
const val MAXIMUM_RECORDING_BYTES = 128L * 1024 * 1024

/** The most bytes one share or pick copies in: 256 MiB. */
const val MAXIMUM_BATCH_BYTES = 256L * 1024 * 1024

/** The most files one share or pick copies in. */
const val MAXIMUM_BATCH_FILES = 64

/** Thrown when a copy would pass its byte limit. */
class TooLargeException(val limit: Long) : IOException("larger than $limit bytes")

/**
 * Copies [input] to [output] and returns the bytes copied. Throws
 * [TooLargeException] as soon as more than [limit] bytes arrive, whatever
 * size the provider reported; nothing past the limit is written.
 */
fun copyBounded(input: InputStream, output: OutputStream, limit: Long = MAXIMUM_RECORDING_BYTES): Long {
    val buffer = ByteArray(64 * 1024)
    var copied = 0L
    while (true) {
        val read = input.read(buffer)
        if (read < 0) return copied
        copied += read
        if (copied > limit) throw TooLargeException(limit)
        output.write(buffer, 0, read)
    }
}

/** The outcome of [copyIntoFolder]. */
sealed interface CopyResult {
    data class Copied(val file: File, val bytes: Long) : CopyResult
    data object TooLarge : CopyResult
    data class Failed(val error: Exception?) : CopyResult
}

/**
 * Copies what [open] returns to [folder]/[name], at most [limit] bytes. On
 * any failure, including a stream that is too large or none at all, the
 * partial file and the folder are removed.
 */
fun copyIntoFolder(folder: File, name: String, limit: Long, open: () -> InputStream?): CopyResult {
    val target = File(folder, name)
    fun cleanUp() {
        target.delete()
        folder.delete()
    }
    return try {
        if (!folder.mkdirs()) return CopyResult.Failed(null)
        val stream = open() ?: run {
            cleanUp()
            return CopyResult.Failed(null)
        }
        val bytes = stream.use { input -> target.outputStream().use { output -> copyBounded(input, output, limit) } }
        CopyResult.Copied(target, bytes)
    } catch (error: TooLargeException) {
        cleanUp()
        CopyResult.TooLarge
    } catch (error: Exception) {
        cleanUp()
        CopyResult.Failed(error)
    }
}
