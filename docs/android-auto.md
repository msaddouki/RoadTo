# Android Auto

The car screen shows the phone's guidance: the phone app computes the route,
the guidance and the alerts, the car app (`app/android/…/car/`) draws them
and sends back what the driver taps. This is spike D of the plan, and the
start of milestone J4.

## What the car shows

- **Map** on the car's own surface: MapLibre, drawn on a virtual display,
  with the phone's style (the offline region style when installed), the
  route and the position; the camera follows the car, kept inside the area
  the templates leave visible.
- **Navigation template**: next maneuver (Valhalla's French instruction, an
  icon per family of maneuvers), distance to it, time and distance left,
  arrival time.
- **Signaler**: a grid of five types (accident, bouchon, danger, route
  fermée, travaux). Police stays out until the L130-11 channel (J6).
- **"Toujours là ?"** when passing an alert: a car alert with Oui / Non,
  10 s, no answer counts as unknown (car API level 5 and later; older hosts
  get a message and the phone asks).
- **Arrêter** stops the trip on the phone.

Without the phone app running, the car asks to open it; without a trip, it
asks to choose a destination on the phone.

## How the two sides talk

Channel `org.roadto/car`, between `lib/services/car_link.dart` and
`car/CarBridge.kt`:

| Direction | Method | Content |
| --- | --- | --- |
| phone → car | `update` | navigating, next maneuver, remaining distance and time, arrival, position, bearing, speed and limit, map style, alert ahead, pending "Toujours là ?", route shape (only when it changes) |
| car → phone | `report` | `{type}`: an `AlertType` code (police refused) |
| car → phone | `confirm` | `{id, stillThere}`: true, false or null |
| car → phone | `stop` | none |

Updates are sent at most twice a second.

## Testing on the desktop head unit (DHU)

Everything stays in simulation first (plan, cross-cutting rules): DHU, then
a car with a passenger handling the phone.

1. On the computer: `sdkmanager "extras;google;auto"` (Android SDK), which
   installs `desktop-head-unit` in `$ANDROID_HOME/extras/google/auto/`.
2. On the phone: install the debug build (`flutter run` or the CI APK).
   Debug builds accept any car host; release builds only the known ones.
3. In the Android Auto settings on the phone (Settings → Apps → Android Auto
   → Additional settings): tap *Version* ten times to unlock developer
   settings, then in the ⋮ menu choose *Start head unit server*, and in
   *Developer settings* tick *Unknown sources*.
4. Connect the phone over USB, then on the computer:
   `adb forward tcp:5277 tcp:5277` and run `desktop-head-unit`.
5. Open RoadTo on the phone (it must run for the car to show anything),
   choose a destination: the DHU shows the map, the maneuver and the
   estimate; *Signaler* opens the grid.

The simulated drive (on by default) moves the position, so the whole trip
plays in the DHU without moving.

## Tests without a head unit

`app/android/app/src/test/…/car/CarScreensTest.kt` checks the templates on
the JVM (Robolectric and the car library's `app-testing`): what the
navigation screen shows in its three states, the report grid, the stop
action, distance rounding, and reading the phone's state. CI runs them in
the Android APK job (`./gradlew :app:testDebugUnitTest`).
`app/test/car_link_test.dart` checks the phone side.

What these cannot check, and the DHU must: the map actually drawing on the
car surface (the spike's open question), frame rate, and the alert on a real
host.

## Not done yet (J4)

- Working without the phone app open (a Flutter engine started by the car
  service).
- Voice reporting with a closed grammar recognised offline (Vosk).
- List of fuel and charging stations along the route.
- Google Play's Android Auto review (internal test track).
