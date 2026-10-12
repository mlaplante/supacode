import ComposableArchitecture
import Foundation

/// Raised when a test event can't be delivered.
public nonisolated enum AgentHookActivityError: Error, LocalizedError, Equatable {
  case noFocusedSurface

  public var errorDescription: String? {
    switch self {
    case .noFocusedSurface: "Focus a terminal first."
    }
  }
}

/// App-side hook liveness exposed to the settings module, which cannot see
/// presence state directly. Wraps app state, not `@Shared`.
public nonisolated struct AgentHookActivityClient: Sendable {
  public var lastEventDates: @Sendable () async -> [SkillAgent: Date]
  /// Runs the agent's own installed hook command with SUPACODE_* env set to the
  /// focused surface, so the full OSC path is exercised.
  public var sendTestEvent: @Sendable (SkillAgent) async throws -> Void

  public init(
    lastEventDates: @escaping @Sendable () async -> [SkillAgent: Date],
    sendTestEvent: @escaping @Sendable (SkillAgent) async throws -> Void
  ) {
    self.lastEventDates = lastEventDates
    self.sendTestEvent = sendTestEvent
  }
}

nonisolated extension AgentHookActivityClient {
  /// Mirror of the presence reducer's `lastEventAt`, fed by `AppFeature` on every
  /// hook event. Process-wide so the live client needs no store reference.
  private static let mirror = LockIsolated<[SkillAgent: Date]>([:])

  /// Called by the app reducer for each received hook event.
  public static func recordEvent(agent: SkillAgent, at date: Date) {
    mirror.withValue { $0[agent] = date }
  }
}

extension AgentHookActivityClient: DependencyKey {
  public static let liveValue = Self(
    lastEventDates: { mirror.value },
    // The surface env is not reachable from here, and the hook resolves its tty
    // from its parent process, so it cannot reach a surface from outside one.
    sendTestEvent: { _ in throw AgentHookActivityError.noFocusedSurface }
  )

  public static let testValue = Self(lastEventDates: { [:] }, sendTestEvent: { _ in })
}

extension DependencyValues {
  public var agentHookActivityClient: AgentHookActivityClient {
    get { self[AgentHookActivityClient.self] }
    set { self[AgentHookActivityClient.self] = newValue }
  }
}
