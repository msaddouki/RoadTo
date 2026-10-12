package org.roadto.roadto

import android.os.Handler
import android.os.Looper
import com.squareup.moshi.Moshi
import com.squareup.moshi.kotlin.reflect.KotlinJsonAdapterFactory
import com.valhalla.api.models.RouteRequest
import com.valhalla.api.models.RouteResponse
import com.valhalla.config.ValhallaConfigBuilder
import com.valhalla.valhalla.Valhalla
import com.valhalla.valhalla.ValhallaResponse
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors
import org.json.JSONObject

class MainActivity : FlutterActivity() {
    // Valhalla (valhalla-mobile) on the installed region's graph. Routing is
    // CPU-bound and blocking, so it runs on its own thread; the engine is
    // kept between requests and rebuilt when the region (config) changes.
    private val routingThread = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val moshi = Moshi.Builder().add(KotlinJsonAdapterFactory()).build()
    private var valhalla: Valhalla? = null
    private var valhallaConfig: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "org.roadto/valhalla").setMethodCallHandler { call, result ->
            when (call.method) {
                "route" -> {
                    val config = call.argument<String>("config")
                    val request = call.argument<String>("request")
                    if (config == null || request == null) {
                        result.error("bad_args", "config and request are required", null)
                        return@setMethodCallHandler
                    }
                    routingThread.execute {
                        try {
                            val response = route(config, request)
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
        if (valhalla == null || valhallaConfig != configPath) {
            valhalla?.close()
            // The region's config (routing.offline.json) names the graph; the
            // library's defaults cover the rest.
            val extract = JSONObject(File(configPath).readText()).getJSONObject("mjolnir").getString("tile_extract")
            valhalla = Valhalla(this, ValhallaConfigBuilder().withTileExtract(extract).build())
            valhallaConfig = configPath
        }
        val request = moshi.adapter(RouteRequest::class.java).fromJson(toModelJson(requestJson))
            ?: throw IllegalArgumentException("empty route request")
        return when (val response = valhalla!!.route(request)) {
            is ValhallaResponse.Json -> moshi.adapter(RouteResponse::class.java).toJson(response.jsonResponse)
            else -> throw IllegalStateException("unexpected response format")
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

    override fun onDestroy() {
        routingThread.execute { valhalla?.close(); valhalla = null }
        routingThread.shutdown()
        super.onDestroy()
    }
}
