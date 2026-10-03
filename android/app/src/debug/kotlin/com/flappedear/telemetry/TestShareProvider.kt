package com.flappedear.telemetry

import android.content.ContentProvider
import android.content.ContentValues
import android.database.Cursor
import android.database.MatrixCursor
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.provider.OpenableColumns
import java.io.File
import java.io.FileNotFoundException

/**
 * Debug builds only: serves files from the app's cache folder share-fixtures/
 * as content://com.flappedear.telemetry.testshare/<name>, the way a sharing
 * app such as RaceChrono serves its export, so the integration test can send
 * the app a real ACTION_SEND (.github/scripts/android-integration-test.sh).
 * Not exported, and not part of release builds.
 */
class TestShareProvider : ContentProvider() {
    override fun onCreate() = true

    private fun fixture(uri: Uri): File {
        val name = uri.lastPathSegment ?: throw FileNotFoundException(uri.toString())
        if (name.contains('/') || name == "." || name == "..") throw FileNotFoundException(name)
        val file = File(File(context!!.cacheDir, "share-fixtures"), name)
        if (!file.isFile) throw FileNotFoundException(name)
        return file
    }

    override fun query(
        uri: Uri,
        projection: Array<out String>?,
        selection: String?,
        selectionArgs: Array<out String>?,
        sortOrder: String?,
    ): Cursor {
        val file = fixture(uri)
        val columns = projection ?: arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE)
        return MatrixCursor(columns).apply {
            addRow(
                columns.map { column ->
                    when (column) {
                        OpenableColumns.DISPLAY_NAME -> file.name
                        OpenableColumns.SIZE -> file.length()
                        else -> null
                    }
                },
            )
        }
    }

    override fun openFile(uri: Uri, mode: String): ParcelFileDescriptor =
        ParcelFileDescriptor.open(fixture(uri), ParcelFileDescriptor.MODE_READ_ONLY)

    override fun getType(uri: Uri) = "application/octet-stream"

    override fun insert(uri: Uri, values: ContentValues?): Uri? = null

    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?) = 0

    override fun update(
        uri: Uri,
        values: ContentValues?,
        selection: String?,
        selectionArgs: Array<out String>?,
    ) = 0
}
