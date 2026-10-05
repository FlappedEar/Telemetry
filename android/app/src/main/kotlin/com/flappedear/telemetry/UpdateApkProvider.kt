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
 * Lets Android's package installer read an update APK the app downloaded
 * (lib/update/app_updater.dart) and checked against the release's
 * SHA256SUMS.txt.
 *
 * It serves only `.apk` files directly in the cache folder "updates", read
 * only, and only to an app given a one-time read grant with the install
 * intent (not exported). A small provider of its own instead of AndroidX
 * FileProvider, so the app gains no dependency.
 */
class UpdateApkProvider : ContentProvider() {
    override fun onCreate(): Boolean = true

    private fun fileFor(uri: Uri): File {
        val context = context ?: throw FileNotFoundException("No context")
        val name = uri.pathSegments.singleOrNull()
            ?: throw FileNotFoundException("Not an update: $uri")
        val folder = File(context.cacheDir, FOLDER).canonicalFile
        val file = File(folder, name).canonicalFile
        if (file.parentFile != folder || !file.name.endsWith(".apk") || !file.isFile) {
            throw FileNotFoundException("Not an update: $uri")
        }
        return file
    }

    override fun openFile(uri: Uri, mode: String): ParcelFileDescriptor {
        if (mode != "r") throw SecurityException("Updates are read only.")
        return ParcelFileDescriptor.open(fileFor(uri), ParcelFileDescriptor.MODE_READ_ONLY)
    }

    override fun getType(uri: Uri): String = APK_TYPE

    override fun query(
        uri: Uri,
        projection: Array<out String>?,
        selection: String?,
        selectionArgs: Array<out String>?,
        sortOrder: String?,
    ): Cursor {
        val file = fileFor(uri)
        val columns = projection ?: arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE)
        val cursor = MatrixCursor(columns, 1)
        cursor.addRow(
            columns.map { column ->
                when (column) {
                    OpenableColumns.DISPLAY_NAME -> file.name
                    OpenableColumns.SIZE -> file.length()
                    else -> null
                }
            },
        )
        return cursor
    }

    override fun insert(uri: Uri, values: ContentValues?): Uri? =
        throw UnsupportedOperationException("Updates are read only.")

    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?): Int =
        throw UnsupportedOperationException("Updates are read only.")

    override fun update(
        uri: Uri,
        values: ContentValues?,
        selection: String?,
        selectionArgs: Array<out String>?,
    ): Int = throw UnsupportedOperationException("Updates are read only.")

    companion object {
        /** The cache folder lib/update/app_updater.dart downloads into. */
        const val FOLDER = "updates"
        const val APK_TYPE = "application/vnd.android.package-archive"

        fun uriFor(packageName: String, name: String): Uri = Uri.Builder()
            .scheme("content")
            .authority("$packageName.updates")
            .appendPath(name)
            .build()
    }
}
