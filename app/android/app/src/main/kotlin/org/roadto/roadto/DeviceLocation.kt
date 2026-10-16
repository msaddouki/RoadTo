package org.roadto.roadto

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Build
import android.os.Bundle
import android.os.Looper
import android.os.SystemClock
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Position from Android's own LocationManager, so the app needs no Google
 * Play Services (no play-services-location in the APK).
 *
 * - "org.roadto/location": `status` -> {service, permission}, `request` ->
 *   "granted" | "denied" | "deniedForever".
 * - "org.roadto/location/fixes": one map per fix (lat, lon, speed, bearing,
 *   accuracy, provider). GPS is preferred; network fixes only fill in while
 *   GPS has nothing recent (start-up, tunnels).
 */
class DeviceLocation(private val context: Context, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    /**
     * The phone screen, when shown: only it can ask for the permission. The
     * engine also runs without it, started by Android Auto (RoadToEngine).
     */
    var activity: Activity? = null

    private val manager = context.getSystemService(Context.LOCATION_SERVICE) as LocationManager
    private val methods = MethodChannel(messenger, "org.roadto/location")
    private val fixes = EventChannel(messenger, "org.roadto/location/fixes")
    private var pendingRequest: MethodChannel.Result? = null
    private var sink: EventChannel.EventSink? = null
    private var lastGpsAt = 0L // elapsedRealtime of the last GPS fix

    private val listener = object : LocationListener {
        override fun onLocationChanged(location: Location) = deliver(location)

        // Abstract before API 30: without them, older Android throws
        // AbstractMethodError when a provider changes state.
        @Deprecated("Deprecated in Java")
        override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}
        override fun onProviderEnabled(provider: String) {}
        override fun onProviderDisabled(provider: String) {}
    }

    init {
        methods.setMethodCallHandler(this)
        fixes.setStreamHandler(this)
    }

    fun dispose() {
        stopUpdates()
        methods.setMethodCallHandler(null)
        fixes.setStreamHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "status" -> result.success(
                mapOf("service" to serviceEnabled(), "permission" to if (hasAnyPermission()) "granted" else "denied")
            )
            "request" -> request(result)
            else -> result.notImplemented()
        }
    }

    private fun serviceEnabled(): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            manager.isLocationEnabled
        } else {
            manager.isProviderEnabled(LocationManager.GPS_PROVIDER) ||
                manager.isProviderEnabled(LocationManager.NETWORK_PROVIDER)
        }

    private fun granted(permission: String) =
        context.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED

    private fun hasFine() = granted(Manifest.permission.ACCESS_FINE_LOCATION)

    private fun hasAnyPermission() = hasFine() || granted(Manifest.permission.ACCESS_COARSE_LOCATION)

    private fun request(result: MethodChannel.Result) {
        if (hasAnyPermission()) {
            result.success("granted")
            return
        }
        val activity = activity
        if (activity == null) {
            // From the car, with the phone screen closed: asked when RoadTo is opened.
            result.success("denied")
            return
        }
        if (pendingRequest != null) {
            result.error("busy", "A location permission request is already running", null)
            return
        }
        pendingRequest = result
        activity.requestPermissions(
            arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION),
            REQUEST_CODE,
        )
    }

    /** Called by MainActivity.onRequestPermissionsResult. */
    fun onPermissionResult(requestCode: Int): Boolean {
        if (requestCode != REQUEST_CODE) return false
        val result = pendingRequest ?: return true
        pendingRequest = null
        result.success(
            when {
                hasAnyPermission() -> "granted"
                // Refused with "don't ask again" (or by policy): the system no
                // longer shows the dialog, only the app settings can grant it.
                activity?.shouldShowRequestPermissionRationale(Manifest.permission.ACCESS_FINE_LOCATION) == false -> "deniedForever"
                else -> "denied"
            }
        )
        return true
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        if (!hasAnyPermission()) {
            events.error("denied", "Location permission not granted", null)
            return
        }
        sink = events
        lastGpsAt = 0L
        val providers = buildList {
            if (hasFine() && manager.allProviders.contains(LocationManager.GPS_PROVIDER)) add(LocationManager.GPS_PROVIDER)
            if (manager.allProviders.contains(LocationManager.NETWORK_PROVIDER)) add(LocationManager.NETWORK_PROVIDER)
        }
        if (providers.isEmpty()) {
            events.error("unavailable", "No location provider on this device", null)
            sink = null
            return
        }
        try {
            // A recent last known position gives the map something to show
            // before the first fix.
            providers.mapNotNull { manager.getLastKnownLocation(it) }
                .filter { ageMs(it) < 120_000 }
                .maxByOrNull { it.time }
                ?.let { deliver(it) }
            for (p in providers) {
                manager.requestLocationUpdates(p, 1000L, 0f, listener, Looper.getMainLooper())
            }
        } catch (e: SecurityException) {
            stopUpdates()
            events.error("denied", e.message, null)
        }
    }

    override fun onCancel(arguments: Any?) = stopUpdates()

    private fun stopUpdates() {
        manager.removeUpdates(listener)
        sink = null
    }

    private fun ageMs(location: Location) =
        (SystemClock.elapsedRealtimeNanos() - location.elapsedRealtimeNanos) / 1_000_000

    private fun deliver(location: Location) {
        val events = sink ?: return
        val now = SystemClock.elapsedRealtime()
        if (location.provider == LocationManager.GPS_PROVIDER) {
            lastGpsAt = now
        } else if (lastGpsAt != 0L && now - lastGpsAt < GPS_PRIORITY_MS) {
            return // a recent GPS fix is better than a network one
        }
        events.success(
            mapOf(
                "lat" to location.latitude,
                "lon" to location.longitude,
                "speed" to if (location.hasSpeed()) location.speed.toDouble() else -1.0,
                "bearing" to if (location.hasBearing()) location.bearing.toDouble() else -1.0,
                "accuracy" to if (location.hasAccuracy()) location.accuracy.toDouble() else -1.0,
                "provider" to (location.provider ?: ""),
            )
        )
    }

    companion object {
        private const val REQUEST_CODE = 4242
        private const val GPS_PRIORITY_MS = 10_000L
    }
}
