import SupacodeSettingsShared
import SwiftUI

/// Wall-clock elapsed formatting for agent presence. Pure so the sidebar row,
/// the menu bar and the tooltip agree to the second.
enum ElapsedFormatter {
  /// "5s", "4m", "2h", "3d": one unit, floor-rounded. For the row accessory.
  static func compact(from start: Date, to now: Date) -> String {
    let seconds = max(0, Int(now.timeIntervalSince(start)))
    switch seconds {
    case ..<60: return "\(seconds)s"
    case ..<3_600: return "\(seconds / 60)m"
    case ..<86_400: return "\(seconds / 3_600)h"
    default: return "\(seconds / 86_400)d"
    }
  }

  /// "4m 12s", "1h 1m", "2d 3h": two units. For tooltips and VoiceOver.
  static func spoken(from start: Date, to now: Date) -> String {
    let seconds = max(0, Int(now.timeIntervalSince(start)))
    switch seconds {
    case ..<60: return "\(seconds)s"
    case ..<3_600: return "\(seconds / 60)m \(seconds % 60)s"
    case ..<86_400: return "\(seconds / 3_600)h \((seconds % 3_600) / 60)m"
    default: return "\(seconds / 86_400)d \((seconds % 86_400) / 3_600)h"
    }
  }
}

/// Self-ticking compact elapsed label. Ticks once a second via `TimelineView`,
/// so the reducer never schedules display work. Pass `isTicking: false` to
/// freeze (e.g. while the row is off screen or the state is not attention).
struct ElapsedLabel: View {
  let since: Date
  var isTicking = true

  var body: some View {
    TimelineView(.periodic(from: since, by: isTicking ? 1 : .infinity)) { context in
      Text(ElapsedFormatter.compact(from: since, to: context.date))
        .appFont(.caption)
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .accessibilityLabel("waiting \(ElapsedFormatter.spoken(from: since, to: context.date))")
    }
  }
}
