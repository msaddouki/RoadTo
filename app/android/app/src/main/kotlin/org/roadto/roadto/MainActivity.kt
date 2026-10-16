package org.roadto.roadto

import android.content.Context
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

/**
 * The phone screen. The Flutter engine and the app's channels belong to the
 * process (RoadToEngine): a trip started here goes on in the car when the
 * screen closes, and one started from the car shows here when RoadTo opens.
 */
class MainActivity : FlutterActivity() {
    override fun provideFlutterEngine(context: Context): FlutterEngine? = RoadToEngine.engine

    override fun shouldDestroyEngineWithHost(): Boolean = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        RoadToEngine.adopt(this, flutterEngine)
        RoadToEngine.location?.activity = this
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        RoadToEngine.location?.onPermissionResult(requestCode)
    }

    override fun onDestroy() {
        RoadToEngine.location?.let { if (it.activity === this) it.activity = null }
        super.onDestroy()
    }
}
