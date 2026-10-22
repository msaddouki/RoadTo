package org.roadto.roadto

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.squareup.moshi.Moshi
import com.squareup.moshi.kotlin.reflect.KotlinJsonAdapterFactory
import com.valhalla.api.models.RouteRequest
import com.valhalla.api.models.RouteResponse
import com.valhalla.config.ValhallaConfigBuilder
import com.valhalla.valhalla.Valhalla
import com.valhalla.valhalla.ValhallaResponse
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors
import org.json.JSONObject

/**
 * "org.roadto/valhalla": Valhalla (valhalla-mobile) on the installed region's
 * graph. Routing is CPU-bound and blocking, so it runs on its own thread; the
 * engine is kept between requests and rebuilt when the region (config)
 * changes. Lives as long as the Flutter engine (RoadToEngine).
 */
class ValhallaChannel(private val context: Context, messenger: BinaryMessenger) {
    private val routingThread = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val moshi = Moshi.Builder().add(KotlinJsonAdapterFactory()).build()
    private var valhalla: Valhalla? = null
    private var valhallaConfig: String? = null
    private val channel = MethodChannel(messenger, "org.roadto/valhalla")

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "route", "traceAttributes", "traceRoute" -> {
                    val config = call.argument<String>("config")
                    val request = call.argument<String>("request")
                    if (config == null || request == null) {
                        result.error("bad_args", "config and request are required", null)
                        return@setMethodCallHandler
                    }
                    routingThread.execute {
                        try {
                            val response = when (call.method) {
                                "route" -> route(config, request)
                                // Raw JSON is public for these: no model mapping. trace_route
                                // answers in OSRM form, the one with the lanes.
                                "traceRoute" -> engine(config).traceRouteRaw(request)
                                else -> engine(config).traceAttributesRaw(request)
                            }
                            main.post { result.success(response) }
                        } catch (e: Throwable) {
                            // Throwable, not Exception: a native library that fails to load
                            // (UnsatisfiedLinkError) must still answer, or Dart waits forever.
                            valhalla?.close()
                            valhalla = null
                            valhallaConfig = null
                            main.post { result.error("valhalla", e.message ?: e.toString(), null) }
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    /**
     * Runs a Valhalla /route request (JSON, as sent to a Valhalla server) and
     * returns Valhalla's JSON answer. valhalla-mobile only takes typed
     * requests, so the JSON goes through its models both ways.
     */
    private fun route(configPath: String, requestJson: String): String {
        // Alternatives (to weigh reported jams) are not in the typed answer:
        // those requests go to the engine as they are, in the server's own
        // format, and fall back to one typed route if that fails.
        if (JSONObject(requestJson).optInt("alternates", 0) > 0) {
            try {
                val raw = engine(configPath).routeRaw(requestJson)
                if (JSONObject(raw).has("trip")) return raw
            } catch (e: Exception) {
                Log.w("RoadTo", "Raw route with alternatives failed, one route instead", e)
            }
        }
        val request = moshi.adapter(RouteRequest::class.java).fromJson(toModelJson(requestJson))
            ?: throw IllegalArgumentException("empty route request")
        return when (val response = engine(configPath).route(request)) {
            is ValhallaResponse.Json -> moshi.adapter(RouteResponse::class.java).toJson(response.jsonResponse)
            else -> throw IllegalStateException("unexpected response format")
        }
    }

    /** The engine for this region, built on first use and kept. */
    private fun engine(configPath: String): Valhalla {
        val current = valhalla
        if (current != null && valhallaConfig == configPath) return current
        current?.close()
        // The region's config (routing.offline.json) names the graph; the
        // library's defaults cover the rest.
        val extract = JSONObject(File(configPath).readText()).getJSONObject("mjolnir").getString("tile_extract")
        return Valhalla(context, ValhallaConfigBuilder().withTileExtract(extract).build()).also {
            valhalla = it
            valhallaConfig = configPath
        }
    }

    /**
     * Adapts a server request to the library's models, which still use the
     * older names: "km"/"mi" units and "avoid_polygons" (Valhalla reads both).
     * Unknown keys, such as "directions_options", are ignored by the models.
     */
    private fun toModelJson(requestJson: String): String {
        val json = JSONObject(requestJson)
        when (json.optString("units")) {
            "kilometers" -> json.put("units", "km")
            "miles" -> json.put("units", "mi")
        }
        if (json.has("exclude_polygons")) {
            json.put("avoid_polygons", json.get("exclude_polygons"))
            json.remove("exclude_polygons")
        }
        return json.toString()
    }
}
