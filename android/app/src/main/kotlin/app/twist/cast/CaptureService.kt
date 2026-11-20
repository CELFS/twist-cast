package app.twist.cast

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import com.cloudwebrtc.webrtc.PlaybackCapture

/** Keeps the user-approved projection alive while another app is on screen. */
class CaptureService : Service() {
    companion object {
        var ready: (() -> Unit)? = null
        var running = false
            private set
    }
    override fun onBind(intent: Intent?): IBinder? = null
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val title = intent?.getStringExtra("title") ?: return START_NOT_STICKY
        val body = intent.getStringExtra("body") ?: return START_NOT_STICKY
        val manager = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= 26) {
            manager.createNotificationChannel(NotificationChannel("cast", title, NotificationManager.IMPORTANCE_LOW))
        }
        val open = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE)
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, "cast") else Notification.Builder(this)
        val notification = builder.setContentTitle(title).setContentText(body)
            .setSmallIcon(R.mipmap.ic_launcher).setOngoing(true).setContentIntent(open).build()
        if (Build.VERSION.SDK_INT >= 29) startForeground(4201, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION)
        else startForeground(4201, notification)
        running = true
        ready?.invoke()
        ready = null
        return START_NOT_STICKY
    }
    override fun onDestroy() {
        running = false
        RemoteTouchService.active?.cancelTouch()
        PlaybackCapture.stopProjection()
        super.onDestroy()
    }
    override fun onTaskRemoved(rootIntent: Intent?) {
        PlaybackCapture.onStopped?.run()
        stopSelf()
    }
}
