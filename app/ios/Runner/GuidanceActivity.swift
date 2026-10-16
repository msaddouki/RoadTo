import ActivityKit
import Flutter
import Foundation

/// Channel "org.roadto/live_activity" (lib/services/live_activity.dart):
/// "update" {state} starts the trip's Live Activity or updates it, "end"
/// ends every RoadTo activity. Needs iOS 16.2; earlier, calls do nothing.
enum GuidanceActivity {
  static func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard #available(iOS 16.2, *) else {
      result(false)
      return
    }
    switch call.method {
    case "update":
      guard let args = call.arguments as? [String: Any],
        let state = RoadToActivityAttributes.ContentState(args)
      else {
        result(FlutterError(code: "args", message: "bad live activity state", details: nil))
        return
      }
      let destination = args["destination"] as? String ?? ""
      Task { @MainActor in
        await LiveTrip.show(state, destination: destination)
        result(true)
      }
    case "end":
      Task { @MainActor in
        await LiveTrip.endAll()
        result(true)
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}

@available(iOS 16.2, *)
@MainActor
private enum LiveTrip {
  static var current: Activity<RoadToActivityAttributes>?

  static func show(_ state: RoadToActivityAttributes.ContentState, destination: String) async {
    // Shown as stale (and "Ouvrez RoadTo") when the app stops updating it,
    // for instance once killed.
    let content = ActivityContent(state: state, staleDate: Date().addingTimeInterval(120))
    if let activity = current, activity.activityState == .active {
      if activity.attributes.destination == destination {
        await activity.update(content)
        return
      }
      await activity.end(nil, dismissalPolicy: .immediate)
    }
    // Off in Settings > RoadTo > Activités en direct: the app works as before.
    guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
    current = try? Activity.request(
      attributes: RoadToActivityAttributes(destination: destination),
      content: content,
      pushType: nil
    )
  }

  static func endAll() async {
    for activity in Activity<RoadToActivityAttributes>.activities {
      await activity.end(nil, dismissalPolicy: .immediate)
    }
    current = nil
  }
}

@available(iOS 16.1, *)
extension RoadToActivityAttributes.ContentState {
  init?(_ m: [String: Any]) {
    guard let symbol = m["symbol"] as? String,
      let distance = m["distance"] as? String,
      let title = m["title"] as? String,
      let remaining = m["remaining"] as? String,
      let arrivalMs = (m["arrivalEpochMs"] as? NSNumber)?.doubleValue
    else { return nil }
    self.init(
      symbol: symbol,
      distance: distance,
      title: title,
      instruction: m["instruction"] as? String ?? "",
      remaining: remaining,
      arrival: Date(timeIntervalSince1970: arrivalMs / 1000),
      alert: m["alert"] as? String,
      arrived: m["arrived"] as? Bool ?? false
    )
  }
}
