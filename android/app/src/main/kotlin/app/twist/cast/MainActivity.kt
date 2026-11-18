package app.twist.cast

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import com.cloudwebrtc.webrtc.PlaybackCapture
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var audioPermission: MethodChannel.Result? = null
    private var events: EventChannel.EventSink? = null
    private var updates: AppUpdates? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        updates = AppUpdates(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.twist.cast/updates")
            .setMethodCallHandler(updates)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "app.twist.cast/capture-events")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, sink: EventChannel.EventSink) { events = sink }
                override fun onCancel(arguments: Any?) { events = null }
            })
        PlaybackCapture.onStopped = Runnable {
            Handler(Looper.getMainLooper()).post {
                events?.success("stopped")
                stopService(Intent(this, CaptureService::class.java))
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.twist.cast/capture")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "audioPermission" -> {
                        if (Build.VERSION.SDK_INT < 29) {
                            result.error("unsupported", "Android 10 required", null)
                        } else if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) {
                            result.success(true)
                        } else if (audioPermission == null) {
                            audioPermission = result
                            requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), 4201)
                        } else result.error("busy", "Permission request in progress", null)
                    }
                    "start" -> {
                        CaptureService.ready = { result.success(null) }
                        val intent = Intent(this, CaptureService::class.java)
                            .putExtra("title", call.argument<String>("title"))
                            .putExtra("body", call.argument<String>("body"))
                        if (Build.VERSION.SDK_INT >= 26) startForegroundService(intent) else startService(intent)
                    }
                    "audio" -> {
                        try {
                            PlaybackCapture.setEnabled(call.argument<Boolean>("enabled") == true)
                            result.success(null)
                        } catch (error: RuntimeException) {
                            result.error("audio", "Internal audio capture failed", null)
                        }
                    }
                    "stop" -> {
                        PlaybackCapture.stopProjection()
                        stopService(Intent(this, CaptureService::class.java))
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.twist.cast/updates").setMethodCallHandler(null)
        updates?.dispose()
        updates = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 4201) {
            audioPermission?.success(grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED)
            audioPermission = null
        }
    }
}
