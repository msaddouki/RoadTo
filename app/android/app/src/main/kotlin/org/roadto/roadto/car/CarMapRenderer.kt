package org.roadto.roadto.car

import android.app.Presentation
import android.graphics.Rect
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.util.Log
import androidx.car.app.CarContext
import androidx.car.app.SurfaceCallback
import androidx.car.app.SurfaceContainer
import org.maplibre.android.MapLibre
import org.maplibre.android.camera.CameraPosition
import org.maplibre.android.camera.CameraUpdateFactory
import org.maplibre.android.geometry.LatLng
import org.maplibre.android.maps.MapLibreMap
import org.maplibre.android.maps.MapView
import org.maplibre.android.maps.Style
import org.maplibre.android.style.layers.CircleLayer
import org.maplibre.android.style.layers.LineLayer
import org.maplibre.android.style.layers.Property
import org.maplibre.android.style.layers.PropertyFactory
import org.maplibre.android.style.sources.GeoJsonSource

/**
 * Draws the map on the car screen (spike D of the plan). The car library
 * hands over a bare surface; a virtual display shows a MapLibre MapView on
 * it, with the phone's style (offline region style included), the route and
 * the car's position. The camera follows the car, kept inside the area the
 * templates leave visible.
 */
class CarMapRenderer(private val carContext: CarContext, private val bridge: CarBridge) : SurfaceCallback {
    private var display: VirtualDisplay? = null
    private var presentation: Presentation? = null
    private var mapView: MapView? = null
    private var map: MapLibreMap? = null
    private var style: Style? = null
    private var navLabels: Boolean? = null
    private var styleUri: String? = null
    private var routeId: String? = null
    private var width = 0
    private var height = 0
    private var visible = Rect()

    private val onState: () -> Unit = { render() }

    override fun onSurfaceAvailable(container: SurfaceContainer) {
        val surface = container.surface ?: return
        width = container.width
        height = container.height
        val manager = carContext.getSystemService(DisplayManager::class.java)
        val virtual = manager.createVirtualDisplay(
            "RoadToCarMap",
            container.width,
            container.height,
            container.dpi,
            surface,
            DisplayManager.VIRTUAL_DISPLAY_FLAG_OWN_CONTENT_ONLY,
        )
        display = virtual
        MapLibre.getInstance(carContext.applicationContext)
        val view = MapView(carContext)
        presentation = Presentation(carContext, virtual.display).apply {
            setContentView(view)
            show()
        }
        mapView = view
        view.onCreate(null)
        view.onStart()
        view.onResume()
        view.getMapAsync { m ->
            map = m
            m.uiSettings.apply {
                isCompassEnabled = false
                isLogoEnabled = false
                isAttributionEnabled = false
            }
            render()
        }
        bridge.addListener(onState)
    }

    override fun onVisibleAreaChanged(visibleArea: Rect) {
        visible = Rect(visibleArea)
        render()
    }

    override fun onStableAreaChanged(stableArea: Rect) {}

    override fun onSurfaceDestroyed(container: SurfaceContainer) {
        bridge.removeListener(onState)
        mapView?.run {
            onPause()
            onStop()
            onDestroy()
        }
        presentation?.dismiss()
        display?.release()
        mapView = null
        map = null
        style = null
        styleUri = null
        routeId = null
        presentation = null
        display = null
    }

    private fun render() {
        val m = map ?: return
        val s = bridge.state
        val uri = styleUriOf(s.mapStyle) ?: return
        if (uri != styleUri) {
            styleUri = uri
            style = null
            routeId = null
            navLabels = null
            m.setStyle(Style.Builder().fromUri(uri)) { loaded ->
                if (styleUri != uri) return@setStyle
                addLayers(loaded)
                style = loaded
                render()
            }
            return
        }
        val st = style ?: return
        if (s.navigating != navLabels) {
            navLabels = s.navigating
            showNavigationLabels(st, s.navigating)
        }
        if (s.routeId != routeId) {
            routeId = s.routeId
            (st.getSource(ROUTE) as? GeoJsonSource)?.setGeoJson(lineGeoJson(s.route))
        }
        if (s.lat != 0.0 || s.lon != 0.0) {
            (st.getSource(POSITION) as? GeoJsonSource)?.setGeoJson(pointGeoJson(s.lat, s.lon))
            m.moveCamera(CameraUpdateFactory.newCameraPosition(camera(s)))
        }
    }

