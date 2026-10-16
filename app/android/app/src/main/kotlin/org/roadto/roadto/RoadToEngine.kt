package org.roadto.roadto

import android.content.Context
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import org.roadto.roadto.car.CarBridge

/**
 * The one Flutter engine of the process, shared by the phone screen
 * (MainActivity) and Android Auto (car/RoadToCarAppService): the guidance
 * runs once, whichever starts first, and goes on when the other closes.
 *
 * Started by the phone screen, the engine is FlutterActivity's own (so debug
 * tooling keeps working) and kept when the screen closes. Started by the car,
 * it runs without a screen until RoadTo is opened on the phone.
 */
object RoadToEngine {
    var engine: FlutterEngine? = null
        private set
    var location: DeviceLocation? = null
        private set

    /** The running engine, or a new one running the app, for the car. */
    fun obtain(context: Context): FlutterEngine {
        engine?.let { return it }
        val app = context.applicationContext
        val created = FlutterEngine(app)
        adopt(app, created)
        created.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint.createDefault())
        return created
    }

    /** Installs the app's channels on [created] and keeps it for the process. */
    fun adopt(context: Context, created: FlutterEngine) {
        if (engine === created) return
        val app = context.applicationContext
        val messenger = created.dartExecutor.binaryMessenger
        location = DeviceLocation(app, messenger)
        ValhallaChannel(app, messenger)
        NavigationService.Channel(app, messenger)
        CarBridge.shared.attach(messenger)
        engine = created
    }
}
