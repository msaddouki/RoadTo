package org.roadto.roadto.car

import androidx.car.app.CarContext
import androidx.car.app.CarToast
import androidx.car.app.Screen
import androidx.car.app.constraints.ConstraintManager
import androidx.car.app.model.Action
import androidx.car.app.model.ActionStrip
import androidx.car.app.model.ItemList
import androidx.car.app.model.ListTemplate
import androidx.car.app.model.Row
import androidx.car.app.model.Template

/** Where to go from the car: the places saved on the phone, or a search. */
class DestinationsScreen(carContext: CarContext, private val bridge: CarBridge) : Screen(carContext) {
    override fun onGetTemplate(): Template {
        val items = placeList(carContext, bridge.state.places, bridge, screenManager)
            .setNoItemsMessage("Aucun favori : enregistrez Maison ou Travail sur le téléphone, ou cherchez une adresse.")
            .build()
        @Suppress("DEPRECATION") // setTitle/setHeaderAction: Header needs car API level 7
        return ListTemplate.Builder()
            .setTitle("Destinations")
            .setHeaderAction(Action.BACK)
            .setActionStrip(
                ActionStrip.Builder()
                    .addAction(
                        Action.Builder()
                            .setTitle("Rechercher")
                            .setOnClickListener { screenManager.push(SearchScreen(carContext, bridge)) }
                            .build(),
                    )
                    .build(),
            )
            .setSingleList(items)
            .build()
    }

    companion object {
        /** As many rows as the car allows (6 on most); tapping one starts the trip. */
        fun placeList(
            carContext: CarContext,
            places: List<CarPlace>,
            bridge: CarBridge,
            screens: androidx.car.app.ScreenManager,
        ): ItemList.Builder {
            val limit = try {
                carContext.getCarService(ConstraintManager::class.java)
                    .getContentLimit(ConstraintManager.CONTENT_LIMIT_TYPE_LIST)
            } catch (e: RuntimeException) {
                6 // hosts before car API level 2
            }
            val items = ItemList.Builder()
            for (p in places.take(limit)) {
                val row = Row.Builder().setTitle(p.name.ifBlank { "Lieu" })
                p.detail?.takeIf { it.isNotBlank() }?.let { row.addText(it) }
                row.setOnClickListener {
                    bridge.navigate(p)
                    CarToast.makeText(carContext, "Itinéraire vers ${p.name}…", CarToast.LENGTH_SHORT).show()
                    screens.popToRoot()
                }
                items.addItem(row.build())
            }
            return items
        }
    }
}
