package org.roadto.roadto.car

import androidx.car.app.AppManager
import androidx.car.app.CarContext
import androidx.car.app.CarToast
import androidx.car.app.Screen
import androidx.car.app.model.Action
import androidx.car.app.model.ActionStrip
import androidx.car.app.model.Alert
import androidx.car.app.model.AlertCallback
import androidx.car.app.model.CarColor
import androidx.car.app.model.CarIcon
import androidx.car.app.model.CarText
import androidx.car.app.model.DateTimeWithZone
import androidx.car.app.model.Distance
import androidx.car.app.model.Template
import androidx.car.app.navigation.NavigationManager
import androidx.car.app.navigation.NavigationManagerCallback
import androidx.car.app.navigation.model.Maneuver
import androidx.car.app.navigation.model.MessageInfo
import androidx.car.app.navigation.model.NavigationTemplate
import androidx.car.app.navigation.model.RoutingInfo
import androidx.car.app.navigation.model.Step
import androidx.car.app.navigation.model.TravelEstimate
import androidx.car.app.versioning.CarAppApiLevels
import androidx.core.graphics.drawable.IconCompat
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import java.util.TimeZone

/**
 * The car's main screen: the map with the next maneuver, the time and
 * distance left, and its actions (Destinations before a trip, Signaler,
 * Arrêter during one). "Toujours là ?" shows
 * as a car alert with two answers. Everything comes from the phone app's
 * guidance through [CarBridge].
 */
class NavigationScreen(carContext: CarContext, private val bridge: CarBridge) : Screen(carContext) {
    private var navigationStarted = false
    private var alertShownFor: String? = null
    private val onState: () -> Unit = { onStateChanged() }

    private val navigationManager: NavigationManager? =
        try {
            carContext.getCarService(NavigationManager::class.java)
        } catch (e: RuntimeException) {
            null // not available in some test hosts
        }

    init {
        navigationManager?.setNavigationManagerCallback(
            object : NavigationManagerCallback {
                // The driver stopped navigation from the car (or another app took over).
                override fun onStopNavigation() {
                    navigationStarted = false
                    bridge.stop()
                }
            },
        )
        lifecycle.addObserver(
            object : DefaultLifecycleObserver {
                override fun onCreate(owner: LifecycleOwner) = bridge.addListener(onState).let {}

                override fun onDestroy(owner: LifecycleOwner) {
                    bridge.removeListener(onState)
                    if (navigationStarted) navigationManager?.navigationEnded()
                }
            },
        )
    }

    private fun onStateChanged() {
        val s = bridge.state
        if (s.navigating != navigationStarted) {
            navigationStarted = s.navigating
            if (s.navigating) navigationManager?.navigationStarted() else navigationManager?.navigationEnded()
        }
        val c = s.confirmation
        if (c != null && c.id != alertShownFor) {
            alertShownFor = c.id
            askStillThere(c)
        }
        invalidate()
    }

    override fun onGetTemplate(): Template {
        val s = bridge.state
        val builder = NavigationTemplate.Builder().setActionStrip(actions(s))
        val maneuver = s.maneuver
        when {
            // The car starts RoadTo when it is not running (RoadToEngine).
            !bridge.connected ->
                builder.setNavigationInfo(MessageInfo.Builder("RoadTo démarre…").setText("Un instant.").build())
            s.locationDenied ->
                builder.setNavigationInfo(
                    MessageInfo.Builder("Localisation désactivée")
                        .setText("Autorisez-la dans RoadTo sur le téléphone, à l’arrêt.")
                        .build(),
                )
            s.routing ->
                builder.setNavigationInfo(MessageInfo.Builder("Calcul de l’itinéraire…").build())
            !s.navigating || maneuver == null ->
                builder.setNavigationInfo(
                    MessageInfo.Builder("Où allez-vous ?").setText("Destinations : vos favoris ou une recherche.").build(),
                )
            else -> {
                builder.setNavigationInfo(
                    RoutingInfo.Builder().setCurrentStep(step(maneuver), distance(maneuver.distanceM)).build(),
                )
                builder.setDestinationTravelEstimate(
                    TravelEstimate.Builder(
                        distance(s.remainingM),
                        DateTimeWithZone.create(s.arrivalEpochMs, TimeZone.getDefault()),
                    ).setRemainingTimeSeconds(s.remainingS.toLong()).build(),
                )
            }
        }
        return builder.build()
    }

    private fun step(m: CarManeuver): Step {
        val icon = CarIcon.Builder(IconCompat.createWithResource(carContext, CarManeuvers.icon(m.type))).build()
        val step = Step.Builder(m.instruction).setManeuver(Maneuver.Builder(CarManeuvers.type(m.type)).setIcon(icon).build())
        m.street?.let { step.setRoad(it) }
        return step.build()
    }

    private fun actions(s: CarState): ActionStrip {
        val strip = ActionStrip.Builder()
        if (bridge.connected && !s.navigating) {
            strip.addAction(
                Action.Builder()
                    .setTitle("Destinations")
                    .setOnClickListener { screenManager.push(DestinationsScreen(carContext, bridge)) }
                    .build(),
            )
        }
        strip.addAction(
                Action.Builder()
                    .setTitle("Signaler")
                    .setOnClickListener { screenManager.push(ReportScreen(carContext, bridge)) }
                    .build(),
            )
        if (s.navigating) {
            strip.addAction(
                Action.Builder().setTitle("Arrêter").setOnClickListener { bridge.stop() }.build(),
            )
        }
        return strip.build()
    }

    /** "Accident toujours là ?" with Oui / Non; no answer counts as unknown. */
    private fun askStillThere(c: CarConfirmation) {
        val title = CarText.create("${c.label} toujours là ?")
        if (carContext.carAppApiLevel < CarAppApiLevels.LEVEL_5) {
            // Older hosts have no alerts: the phone asks instead.
            CarToast.makeText(carContext, title.toCharSequence(), CarToast.LENGTH_LONG).show()
            return
        }
        var answered = false
        fun answer(stillThere: Boolean?) {
            if (answered) return
            answered = true
            bridge.confirm(c.id, stillThere)
            carContext.getCarService(AppManager::class.java).dismissAlert(ALERT_ID)
        }
        val alert = Alert.Builder(ALERT_ID, title, 10_000)
            .addAction(Action.Builder().setTitle("Oui").setBackgroundColor(CarColor.GREEN).setOnClickListener { answer(true) }.build())
            .addAction(Action.Builder().setTitle("Non").setBackgroundColor(CarColor.RED).setOnClickListener { answer(false) }.build())
            .setCallback(
                object : AlertCallback {
                    override fun onCancel(reason: Int) = answer(null)

                    override fun onDismiss() = answer(null)
                },
            )
            .build()
        carContext.getCarService(AppManager::class.java).showAlert(alert)
    }

    companion object {
        private const val ALERT_ID = 1

        /** Metres under 1 km (rounded to 10 m), kilometres with one decimal under 10 km. */
        fun distance(metres: Double): Distance = when {
            metres < 1000 -> Distance.create((Math.round(metres / 10) * 10).toDouble(), Distance.UNIT_METERS)
            metres < 10_000 -> Distance.create(Math.round(metres / 100) / 10.0, Distance.UNIT_KILOMETERS_P1)
            else -> Distance.create(Math.round(metres / 1000).toDouble(), Distance.UNIT_KILOMETERS)
        }
    }
}
