import Foundation

/// What the Developer settings row says about one agent's hook liveness.
public nonisolated enum AgentHookStatus: Equatable, Sendable {
  case healthy(lastEvent: String)
  case installedNoEvents
  case outdated
  case notInstalled

  public static func resolve(
    installed: AgentIntegrationState, lastEventAt: Date?, now: Date
  ) -> AgentHookStatus {
    switch installed {
    case .notInstalled: return .notInstalled
    case .outdated: return .outdated
    case .installed:
      guard let lastEventAt else { return .installedNoEvents }
      let seconds = max(0, Int(now.timeIntervalSince(lastEventAt)))
      let elapsed =
        seconds < 3_600
        ? "\(seconds / 60)m \(seconds % 60)s"
        : "\(seconds / 3_600)h \((seconds % 3_600) / 60)m"
      return .healthy(lastEvent: elapsed)
    }
  }

  public var text: String {
    switch self {
    case .healthy(let elapsed): "Hooks installed \u{00B7} last event \(elapsed) ago"
    case .installedNoEvents: "Hooks installed \u{00B7} no events received this session"
    case .outdated: "Hooks outdated"
    case .notInstalled: "Hooks not installed"
    }
  }
}
