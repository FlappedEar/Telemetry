package com.flappedear.telemetry

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.OpenableColumns
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.UUID
import java.util.concurrent.Executors

/**
 * Receives VBO and RCZ recordings that another app, such as RaceChrono, shares
 * to this one (ACTION_SEND and ACTION_SEND_MULTIPLE, see AndroidManifest.xml).
 *
 * Each shared file is copied off the main thread into the app's own storage,
 * files/incoming/<unique folder>/<file name>, and the copies' paths go to Dart
 * on the "com.flappedear.telemetry/incoming_recordings" channel. Until Dart
 * calls "ready", for example when the share started the app, they are held
 * here.
 */
class MainActivity : FlutterActivity() {
    private val copier = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var channel: MethodChannel? = null
    private val pending = mutableListOf<String>()
    private var ready = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "ready" -> {
                        ready = true
                        result.success(ArrayList(pending))
                        pending.clear()
                    }
                    else -> result.notImplemented()
                }
            }
        }
        receive(intent)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        channel?.setMethodCallHandler(null)
        channel = null
        ready = false
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        receive(intent)
    }

    override fun onDestroy() {
        copier.shutdown()
        super.onDestroy()
    }

    private fun receive(intent: Intent?) {
        if (intent == null || intent.getBooleanExtra(HANDLED, false)) return
        val uris = sharedUris(intent)
        if (uris.isEmpty()) return
        // A recreated activity gets the same intent again; import it once.
        intent.putExtra(HANDLED, true)
        copier.execute {
            val paths = uris.mapNotNull { copyRecording(it) }
            if (paths.isNotEmpty()) main.post { deliver(paths) }
        }
    }

    private fun deliver(paths: List<String>) {
        val target = channel
        if (ready && target != null) {
            target.invokeMethod("received", paths)
        } else {
            pending.addAll(paths)
        }
    }

    @Suppress("DEPRECATION")
    private fun sharedUris(intent: Intent): List<Uri> = when (intent.action) {
        Intent.ACTION_SEND -> listOfNotNull(
            if (Build.VERSION.SDK_INT >= 33) {
                intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
            } else {
                intent.getParcelableExtra(Intent.EXTRA_STREAM)
            },
        )
        Intent.ACTION_SEND_MULTIPLE ->
            if (Build.VERSION.SDK_INT >= 33) {
                intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)
            } else {
                intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)
            }.orEmpty()
        else -> emptyList()
    }

    /** Copies one shared VBO or RCZ file; null for other files or on failure. */
    private fun copyRecording(uri: Uri): String? {
        val name = displayName(uri) ?: return null
        if (name.substringAfterLast('.', "").lowercase() !in EXTENSIONS) return null
        val folder = File(filesDir, "incoming/${System.currentTimeMillis()}-${UUID.randomUUID()}")
        val target = File(folder, name)
        return try {
            if (!folder.mkdirs()) return null
            contentResolver.openInputStream(uri)?.use { input ->
                target.outputStream().use { output -> input.copyTo(output) }
            } ?: return null
            target.path
        } catch (error: Exception) {
            Log.w(TAG, "Could not copy a shared recording", error)
            target.delete()
            folder.delete()
            null
        }
    }

    /** The file's name without any folder part, or null when it has none. */
    private fun displayName(uri: Uri): String? {
        val name = try {
            contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
                ?.use { cursor -> if (cursor.moveToFirst()) cursor.getString(0) else null }
        } catch (error: Exception) {
            null
        } ?: uri.lastPathSegment
        return name?.substringAfterLast('/')?.takeIf { it.isNotBlank() && it != "." && it != ".." }
    }

    private companion object {
        const val CHANNEL = "com.flappedear.telemetry/incoming_recordings"
        const val HANDLED = "com.flappedear.telemetry.SHARE_HANDLED"
        const val TAG = "IncomingRecordings"
        val EXTENSIONS = setOf("vbo", "rcz")
    }
}
