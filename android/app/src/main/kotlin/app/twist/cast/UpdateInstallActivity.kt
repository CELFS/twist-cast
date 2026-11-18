package app.twist.cast

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.widget.Toast

class UpdateInstallActivity : Activity() {
    private val task by lazy { ApkDownload(this) }
    private var waiting = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        waiting = savedInstanceState?.getBoolean("waiting") == true
        if (!waiting) prepare()
    }

    override fun onSaveInstanceState(state: Bundle) {
        state.putBoolean("waiting", waiting)
        super.onSaveInstanceState(state)
    }

    private fun prepare() {
        if (intent.getLongExtra("id", -1) != task.id) { finish(); return }
        if (Build.VERSION.SDK_INT >= 26 && !packageManager.canRequestPackageInstalls()) {
            waiting = true
            startActivityForResult(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:$packageName")), 1)
            return
        }
        val id = task.id
        Thread {
            try {
                val uri = task.verify(id)
                runOnUiThread {
                    if (!isDestroyed && !isFinishing) {
                        try {
                            startActivity(Intent(Intent.ACTION_VIEW).setDataAndType(uri, "application/vnd.android.package-archive")
                                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION))
                            finish()
                        } catch (_: Exception) { failed() }
                    }
                }
            } catch (_: Exception) { runOnUiThread { failed() } }
        }.start()
    }

    private fun failed() {
        if (isDestroyed) return
        Toast.makeText(this, task.prefs.getString("error", ""), Toast.LENGTH_LONG).show()
        finish()
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        waiting = false
        if (requestCode == 1 && Build.VERSION.SDK_INT >= 26 && packageManager.canRequestPackageInstalls()) prepare()
        else finish()
    }
}
