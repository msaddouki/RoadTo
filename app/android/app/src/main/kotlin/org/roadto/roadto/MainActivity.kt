package org.roadto.roadto

import android.os.Handler
import android.os.Looper
import com.valhalla.valhalla.Valhalla
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    // Valhalla (valhalla-mobile) on the installed region's graph. Routing is
    // CPU-bound and blocking, so it runs on its own thread; the engine is
    // kept between requests and rebuilt when the region (config) changes.
    private val routingThread = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
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
                            if (valhalla == null || valhallaConfig != config) {
                                valhalla?.close()
                                valhalla = Valhalla(config)
                                valhallaConfig = config
                            }
                            val response = valhalla!!.routeRaw(request)
                            main.post { result.success(response) }
                        } catch (e: Exception) {
                            main.post { result.error("valhalla", e.message ?: e.toString(), null) }
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        routingThread.execute { valhalla?.close(); valhalla = null }
        routingThread.shutdown()
        super.onDestroy()
    }
}
