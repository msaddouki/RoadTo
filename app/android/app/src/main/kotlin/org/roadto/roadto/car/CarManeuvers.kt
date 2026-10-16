package org.roadto.roadto.car

import androidx.car.app.navigation.model.Maneuver
import org.roadto.roadto.R

/**
 * Valhalla maneuver types (the routing engine's, see TripRoute.maneuvers on
 * the Dart side) mapped to the car library's, with the icon shown next to
 * the instruction. France drives on the right: roundabouts turn
 * counterclockwise.
 */
object CarManeuvers {
    fun type(valhalla: Int): Int = when (valhalla) {
        1, 2, 3 -> Maneuver.TYPE_DEPART
        4 -> Maneuver.TYPE_DESTINATION
        5 -> Maneuver.TYPE_DESTINATION_RIGHT
        6 -> Maneuver.TYPE_DESTINATION_LEFT
        7 -> Maneuver.TYPE_NAME_CHANGE
        8, 22 -> Maneuver.TYPE_STRAIGHT
        9 -> Maneuver.TYPE_TURN_SLIGHT_RIGHT
        10 -> Maneuver.TYPE_TURN_NORMAL_RIGHT
        11 -> Maneuver.TYPE_TURN_SHARP_RIGHT
        12 -> Maneuver.TYPE_U_TURN_RIGHT
        13 -> Maneuver.TYPE_U_TURN_LEFT
        14 -> Maneuver.TYPE_TURN_SHARP_LEFT
        15 -> Maneuver.TYPE_TURN_NORMAL_LEFT
        16 -> Maneuver.TYPE_TURN_SLIGHT_LEFT
        17 -> Maneuver.TYPE_ON_RAMP_NORMAL_RIGHT
        18 -> Maneuver.TYPE_ON_RAMP_SLIGHT_RIGHT
        19 -> Maneuver.TYPE_ON_RAMP_SLIGHT_LEFT
        20 -> Maneuver.TYPE_OFF_RAMP_SLIGHT_RIGHT
        21 -> Maneuver.TYPE_OFF_RAMP_SLIGHT_LEFT
        23 -> Maneuver.TYPE_KEEP_RIGHT
        24 -> Maneuver.TYPE_KEEP_LEFT
        25 -> Maneuver.TYPE_MERGE_SIDE_UNSPECIFIED
        26 -> Maneuver.TYPE_ROUNDABOUT_ENTER_CCW
        27 -> Maneuver.TYPE_ROUNDABOUT_EXIT_CCW
        28 -> Maneuver.TYPE_FERRY_BOAT
        37 -> Maneuver.TYPE_MERGE_RIGHT
        38 -> Maneuver.TYPE_MERGE_LEFT
        else -> Maneuver.TYPE_STRAIGHT
    }

    /** One drawing per family of maneuvers: straight, left, right, roundabout, arrival. */
    fun icon(valhalla: Int): Int = when (type(valhalla)) {
        Maneuver.TYPE_DESTINATION, Maneuver.TYPE_DESTINATION_LEFT, Maneuver.TYPE_DESTINATION_RIGHT ->
            R.drawable.car_maneuver_arrive
        Maneuver.TYPE_ROUNDABOUT_ENTER_CCW, Maneuver.TYPE_ROUNDABOUT_EXIT_CCW -> R.drawable.car_maneuver_roundabout
        Maneuver.TYPE_TURN_SLIGHT_RIGHT, Maneuver.TYPE_TURN_NORMAL_RIGHT, Maneuver.TYPE_TURN_SHARP_RIGHT,
        Maneuver.TYPE_U_TURN_RIGHT, Maneuver.TYPE_ON_RAMP_NORMAL_RIGHT, Maneuver.TYPE_ON_RAMP_SLIGHT_RIGHT,
        Maneuver.TYPE_OFF_RAMP_SLIGHT_RIGHT, Maneuver.TYPE_KEEP_RIGHT, Maneuver.TYPE_MERGE_RIGHT,
        -> R.drawable.car_maneuver_right
        Maneuver.TYPE_TURN_SLIGHT_LEFT, Maneuver.TYPE_TURN_NORMAL_LEFT, Maneuver.TYPE_TURN_SHARP_LEFT,
        Maneuver.TYPE_U_TURN_LEFT, Maneuver.TYPE_ON_RAMP_SLIGHT_LEFT, Maneuver.TYPE_OFF_RAMP_SLIGHT_LEFT,
        Maneuver.TYPE_KEEP_LEFT, Maneuver.TYPE_MERGE_LEFT,
        -> R.drawable.car_maneuver_left
        else -> R.drawable.car_maneuver_straight
    }
}
