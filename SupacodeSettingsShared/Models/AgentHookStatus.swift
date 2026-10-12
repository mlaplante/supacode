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
      let s = max(0, Int(now.timeIntervalSince(lastEventAt)))
      return .healthy(lastEvent: s < 3_600 ? "\(s / 60)m \(s % 60)s" : "\(s / 3_600)h \((s % 3_600) / 60)m")
    }
  }

  public var text: String {
    switch self {
    case .healthy(let e): "Hooks installed \u{00B7} last event \(e) ago"
    case .installedNoEvents: "Hooks installed \u{00B7} no events received this session"
    case .outdated: "Hooks outdated"
    case .notInstalled: "Hooks not installed"
    }
  }
}
