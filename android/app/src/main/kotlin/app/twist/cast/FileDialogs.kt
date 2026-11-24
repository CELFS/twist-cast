package app.twist.cast

import android.app.Activity
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.provider.OpenableColumns
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.util.concurrent.Executors

class FileDialogs(private val activity: Activity) : MethodChannel.MethodCallHandler {
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var pending: MethodChannel.Result? = null
    private var payload: ByteArray? = null
    private var limit = 0

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (pending != null) { result.error("busy", null, null); return }
        val intent = when (call.method) {
            "pick" -> {
                limit = call.argument<Int>("limit") ?: 0
                Intent(Intent.ACTION_OPEN_DOCUMENT)
            }
            "save" -> {
                payload = call.argument<ByteArray>("bytes")
                if (payload == null) { result.error("arguments", null, null); return }
                Intent(Intent.ACTION_CREATE_DOCUMENT).putExtra(Intent.EXTRA_TITLE, call.argument<String>("name"))
            }
            else -> { result.notImplemented(); return }
        }
        pending = result
        intent.type = if (payload == null) "*/*" else "application/octet-stream"
        intent.addCategory(Intent.CATEGORY_OPENABLE)
        try { activity.startActivityForResult(intent, REQUEST) }
        catch (_: Exception) { finish(null, "dialog") }
    }

    fun onResult(request: Int, code: Int, intent: Intent?) {
        if (request != REQUEST || pending == null) return
        val uri = intent?.data
        if (code != Activity.RESULT_OK || uri == null) { finish(null); return }
        val bytes = payload
        worker.execute {
            val resolver = activity.contentResolver
            var error: String? = null
            val value: Any? = try {
                if (bytes != null) {
                    val stream = resolver.openOutputStream(uri, "wt") ?: throw IOException()
                    stream.use { it.write(bytes) }
                    true
                } else {
                    var name = "file"
                    resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE), null, null, null)?.use {
                        if (it.moveToFirst()) {
                            name = it.getString(0) ?: name
                            if (!it.isNull(1) && it.getLong(1) > limit) throw TooLarge()
                        }
                    }
                    val stream = resolver.openInputStream(uri) ?: throw IOException()
                    val output = ByteArrayOutputStream()
                    stream.use { input ->
                        val buffer = ByteArray(65536)
                        while (true) {
                            val n = input.read(buffer)
                            if (n < 0) break
                            if (n > limit - output.size()) throw TooLarge()
                            output.write(buffer, 0, n)
                        }
                    }
                    mapOf("name" to name, "bytes" to output.toByteArray())
                }
            } catch (_: TooLarge) { error = "size"; null }
              catch (_: Exception) { error = "file"; null }
            main.post { finish(value, error) }
        }
    }

    private class TooLarge : IOException()
    private fun finish(value: Any?, error: String? = null) {
        val result = pending
        pending = null
        payload = null
        if (error == null) result?.success(value) else result?.error(error, null, null)
    }
    fun dispose() { finish(null); worker.shutdown() }
    companion object { private const val REQUEST = 4210 }
}
