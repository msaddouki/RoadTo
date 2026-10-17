package org.roadto.roadto

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Runs during a trip only, so Android keeps the position coming and the app
 * alive with the phone screen off or RoadTo closed (driving with Android
 * Auto). Its notification ("Guidage en cours") is the system's requirement
 * and opens RoadTo.
 */
class NavigationService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION else 0
        try {
            ServiceCompat.startForeground(this, NOTIFICATION_ID, notification(this), type)
        } catch (e: RuntimeException) {
            // Not allowed from the background on recent Android, or no
            // location permission: the trip goes on while RoadTo is shown.
            Log.w(TAG, "No foreground service: ${e.message}")
            stopSelf()
        }
        return START_NOT_STICKY
    }

    /** "org.roadto/navigation": `start` and `stop`, with the trip. */
    class Channel(private val context: Context, messenger: BinaryMessenger) {
        init {
            MethodChannel(messenger, "org.roadto/navigation").setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> result.success(start())
                    "stop" -> {
                        context.stopService(Intent(context, NavigationService::class.java))
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }

        private fun start(): Boolean =
            try {
                context.startForegroundService(Intent(context, NavigationService::class.java))
                true
            } catch (e: RuntimeException) {
                Log.w(TAG, "Cannot start the navigation service: ${e.message}")
                false
            }
    }

    companion object {
        private const val TAG = "RoadTo"
        private const val NOTIFICATION_ID = 1
        private const val CHANNEL_ID = "navigation"

        fun notification(context: Context): Notification {
            val manager = context.getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "Guidage", NotificationManager.IMPORTANCE_LOW).apply {
                    description = "Pendant un trajet, pour garder le guidage écran éteint."
                },
            )
            val open = PendingIntent.getActivity(
                context,
                0,
                Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
                PendingIntent.FLAG_IMMUTABLE,
            )
            return NotificationCompat.Builder(context, CHANNEL_ID)
                .setSmallIcon(R.drawable.car_maneuver_straight)
                .setContentTitle("Guidage en cours")
                .setContentText("Touchez pour ouvrir RoadTo.")
                .setContentIntent(open)
                .setOngoing(true)
                .setSilent(true)
                .setCategory(NotificationCompat.CATEGORY_NAVIGATION)
                .build()
        }
    }
}
