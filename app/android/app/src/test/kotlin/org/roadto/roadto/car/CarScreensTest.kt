package org.roadto.roadto.car

import android.os.Looper
import androidx.car.app.OnDoneCallback
import androidx.car.app.serialization.Bundleable
import androidx.car.app.model.Action
import androidx.car.app.model.Distance
import androidx.car.app.model.GridItem
import androidx.car.app.model.GridTemplate
import androidx.car.app.navigation.model.Maneuver
import androidx.car.app.navigation.model.MessageInfo
import androidx.car.app.navigation.model.NavigationTemplate
import androidx.car.app.navigation.model.RoutingInfo
import androidx.car.app.testing.TestCarContext
import androidx.car.app.testing.ScreenController
import androidx.car.app.testing.TestScreenManager
import androidx.lifecycle.Lifecycle
import androidx.test.core.app.ApplicationProvider
import io.flutter.plugin.common.BinaryMessenger
import java.nio.ByteBuffer
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf

@RunWith(RobolectricTestRunner::class)
class CarScreensTest {
    private lateinit var context: TestCarContext
    private lateinit var bridge: CarBridge
    private val sent = mutableListOf<Pair<String, Any?>>()

    /** Stands in for the Flutter engine's messenger: the bridge only needs one to attach. */
    private val messenger = object : BinaryMessenger {
        override fun send(channel: String, message: ByteBuffer?) {}

        override fun send(channel: String, message: ByteBuffer?, callback: BinaryMessenger.BinaryReply?) {}

        override fun setMessageHandler(channel: String, handler: BinaryMessenger.BinaryMessageHandler?) {}
    }

    private val driving = CarState(
        navigating = true,
        maneuver = CarManeuver(10, "Tournez à droite dans Rue Garibaldi.", "Rue Garibaldi", 247.0),
        remainingM = 5430.0,
        remainingS = 780.0,
        arrivalEpochMs = 1_792_150_000_000,
        lat = 45.76,
        lon = 4.85,
        bearing = 90.0,
        mapStyle = "/data/user/0/org.roadto.roadto/files/regions/lyon/style/style.offline.json",
    )

    @Before
    fun setUp() {
        context = TestCarContext.createCarContext(ApplicationProvider.getApplicationContext())
        bridge = CarBridge()
        bridge.sender = { method, args -> sent.add(method to args) }
    }

    private fun click(action: Action) {
        action.onClickDelegate!!.sendClick(
            object : OnDoneCallback {
                override fun onSuccess(response: Bundleable?) {}

                override fun onFailure(response: Bundleable) {}
            },
        )
        shadowOf(Looper.getMainLooper()).idle()
    }

    private fun click(item: GridItem) {
        item.onClickDelegate!!.sendClick(
            object : OnDoneCallback {
                override fun onSuccess(response: Bundleable?) {}

                override fun onFailure(response: Bundleable) {}
            },
        )
        shadowOf(Looper.getMainLooper()).idle()
    }

    @Test
    fun withoutThePhoneApp_asksToOpenIt() {
        val t = NavigationScreen(context, bridge).onGetTemplate() as NavigationTemplate
        assertEquals("Ouvrez RoadTo sur le téléphone", (t.navigationInfo as MessageInfo).title.toString())
    }

    @Test
    fun connectedWithoutTrip_asksForADestination() {
        bridge.attach(messenger)
        val t = NavigationScreen(context, bridge).onGetTemplate() as NavigationTemplate
        assertEquals("Choisissez une destination", (t.navigationInfo as MessageInfo).title.toString())
        assertEquals(listOf("Signaler"), t.actionStrip!!.actions.map { it.title.toString() })
    }

    @Test
    fun navigating_showsTheNextManeuverAndWhatIsLeft() {
        bridge.attach(messenger)
        bridge.update(driving)
        val t = NavigationScreen(context, bridge).onGetTemplate() as NavigationTemplate
        val routing = t.navigationInfo as RoutingInfo
        val step = routing.currentStep!!
        assertEquals("Tournez à droite dans Rue Garibaldi.", step.cue.toString())
        assertEquals("Rue Garibaldi", step.road.toString())
        assertEquals(Maneuver.TYPE_TURN_NORMAL_RIGHT, step.maneuver!!.type)
        assertEquals(250.0, routing.currentDistance!!.displayDistance, 0.0)
        assertEquals(Distance.UNIT_METERS, routing.currentDistance!!.displayUnit)
        val estimate = t.destinationTravelEstimate!!
        assertEquals(5.4, estimate.remainingDistance!!.displayDistance, 0.0)
        assertEquals(780L, estimate.remainingTimeSeconds)
        assertEquals(1_792_150_000_000, estimate.arrivalTimeAtDestination!!.timeSinceEpochMillis)
    }