    private fun camera(s: CarState): CameraPosition {
        // The position sits low in the visible area, so more of the road
        // ahead shows (as on the phone while navigating).
        val area = if (visible.isEmpty) Rect(0, 0, width, height) else visible
        val top = area.top + area.height() * 0.35
        return CameraPosition.Builder()
            .target(LatLng(s.lat, s.lon))
            .zoom(if (s.navigating) 16.5 else 14.0)
            .bearing(if (s.navigating) s.bearing ?: 0.0 else 0.0)
            .tilt(if (s.navigating) 45.0 else 0.0)
            .padding(area.left.toDouble(), top, (width - area.right).toDouble(), (height - area.bottom).toDouble())
            .build()
    }

    private fun addLayers(style: Style) {
        try {
            style.addSource(GeoJsonSource(ROUTE, lineGeoJson(emptyList())))
            style.addSource(GeoJsonSource(POSITION, pointGeoJson(null, null)))
            // Under the street names of RoadTo's style (its "roadto-labels"
            // marker): the route never covers a name.
            fun addRouteLayer(layer: LineLayer) =
                if (style.getLayer(LABELS_MARKER) != null) style.addLayerBelow(layer, LABELS_MARKER) else style.addLayer(layer)
            addRouteLayer(
                LineLayer("$ROUTE-casing", ROUTE).withProperties(
                    PropertyFactory.lineColor("#0B3D91"),
                    PropertyFactory.lineWidth(12f),
                    PropertyFactory.lineCap(Property.LINE_CAP_ROUND),
                    PropertyFactory.lineJoin(Property.LINE_JOIN_ROUND),
                ),
            )
            addRouteLayer(
                LineLayer(ROUTE, ROUTE).withProperties(
                    PropertyFactory.lineColor("#3D8BFF"),
                    PropertyFactory.lineWidth(8f),
                    PropertyFactory.lineCap(Property.LINE_CAP_ROUND),
                    PropertyFactory.lineJoin(Property.LINE_JOIN_ROUND),
                ),
            )
            style.addLayer(
                CircleLayer(POSITION, POSITION).withProperties(
                    PropertyFactory.circleRadius(9f),
                    PropertyFactory.circleColor("#3D8BFF"),
                    PropertyFactory.circleStrokeWidth(3f),
                    PropertyFactory.circleStrokeColor("#FFFFFF"),
                ),
            )
        } catch (e: RuntimeException) {
            Log.w(TAG, "Could not add the car map layers", e)
        }
    }

    /**
     * During a trip, street names in bubbles (the style's "-nav" layers)
     * rather than along the roads, as on the phone. Styles without them are
     * left as they are.
     */
    private fun showNavigationLabels(style: Style, navigating: Boolean) {
        for (layer in style.layers) {
            val id = layer.id
            val visible = when {
                id.endsWith(NAV_SUFFIX) -> navigating
                style.getLayer(id + NAV_SUFFIX) != null -> !navigating
                else -> continue
            }
            layer.setProperties(PropertyFactory.visibility(if (visible) Property.VISIBLE else Property.NONE))
        }
    }

    companion object {
        private const val TAG = "RoadToCarMap"
        private const val LABELS_MARKER = "roadto-labels"
        private const val NAV_SUFFIX = "-nav"
        private const val ROUTE = "roadto-route"
        private const val POSITION = "roadto-position"

        /** The phone gives a URL, or a local file path for the offline style. */
        fun styleUriOf(mapStyle: String?): String? = when {
            mapStyle.isNullOrBlank() -> null
            mapStyle.startsWith("/") -> "file://$mapStyle"
            else -> mapStyle
        }

        fun lineGeoJson(route: List<DoubleArray>): String =
            if (route.size < 2) {
                """{"type":"FeatureCollection","features":[]}"""
            } else {
                route.joinToString(",", """{"type":"Feature","properties":{},"geometry":{"type":"LineString","coordinates":[""", "]}}") {
                    "[${it[0]},${it[1]}]"
                }
            }

        fun pointGeoJson(lat: Double?, lon: Double?): String =
            if (lat == null || lon == null) {
                """{"type":"FeatureCollection","features":[]}"""
            } else {
                """{"type":"Feature","properties":{},"geometry":{"type":"Point","coordinates":[$lon,$lat]}}"""
            }
    }
}
