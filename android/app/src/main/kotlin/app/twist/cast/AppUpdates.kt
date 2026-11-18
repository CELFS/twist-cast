package app.twist.cast

import android.app.Activity
import android.app.DownloadManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest
import java.util.concurrent.Executors
import java.util.zip.ZipFile

internal class ApkDownload(private val context: Context) {
    val prefs = context.getSharedPreferences("apk-update", Context.MODE_PRIVATE)
    val manager = context.getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
    val id get() = prefs.getLong("id", -1)
    private val installed get() = context.packageManager.getPackageInfo(context.packageName, 0)

    // Match the installed APK's ABI, including a 32-bit APK on a 64-bit device.
    private fun abi(): String = ZipFile(context.applicationInfo.sourceDir).use { zip ->
        Build.SUPPORTED_ABIS.first { zip.getEntry("lib/$it/libflutter.so") != null }
    }

    fun state(): Map<String, Any> {
        val version = requireNotNull(installed.versionName)
        val state = mutableMapOf<String, Any>("version" to version,
            "platform" to "android-${abi()}", "phase" to "idle", "received" to 0L, "total" to 0L,
            "targetVersion" to (prefs.getString("version", "") ?: ""))
        if (id < 0) return state
        val target = prefs.getString("version", "") ?: ""
        if (target.isNotEmpty() && compareVersions(target, version) <= 0) {
            manager.remove(id)
            prefs.edit().clear().commit()
            return state
        }
        state["phase"] = "failed"
        manager.query(DownloadManager.Query().setFilterById(id))?.use { row ->
            if (row.moveToFirst()) {
                state["phase"] = when (row.getInt(row.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS))) {
                    DownloadManager.STATUS_SUCCESSFUL -> "ready"
                    DownloadManager.STATUS_FAILED -> "failed"
                    else -> "downloading"
                }
                state["received"] = row.getLong(row.getColumnIndexOrThrow(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR))
                state["total"] = row.getLong(row.getColumnIndexOrThrow(DownloadManager.COLUMN_TOTAL_SIZE_BYTES))
            }
        }
        return state
    }

    fun download(version: String, url: String, hash: String) {
        require(Regex("[0-9]+\\.[0-9]+\\.[0-9]+").matches(version))
        require(compareVersions(version, requireNotNull(installed.versionName)) > 0)
        require(Regex("[a-f0-9]{64}").matches(hash))
        val filename = "twist-cast-$version-android-${abi()}.apk"
        require(url == "https://github.com/CELFS/twist-cast/releases/download/v$version/$filename")
        if (prefs.getString("hash", "") == hash && state()["phase"] in listOf("downloading", "ready")) return
        if (id >= 0) manager.remove(id)
        val localName = "$hash.apk"
        val destination = File(context.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS), localName)
        if (destination.exists()) check(destination.delete())
        val request = DownloadManager.Request(Uri.parse(url))
            .setTitle("TwistCast v$version")
            .setMimeType("application/vnd.android.package-archive")
            .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE)
            .setDestinationInExternalFilesDir(context, Environment.DIRECTORY_DOWNLOADS, localName)
        val next = manager.enqueue(request)
        prefs.edit().putLong("id", next).putString("version", version).putString("hash", hash)
            .putString("file", destination.absolutePath).commit()
    }

    fun verify(downloadId: Long): Uri {
        check(downloadId == id && state()["phase"] == "ready")
        val uri = requireNotNull(manager.getUriForDownloadedFile(downloadId))
        val digest = MessageDigest.getInstance("SHA-256")
        requireNotNull(context.contentResolver.openInputStream(uri)).use { input ->
            val buffer = ByteArray(65536)
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                digest.update(buffer, 0, count)
            }
        }
        val valid = digest.digest().joinToString("") { "%02x".format(it) } == prefs.getString("hash", "")
        if (!valid) { manager.remove(downloadId); error("Package checksum mismatch") }
        val flags = if (Build.VERSION.SDK_INT >= 28) PackageManager.GET_SIGNING_CERTIFICATES else PackageManager.GET_SIGNATURES
        val candidate = requireNotNull(context.packageManager.getPackageArchiveInfo(requireNotNull(prefs.getString("file", null)), flags))
        val current = context.packageManager.getPackageInfo(context.packageName, flags)
        require(candidate.packageName == context.packageName && candidate.versionName == prefs.getString("version", ""))
        val oldCode = if (Build.VERSION.SDK_INT >= 28) current.longVersionCode else current.versionCode.toLong()
        val newCode = if (Build.VERSION.SDK_INT >= 28) candidate.longVersionCode else candidate.versionCode.toLong()
        require(newCode > oldCode)
        val oldSigners = if (Build.VERSION.SDK_INT >= 28) requireNotNull(current.signingInfo).apkContentsSigners else current.signatures
        val newSigners = if (Build.VERSION.SDK_INT >= 28) requireNotNull(candidate.signingInfo).apkContentsSigners else candidate.signatures
        require(requireNotNull(oldSigners).toSet() == requireNotNull(newSigners).toSet())
        check(downloadId == id)
        return uri
    }

    private fun compareVersions(a: String, b: String): Int {
        val left = a.split('.').map { it.toInt() }
        val right = b.split('.').map { it.toInt() }
        require(left.size == 3 && right.size == 3)
        for (i in 0..2) if (left[i] != right[i]) return left[i].compareTo(right[i])
        return 0
    }
}

internal class AppUpdates(private val activity: Activity) : MethodChannel.MethodCallHandler {
    private val worker = Executors.newSingleThreadExecutor()
    private val task = ApkDownload(activity.applicationContext)

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method !in listOf("status", "download", "install")) { result.notImplemented(); return }
        worker.execute {
            try {
                val value = when (call.method) {
                    "status" -> task.state()
                    "download" -> {
                        task.download(requireNotNull(call.argument("version")), requireNotNull(call.argument("url")), requireNotNull(call.argument("sha256")))
                        null
                    }
                    else -> {
                        check(task.state()["phase"] == "ready")
                        task.prefs.edit().putString("error", call.argument<String>("failureMessage")).commit()
                        val id = task.id
                        activity.runOnUiThread {
                            try {
                                activity.startActivity(Intent(activity, UpdateInstallActivity::class.java).putExtra("id", id))
                                result.success(null)
                            } catch (error: Exception) { result.error("install", error.message, null) }
                        }
                        return@execute
                    }
                }
                activity.runOnUiThread { result.success(value) }
            } catch (error: Exception) { activity.runOnUiThread { result.error("update", error.message, null) } }
        }
    }

    fun dispose() { worker.shutdown() }
}
