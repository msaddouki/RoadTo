# iPhone: lock screen and Dynamic Island

While navigating, the trip shows as a Live Activity: on the lock screen of
any iPhone on iOS 16.2 or later, and in the Dynamic Island on the models
that have one (iPhone 14 Pro and later).

## What it shows

| Where | Content |
| --- | --- |
| Lock screen | maneuver icon, distance to it, street (or instruction), arrival time, distance left, first alert ahead |
| Dynamic Island, compact | maneuver icon and distance |
| Dynamic Island, minimal (shared with another activity) | maneuver icon |
| Dynamic Island, expanded (long press) | the lock screen content, laid out around the island |

Tapping it opens RoadTo. It ends with the trip. If RoadTo stops updating it
(app killed), it turns stale after two minutes and asks to open RoadTo; the
next start ends any activity left behind.

## How it works

- `lib/services/live_activity.dart` words and rounds the content (same
  distances as the phone's panel, arrival to the minute) and sends it only
  when the screen would change, at most every two seconds, on channel
  `org.roadto/live_activity` (`update` {state}, `end`).
- `ios/Runner/GuidanceActivity.swift` starts, updates and ends the activity
  with ActivityKit. Updates come from the app itself, `pushType: nil`: no
  Apple push token, no server, nothing about the trip leaves the phone.
- `ios/RoadToLiveActivity/` is the widget extension that lays it out
  (SwiftUI). `RoadToActivityAttributes.swift` is built into both targets.
- The app still targets iOS 15: ActivityKit is linked weakly and the calls do
  nothing before 16.2.

The user can turn it off in Réglages > RoadTo > Activités en direct; the app
works the same without it.

## Background location while navigating

iOS suspends an app in the background unless it receives location. While a
trip runs, RoadTo now asks for location in the background too
(`UIBackgroundModes` `location`, still with the "when in use" permission), so
guidance, voice and the Live Activity go on with the screen locked; iOS shows
the blue location indicator. Outside a trip, nothing changes: no location in
the background.

With the simulated drive on, the real position is requested during the trip
only to keep the app running, and ignored.

## Testing

`app/test/live_activity_test.dart` checks the content and when it is sent.
CI builds the extension with the app (iOS job). What only a phone can show:
the layout itself, on a real iPhone (or the iOS simulator: start a trip, lock
with ⌘L, or go to the home screen on an iPhone 15 Pro simulator for the
island).

1. Build and install on an iPhone (Xcode, `flutter run`, signed with a
   development team).
2. Start a trip (simulated drive is fine), then lock the phone: the activity
   is on the lock screen. Unlock and go to the home screen: it is in the
   Dynamic Island; long press to expand.
