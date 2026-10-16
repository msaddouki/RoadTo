package org.roadto.roadto.car

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/** The next maneuver, as the Flutter guidance sees it. */
data class CarManeuver(
    /** Valhalla maneuver type (see [CarManeuvers]). */
    val type: Int,
    /** What to do, in French ("Tournez à droite dans Rue Garibaldi."). */
    val instruction: String,
    val street: String?,
    val distanceM: Double,
)

/** An alert ahead on the route. */
data class CarAlert(val label: String, val distanceM: Double, val confirmations: Int)

/** "Toujours là ?" for an alert the car just passed. */
data class CarConfirmation(val id: String, val label: String)

/**
 * What the car screen shows. Sent by the Flutter side (lib/services/car_link.dart)
 * on every change; the car app never computes guidance itself.
 */
data class CarState(
    val navigating: Boolean = false,
    val maneuver: CarManeuver? = null,
    val remainingM: Double = 0.0,
    val remainingS: Double = 0.0,
    val arrivalEpochMs: Long = 0,
    val lat: Double = 0.0,
    val lon: Double = 0.0,
    val bearing: Double? = null,
    val speedKph: Int? = null,
    val speedLimitKph: Int? = null,
    /** Style of the map shown on the phone: a URL or a local file path. */
    val mapStyle: String? = null,
    val alert: CarAlert? = null,
    val confirmation: CarConfirmation? = null,
    /** Changes whenever [route] does, so the car redraws the line only then. */
    val routeId: String? = null,
    /** The route's shape, [lon, lat] pairs. */
    val route: List<DoubleArray> = emptyList(),
) {
    companion object {
        @Suppress("UNCHECKED_CAST")
        fun fromMap(m: Map<String, Any?>, previous: CarState): CarState {
            fun d(key: String) = (m[key] as? Number)?.toDouble()
            val maneuver = (m["maneuver"] as? Map<String, Any?>)?.let {
                CarManeuver(
                    type = (it["type"] as? Number)?.toInt() ?: 0,
                    instruction = it["instruction"] as? String ?: "",
                    street = it["street"] as? String,
                    distanceM = (it["distanceM"] as? Number)?.toDouble() ?: 0.0,
                )
            }
            val alert = (m["alert"] as? Map<String, Any?>)?.let {
                CarAlert(
                    label = it["label"] as? String ?: "",
                    distanceM = (it["distanceM"] as? Number)?.toDouble() ?: 0.0,
                    confirmations = (it["confirmations"] as? Number)?.toInt() ?: 0,
                )
            }
            val confirmation = (m["confirmation"] as? Map<String, Any?>)?.let {
                CarConfirmation(id = it["id"] as? String ?: "", label = it["label"] as? String ?: "")
            }
            val routeId = m["routeId"] as? String
            // The shape is only sent when the route changes.
            val route = (m["route"] as? List<*>)?.mapNotNull { p ->
                (p as? List<*>)?.let { doubleArrayOf((it[0] as Number).toDouble(), (it[1] as Number).toDouble()) }
            } ?: if (routeId == previous.routeId) previous.route else emptyList()
            return CarState(
                navigating = m["navigating"] as? Boolean ?: false,
                maneuver = maneuver,
                remainingM = d("remainingM") ?: 0.0,
                remainingS = d("remainingS") ?: 0.0,
                arrivalEpochMs = (m["arrivalEpochMs"] as? Number)?.toLong() ?: 0,
                lat = d("lat") ?: 0.0,
                lon = d("lon") ?: 0.0,
                bearing = d("bearing"),
                speedKph = (m["speedKph"] as? Number)?.toInt(),
                speedLimitKph = (m["speedLimitKph"] as? Number)?.toInt(),
                mapStyle = m["mapStyle"] as? String,
                alert = alert,
                confirmation = confirmation,
                routeId = routeId,
                route = route,
            )
        }
    }
}

/**
 * Link between the phone app (Flutter) and the car screens, over the
 * "org.roadto/car" channel:
 *
 * - Flutter -> car: `update` with the [CarState] as a map.
 * - car -> Flutter: `report` {type} (an AlertType code), `confirm`
 *   {id, stillThere: true/false/null}, `stop`.
 *
 * The car app runs in the same process as the phone app; it only works while
 * the Flutter side is running ([connected]).
 */
class CarBridge {
    @Volatile var state = CarState()
        private set
    val connected get() = channel != null

    private var channel: MethodChannel? = null
    private val listeners = mutableListOf<() -> Unit>()
    private val main = Handler(Looper.getMainLooper())

    fun attach(messenger: BinaryMessenger) {
        channel = MethodChannel(messenger, CHANNEL).also {
            it.setMethodCallHandler { call, result ->
                when (call.method) {
                    "update" -> {
                        @Suppress("UNCHECKED_CAST")
                        update(CarState.fromMap(call.arguments as? Map<String, Any?> ?: emptyMap(), state))
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
        notifyListeners()
    }

    fun detach() {
        channel?.setMethodCallHandler(null)
        channel = null
        state = CarState()
        notifyListeners()
    }

    fun update(s: CarState) {
        state = s
        notifyListeners()
    }

    fun addListener(l: () -> Unit) = synchronized(listeners) { listeners.add(l) }

    fun removeListener(l: () -> Unit) = synchronized(listeners) { listeners.remove(l) }

    fun report(type: String) = send("report", mapOf("type" to type))

    fun confirm(id: String, stillThere: Boolean?) = send("confirm", mapOf("id" to id, "stillThere" to stillThere))

    fun stop() = send("stop", null)

    /** Calls to Flutter; overridden in tests. */
    internal var sender: (String, Any?) -> Unit = { method, args -> main.post { channel?.invokeMethod(method, args) } }

    private fun send(method: String, args: Any?) = sender(method, args)

    private fun notifyListeners() {
        val copy = synchronized(listeners) { listeners.toList() }
        main.post { copy.forEach { it() } }
    }

    companion object {
        const val CHANNEL = "org.roadto/car"

        /** The one the app and the car service share. */
        val shared = CarBridge()
    }
}
