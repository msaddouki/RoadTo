package org.roadto.roadto.car

import android.content.Intent
import android.content.pm.ApplicationInfo
import androidx.car.app.AppManager
import androidx.car.app.CarAppService
import androidx.car.app.Screen
import androidx.car.app.Session
import androidx.car.app.validation.HostValidator
import org.roadto.roadto.RoadToEngine

/**
 * Entry point of the Android Auto app (navigation category). The Flutter
 * side computes the route and the guidance, the car shows them and sends
 * back what the driver taps; the car starts it when RoadTo is not running
 * (RoadToEngine), so the phone can stay in the pocket.
 */
class RoadToCarAppService : CarAppService() {
    override fun createHostValidator(): HostValidator =
        if (applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0) {
            // Debug builds: the desktop head unit (DHU) and test hosts too.
            HostValidator.ALLOW_ALL_HOSTS_VALIDATOR
        } else {
            HostValidator.Builder(applicationContext)
                .addAllowedHosts(androidx.car.app.R.array.hosts_allowlist_sample)
                .build()
        }

    override fun onCreateSession(): Session = NavigationSession()
}

class NavigationSession(private val bridge: CarBridge = CarBridge.shared) : Session() {
    override fun onCreateScreen(intent: Intent): Screen {
        RoadToEngine.obtain(carContext)
        carContext.getCarService(AppManager::class.java).setSurfaceCallback(CarMapRenderer(carContext, bridge))
        return NavigationScreen(carContext, bridge)
    }
}