    @Test
    fun stopFromTheCar_stopsTheTripOnThePhone() {
        bridge.attach(messenger)
        bridge.update(driving)
        val t = NavigationScreen(context, bridge).onGetTemplate() as NavigationTemplate
        val stop = t.actionStrip!!.actions.single { it.title.toString() == "Arrêter" }
        click(stop)
        assertEquals(listOf("stop" to null), sent)
    }

    @Test
    fun reportGrid_hasFiveTypesWithoutPolice_andSendsTheTappedOne() {
        // Opened from the navigation screen, as in the app.
        val screens = context.getCarService(TestScreenManager::class.java)
        ScreenController(NavigationScreen(context, bridge)).moveToState(Lifecycle.State.RESUMED)
        val report = ReportScreen(context, bridge)
        ScreenController(report).moveToState(Lifecycle.State.RESUMED)
        val t = report.onGetTemplate() as GridTemplate
        val items = t.singleList!!.items.map { it as GridItem }
        assertEquals(listOf("Accident", "Bouchon", "Danger", "Route fermée", "Travaux"), items.map { it.title.toString() })
        assertFalse(items.any { it.title.toString() == "Police" })
        click(items[3])
        assertEquals(listOf("report" to mapOf("type" to "closure")), sent)
        // Back to the map.
        assertTrue(screens.top is NavigationScreen)
    }

    @Test
    fun distances_areRoundedLikeOnThePhone() {
        NavigationScreen.distance(47.0).let { assertEquals(50.0, it.displayDistance, 0.0); assertEquals(Distance.UNIT_METERS, it.displayUnit) }
        NavigationScreen.distance(1260.0).let { assertEquals(1.3, it.displayDistance, 0.0); assertEquals(Distance.UNIT_KILOMETERS_P1, it.displayUnit) }
        NavigationScreen.distance(23400.0).let { assertEquals(23.0, it.displayDistance, 0.0); assertEquals(Distance.UNIT_KILOMETERS, it.displayUnit) }
    }
}

class CarStateTest {
    @Test
    fun readsTheFlutterMap_andKeepsTheRouteWhileItsIdIsTheSame() {
        val first = CarState.fromMap(
            mapOf(
                "navigating" to true,
                "maneuver" to mapOf("type" to 26, "instruction" to "Prenez le rond-point.", "street" to null, "distanceM" to 120),
                "remainingM" to 3000.5,
                "remainingS" to 300,
                "arrivalEpochMs" to 1_792_150_000_000,
                "lat" to 45.76,
                "lon" to 4.85,
                "bearing" to null,
                "alert" to mapOf("label" to "Accident", "distanceM" to 800, "confirmations" to 3),
                "routeId" to "r1",
                "route" to listOf(listOf(4.85, 45.76), listOf(4.86, 45.77)),
            ),
            CarState(),
        )
        assertTrue(first.navigating)
        assertEquals(26, first.maneuver!!.type)
        assertNull(first.maneuver!!.street)
        assertNull(first.bearing)
        assertEquals(CarAlert("Accident", 800.0, 3), first.alert)
        assertEquals(2, first.route.size)

        val next = CarState.fromMap(mapOf("navigating" to true, "routeId" to "r1"), first)
        assertEquals(2, next.route.size)
        val other = CarState.fromMap(mapOf("navigating" to true, "routeId" to "r2"), first)
        assertTrue(other.route.isEmpty())
    }

    @Test
    fun maneuvers_mapValhallaTypes() {
        assertEquals(Maneuver.TYPE_ROUNDABOUT_ENTER_CCW, CarManeuvers.type(26))
        assertEquals(Maneuver.TYPE_TURN_NORMAL_LEFT, CarManeuvers.type(15))
        assertEquals(Maneuver.TYPE_DESTINATION_LEFT, CarManeuvers.type(6))
        assertEquals(Maneuver.TYPE_OFF_RAMP_SLIGHT_RIGHT, CarManeuvers.type(20))
        assertEquals(Maneuver.TYPE_STRAIGHT, CarManeuvers.type(99))
    }

    @Test
    fun mapStyle_pathsBecomeFileUris() {
        assertEquals("file:///data/x/style.json", CarMapRenderer.styleUriOf("/data/x/style.json"))
        assertEquals("https://tiles.openfreemap.org/styles/liberty", CarMapRenderer.styleUriOf("https://tiles.openfreemap.org/styles/liberty"))
        assertNull(CarMapRenderer.styleUriOf(""))
        assertEquals("""{"type":"FeatureCollection","features":[]}""", CarMapRenderer.lineGeoJson(listOf(doubleArrayOf(4.8, 45.7))))
    }
}
