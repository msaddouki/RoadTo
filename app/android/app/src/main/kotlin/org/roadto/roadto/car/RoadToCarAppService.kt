package org.roadto.roadto.car

import android.content.Intent
import android.content.pm.ApplicationInfo
import androidx.car.app.AppManager
import androidx.car.app.CarAppService
import androidx.car.app.Screen
import androidx.car.app.Session
import androidx.car.app.validation.HostValidator

/**
 * Entry point of the Android Auto app (navigation category). The phone app
 * must be running: it computes the route and the guidance, the car shows
 * them and sends back reports.
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
        carContext.getCarService(AppManager::class.java).setSurfaceCallback(CarMapRenderer(carContext, bridge))
        return NavigationScreen(carContext, bridge)
    }
}
