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

extension ElapsedFormatter {
  /// Which formatter a timeline feeds. Each changes its text on a different
  /// grid, so each gets its own tick stride.
  enum Style {
    case compact
    case spoken
  }

  /// Seconds until the formatted text can next change, at a given elapsed time.
  /// Compact drops seconds after a minute; spoken keeps them for the first hour.
  static func stride(forElapsed seconds: Int, style: Style) -> Int {
    switch (style, seconds) {
    case (.compact, ..<60), (.spoken, ..<3_600): 1
    case (.compact, ..<3_600), (.spoken, ..<86_400): 60
    case (.compact, ..<86_400), (.spoken, _): 3_600
    case (.compact, _): 86_400
    }
  }
}

/// Ticks only when the formatted elapsed text can change: every second while
/// seconds are shown, then every minute, hour, or day. Yields a single entry
/// when paused, so a view keeps one stable `TimelineView` either way.
struct ElapsedSchedule: TimelineSchedule {
  /// Lands each tick just past its boundary. `since + 60` minus `since` can come
  /// back as 59.999… at real epoch magnitudes, which would floor to the old text.
  static let boundaryNudge: TimeInterval = 0.005

  let start: Date
  let style: ElapsedFormatter.Style
  let isPaused: Bool

  func entries(from startDate: Date, mode: TimelineScheduleMode) -> AnySequence<Date> {
    if isPaused { return AnySequence([startDate]) }
    let start = start
    let style = style
    return AnySequence(
      sequence(first: startDate) { date in
        let elapsed = max(0, Int(date.timeIntervalSince(start)))
        let step = ElapsedFormatter.stride(forElapsed: elapsed, style: style)
        let next = (elapsed / step + 1) * step
        return start.addingTimeInterval(TimeInterval(next) + Self.boundaryNudge)
      })
  }
}

/// Self-ticking compact elapsed label. Ticks only when the compact text changes,
/// so the reducer never schedules display work. `stateLabel` is the VoiceOver
/// verb phrase ("waiting", "errored"). Past a minute the VoiceOver seconds can
/// lag by up to 59 s; that is the price of not re-rendering every second.
struct ElapsedLabel: View {
  let since: Date
  var stateLabel = "waiting"

  var body: some View {
    TimelineView(ElapsedSchedule(start: since, style: .compact, isPaused: false)) { context in
      Text(ElapsedFormatter.compact(from: since, to: context.date))
        .appFont(.caption)
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .accessibilityLabel("\(stateLabel) \(ElapsedFormatter.spoken(from: since, to: context.date))")
    }
  }
}
