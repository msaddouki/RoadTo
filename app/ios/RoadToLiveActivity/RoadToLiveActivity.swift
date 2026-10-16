import ActivityKit
import SwiftUI
import WidgetKit

/// The trip on the lock screen and in the Dynamic Island, in the colours of
/// the phone's navigation screen (lib/ui/navigation_panels.dart).
@main
struct RoadToWidgets: WidgetBundle {
  var body: some Widget {
    TripActivity()
  }
}

private enum Palette {
  static let banner = Color(red: 0x1B / 255, green: 0x3A / 255, blue: 0x73 / 255)
  static let eta = Color(red: 0x7F / 255, green: 0xE0 / 255, blue: 0xA0 / 255)
  static let report = Color(red: 0xF5 / 255, green: 0xB8 / 255, blue: 0x3D / 255)
  static let muted = Color(red: 0xA9 / 255, green: 0xB3 / 255, blue: 0xBD / 255)
}

struct TripActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: RoadToActivityAttributes.self) { context in
      LockScreenView(state: context.state, stale: context.isStale)
        .activityBackgroundTint(Palette.banner)
        .activitySystemActionForegroundColor(.white)
    } dynamicIsland: { context in
      let s = context.state
      return DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          VStack(alignment: .leading, spacing: 2) {
            ManeuverIcon(symbol: s.symbol, size: 34)
            Text(s.distance).font(.title3.monospacedDigit().bold())
          }
        }
        DynamicIslandExpandedRegion(.trailing) {
          VStack(alignment: .trailing, spacing: 2) {
            Text(s.arrival, style: .time).font(.title3.monospacedDigit().bold()).foregroundColor(Palette.eta)
            Text(s.remaining).font(.footnote.monospacedDigit()).foregroundColor(Palette.muted)
          }
        }
        DynamicIslandExpandedRegion(.center) {
          Text(s.title).font(.headline).lineLimit(2).multilineTextAlignment(.center)
        }
        DynamicIslandExpandedRegion(.bottom) {
          if let alert = s.alert {
            AlertLine(text: alert)
          } else if context.isStale {
            Text("Ouvrez RoadTo pour reprendre le guidage").font(.footnote).foregroundColor(Palette.muted)
          }
        }
      } compactLeading: {
        ManeuverIcon(symbol: s.symbol, size: 18)
      } compactTrailing: {
        Text(s.arrived ? "Arrivé" : s.distance).font(.callout.monospacedDigit().bold())
      } minimal: {
        ManeuverIcon(symbol: s.symbol, size: 18)
      }
      .keylineTint(Palette.eta)
    }
  }
}

private struct ManeuverIcon: View {
  let symbol: String
  let size: CGFloat

  var body: some View {
    Image(systemName: symbol)
      .font(.system(size: size, weight: .bold))
      .foregroundColor(.white)
      .accessibilityHidden(true)
  }
}

private struct AlertLine: View {
  let text: String

  var body: some View {
    Label(text, systemImage: "exclamationmark.triangle.fill")
      .font(.subheadline.bold())
      .foregroundColor(Palette.report)
      .lineLimit(1)
  }
}

private struct LockScreenView: View {
  let state: RoadToActivityAttributes.ContentState
  let stale: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .center, spacing: 12) {
        ManeuverIcon(symbol: state.symbol, size: 40)
        VStack(alignment: .leading, spacing: 2) {
          if !state.distance.isEmpty {
            Text(state.distance).font(.title2.monospacedDigit().bold()).foregroundColor(.white)
          }
          Text(state.title).font(.headline).foregroundColor(.white).lineLimit(2)
        }
        Spacer(minLength: 8)
        VStack(alignment: .trailing, spacing: 2) {
          Text(state.arrival, style: .time).font(.title3.monospacedDigit().bold()).foregroundColor(Palette.eta)
          Text(state.remaining).font(.footnote.monospacedDigit()).foregroundColor(Palette.muted)
        }
      }
      if let alert = state.alert {
        AlertLine(text: alert)
      }
      if stale {
        Text("Ouvrez RoadTo pour reprendre le guidage").font(.footnote).foregroundColor(Palette.muted)
      }
    }
    .padding(16)
  }
}
