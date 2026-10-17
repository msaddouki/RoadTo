package org.roadto.roadto.car

import androidx.car.app.CarContext
import androidx.car.app.Screen
import androidx.car.app.model.Action
import androidx.car.app.model.SearchTemplate
import androidx.car.app.model.Template

/**
 * Search from the car, with the car's keyboard (only when parked, the host
 * decides). The phone searches, offline index first, as in the app.
 */
class SearchScreen(carContext: CarContext, private val bridge: CarBridge) : Screen(carContext) {
    /** Null until a search is made. */
    private var results: List<CarPlace>? = null
    private var loading = false
    private var generation = 0

    override fun onGetTemplate(): Template {
        val builder = SearchTemplate.Builder(
            object : SearchTemplate.SearchCallback {
                override fun onSearchSubmitted(searchText: String) = search(searchText)
            },
        )
            .setHeaderAction(Action.BACK)
            .setSearchHint("Adresse, lieu, commune")
            .setShowKeyboardByDefault(results == null)
        val found = results
        when {
            loading -> builder.setLoading(true)
            found != null ->
                builder.setItemList(
                    DestinationsScreen.placeList(carContext, found, bridge, screenManager)
                        .setNoItemsMessage("Aucun résultat")
                        .build(),
                )
        }
        return builder.build()
    }

    fun search(query: String) {
        if (query.isBlank()) return
        val current = ++generation
        loading = true
        invalidate()
        bridge.search(query.trim()) { places ->
            if (current != generation) return@search // a newer search is running
            results = places
            loading = false
            invalidate()
        }
    }
}
