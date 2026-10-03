package com.flappedear.telemetry

import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.InputStream
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class BoundedCopyTest {
    @Test
    fun copiesAFileUpToTheLimit() {
        val bytes = ByteArray(1000) { it.toByte() }
        val output = ByteArrayOutputStream()
        assertEquals(1000L, copyBounded(ByteArrayInputStream(bytes), output, limit = 1000))
        assertArrayEquals(bytes, output.toByteArray())
    }

    @Test
    fun stopsOneBytePastTheLimit() {
        val output = ByteArrayOutputStream()
        assertThrows(TooLargeException::class.java) {
            copyBounded(ByteArrayInputStream(ByteArray(1001)), output, limit = 1000)
        }
        assertTrue(output.size() <= 1000)
    }

    /** A provider stream that never ends, as a lying or broken provider might send. */
    @Test
    fun stopsAnEndlessStreamAtTheLimit() {
        var served = 0L
        val endless = object : InputStream() {
            override fun read(): Int = 0
            override fun read(b: ByteArray, off: Int, len: Int): Int {
                served += len
                return len
            }
        }
        val output = ByteArrayOutputStream()
        assertThrows(TooLargeException::class.java) {
            copyBounded(endless, output, limit = 1L shl 20)
        }
        assertTrue(output.size() <= 1 shl 20)
        assertTrue(served < (1L shl 20) + 128 * 1024)
    }

    @Test
    fun matchesTheDartImportLimit() {
        assertEquals(128L * 1024 * 1024, MAXIMUM_RECORDING_BYTES)
    }
}

class CopyIntoFolderTest {
    @get:org.junit.Rule
    val temp = org.junit.rules.TemporaryFolder()

    @Test
    fun keepsACopyWithinTheLimit() {
        val folder = java.io.File(temp.root, "picked/1")
        val result = copyIntoFolder(folder, "day.vbo", limit = 10) { ByteArrayInputStream(ByteArray(10)) }
        assertTrue(result is CopyResult.Copied)
        assertEquals(10L, java.io.File(folder, "day.vbo").length())
    }

    @Test
    fun removesATooLargeCopy() {
        val folder = java.io.File(temp.root, "picked/2")
        val result = copyIntoFolder(folder, "day.vbo", limit = 10) { ByteArrayInputStream(ByteArray(11)) }
        assertEquals(CopyResult.TooLarge, result)
        assertTrue(!folder.exists())
    }

    @Test
    fun removesTheCopyWhenReadingFails() {
        val folder = java.io.File(temp.root, "picked/3")
        val failing = object : InputStream() {
            var reads = 0
            override fun read(): Int = throw java.io.IOException("gone")
            override fun read(b: ByteArray, off: Int, len: Int): Int {
                if (reads++ > 0) throw java.io.IOException("gone")
                return 5
            }
        }
        val result = copyIntoFolder(folder, "day.vbo", limit = 10) { failing }
        assertTrue(result is CopyResult.Failed)
        assertTrue(!folder.exists())
    }

    @Test
    fun removesTheFolderWhenThereIsNoStream() {
        val folder = java.io.File(temp.root, "picked/4")
        val result = copyIntoFolder(folder, "day.vbo", limit = 10) { null }
        assertTrue(result is CopyResult.Failed)
        assertTrue(!folder.exists())
    }
}
