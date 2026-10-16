import ActivityKit
import Foundation

/// A trip shown as a Live Activity (lock screen, Dynamic Island). Built into
/// both the app, which starts and updates it, and the widget extension,
/// which lays it out. The text comes worded and rounded from the Dart side
/// (lib/services/live_activity.dart).
@available(iOS 16.1, *)
struct RoadToActivityAttributes: ActivityAttributes {
  struct ContentState: Codable, Hashable {
    /// SF Symbol of the next maneuver.
    var symbol: String
    /// Distance to it, "250 m".
    var distance: String
    /// Street, or the instruction when there is none.
    var title: String
    var instruction: String
    /// Distance left, "5,4 km".
    var remaining: String
    var arrival: Date
    /// First alert ahead, "Accident à 800 m".
    var alert: String?
    var arrived: Bool
  }

  var destination: String
}
