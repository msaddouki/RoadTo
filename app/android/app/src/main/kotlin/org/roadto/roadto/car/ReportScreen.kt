package org.roadto.roadto.car

import androidx.car.app.CarContext
import androidx.car.app.CarToast
import androidx.car.app.Screen
import androidx.car.app.model.Action
import androidx.car.app.model.CarIcon
import androidx.car.app.model.GridItem
import androidx.car.app.model.GridTemplate
import androidx.car.app.model.ItemList
import androidx.car.app.model.Template
import androidx.core.graphics.drawable.IconCompat
import org.roadto.roadto.R

/**
 * One tap to report what is on the road, as on the phone (report sheet).
 * Police stays out until the L130-11 channel exists (plan, J6).
 */
class ReportScreen(carContext: CarContext, private val bridge: CarBridge) : Screen(carContext) {
    override fun onGetTemplate(): Template {
        val items = ItemList.Builder()
        for (t in TYPES) {
            items.addItem(
                GridItem.Builder()
                    .setTitle(t.label)
                    .setImage(CarIcon.Builder(IconCompat.createWithResource(carContext, t.icon)).build())
                    .setOnClickListener {
                        bridge.report(t.code)
                        CarToast.makeText(carContext, "${t.label} signalé", CarToast.LENGTH_SHORT).show()
                        screenManager.pop()
                    }
                    .build(),
            )
        }
        @Suppress("DEPRECATION") // setTitle/setHeaderAction: Header needs car API level 7
        return GridTemplate.Builder()
            .setTitle("Signaler")
            .setHeaderAction(Action.BACK)
            .setSingleList(items.build())
            .build()
    }

    data class ReportType(val code: String, val label: String, val icon: Int)

    companion object {
        /** AlertType codes of the Dart core (packages/roadto_core/lib/src/alerts.dart). */
        val TYPES = listOf(
            ReportType("accident", "Accident", R.drawable.car_report_accident),
            ReportType("traffic", "Bouchon", R.drawable.car_report_traffic),
            ReportType("hazard", "Danger", R.drawable.car_report_hazard),
            ReportType("closure", "Route fermée", R.drawable.car_report_closure),
            ReportType("roadworks", "Travaux", R.drawable.car_report_roadworks),
        )
    }
}
