package com.flappedear.telemetry

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.OpenableColumns
import android.util.Log
import android.widget.Toast
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
 *
 * "pick" on the "com.flappedear.telemetry/recording_picker" channel opens the
 * system file picker and copies the chosen files the same way, keeping each
 * file's own name. The file_selector plugin is not used for this on Android:
 * it renames a copy after the type the provider reports, and providers report
 * a .vbo file as application/octet-stream, so "session.vbo" arrived as
 * "session.bin" and was not imported as a recording.
 *
 * Copies are bounded by the Dart import's limits (BoundedCopy.kt): a file
 * larger than [MAXIMUM_RECORDING_BYTES] is not copied (its size is checked
 * first where the provider reports one, and the copy stops at the limit
 * regardless), one share or pick copies at most [MAXIMUM_BATCH_BYTES] and
 * [MAXIMUM_BATCH_FILES] files, and the user is told once what was left out.
 */
class MainActivity : FlutterActivity() {
    private val copier = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var channel: MethodChannel? = null
    private val pending = mutableListOf<String>()
    private var ready = false
    private var picker: MethodChannel? = null
    private var pickResult: MethodChannel.Result? = null

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
        picker = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PICKER_CHANNEL).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "pick" -> pick(result)
                    else -> result.notImplemented()
                }
            }
        }
        receive(intent)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        channel?.setMethodCallHandler(null)
        channel = null
        picker?.setMethodCallHandler(null)
        picker = null
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
            val recordings = uris.filter { uri ->
                displayName(uri)?.substringAfterLast('.', "")?.lowercase() in EXTENSIONS
            }
            val paths = copyBatch(recordings, "incoming")
            if (paths.isNotEmpty()) main.post { deliver(paths) }
        }
    }

    /** Opens the system picker for any file; the import reports what is not a recording. */
    private fun pick(result: MethodChannel.Result) {
        if (pickResult != null) {
            result.error("busy", "The file picker is already open.", null)
            return
        }
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT)
            .addCategory(Intent.CATEGORY_OPENABLE)
            .setType("*/*")
            .putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
        try {
            @Suppress("DEPRECATION")
            startActivityForResult(intent, PICK_REQUEST)
            pickResult = result
        } catch (error: ActivityNotFoundException) {
            result.error("unavailable", "No app can open files on this device.", null)
        }
    }

    @Deprecated("Deprecated in Java")
    @Suppress("DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != PICK_REQUEST) {
            super.onActivityResult(requestCode, resultCode, data)
            return
        }
        val result = pickResult ?: return
        pickResult = null
        val uris = if (resultCode == Activity.RESULT_OK) pickedUris(data) else emptyList()
        if (uris.isEmpty()) {
            result.success(emptyList<String>())
            return
        }
        copier.execute {
            val paths = copyBatch(uris, "picked")
            main.post { result.success(paths) }
        }
    }

    private fun pickedUris(data: Intent?): List<Uri> {
        if (data == null) return emptyList()
        val clip = data.clipData ?: return listOfNotNull(data.data)
        return (0 until clip.itemCount).mapNotNull { clip.getItemAt(it).uri }
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

    /**
     * Copies [uris] to files/<area>/<unique folder>/<own name> within the batch
     * limits and returns the copies' paths. A batch of more than
     * [MAXIMUM_BATCH_FILES] files copies nothing.
     */
    private fun copyBatch(uris: List<Uri>, area: String): List<String> {
        if (uris.size > MAXIMUM_BATCH_FILES) {
            tell(getString(R.string.too_many_files, MAXIMUM_BATCH_FILES))
            return emptyList()
        }
        val paths = mutableListOf<String>()
        var budget = MAXIMUM_BATCH_BYTES
        var leftOut = false
        for (uri in uris) {
            val name = displayName(uri) ?: continue
            val limit = minOf(MAXIMUM_RECORDING_BYTES, budget)
            val reported = reportedSize(uri)
            if (limit <= 0 || (reported != null && reported > limit)) {
                leftOut = true
                continue
            }
            val folder = File(filesDir, "$area/${System.currentTimeMillis()}-${UUID.randomUUID()}")
            when (val result = copyIntoFolder(folder, name, limit) { contentResolver.openInputStream(uri) }) {
                is CopyResult.Copied -> {
                    paths.add(result.file.path)
                    budget -= result.bytes
                }
                CopyResult.TooLarge -> leftOut = true
                is CopyResult.Failed -> Log.w(TAG, "Could not copy $name", result.error)
            }
        }
        if (leftOut) {
            tell(
                getString(
                    R.string.files_too_large,
                    (MAXIMUM_RECORDING_BYTES / MIB).toInt(),
                    (MAXIMUM_BATCH_BYTES / MIB).toInt(),
                ),
            )
        }
        return paths
    }

    /** The size the provider reports for [uri], or null when it reports none. */
    private fun reportedSize(uri: Uri): Long? = try {
        contentResolver.query(uri, arrayOf(OpenableColumns.SIZE), null, null, null)?.use { cursor ->
            if (cursor.moveToFirst() && !cursor.isNull(0)) cursor.getLong(0) else null
        }
    } catch (error: Exception) {
        null
    }

    private fun tell(message: String) {
        Log.w(TAG, message)
        val context = applicationContext
        main.post { Toast.makeText(context, message, Toast.LENGTH_LONG).show() }
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
        const val PICKER_CHANNEL = "com.flappedear.telemetry/recording_picker"
        const val PICK_REQUEST = 0x46E7
        const val HANDLED = "com.flappedear.telemetry.SHARE_HANDLED"
        const val TAG = "IncomingRecordings"
        val EXTENSIONS = setOf("vbo", "rcz")
        const val MIB = 1024L * 1024
    }
}
