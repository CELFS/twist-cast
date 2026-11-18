package app.twist.cast

import android.app.Activity
import android.content.Intent
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

class DiagnosticExport(private val activity: Activity) : MethodChannel.MethodCallHandler {
    private var pending: MethodChannel.Result? = null
    private var data: ByteArray? = null
    private val writer = Executors.newSingleThreadExecutor()

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "export") { result.notImplemented(); return }
        if (pending != null) { result.error("busy", null, null); return }
        val bytes = call.argument<String>("json")?.toByteArray(Charsets.UTF_8)
        if (bytes == null || bytes.size > 4 * 1024 * 1024) {
            result.error("size", null, null); return
        }
        pending = result
        data = bytes
        try {
            activity.startActivityForResult(Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "application/json"
                putExtra(Intent.EXTRA_TITLE, "twistcast-sender-${System.currentTimeMillis()}.json")
            }, REQUEST)
        } catch (_: Exception) { finish(false, true) }
    }

    fun onResult(request: Int, code: Int, intent: Intent?) {
        if (request != REQUEST || pending == null) return
        val uri = intent?.data
        val bytes = data
        if (code != Activity.RESULT_OK || uri == null || bytes == null) { finish(false); return }
        writer.execute {
            val saved = try {
                val stream = activity.contentResolver.openOutputStream(uri, "wt")
                    ?: throw IllegalStateException()
                stream.use { it.write(bytes) }
                true
            } catch (_: Exception) { false }
            Handler(Looper.getMainLooper()).post { finish(saved, !saved) }
        }
    }

    private fun finish(saved: Boolean, error: Boolean = false) {
        val result = pending
        pending = null
        data = null
        if (error) result?.error("export", null, null) else result?.success(saved)
    }
    fun dispose() { finish(false); writer.shutdown() }
    companion object { const val REQUEST = 4202 }
}
