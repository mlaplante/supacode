import ComposableArchitecture
import Foundation

/// App-side hook liveness exposed to the settings module, which cannot see
/// presence state directly. Wraps app state, not `@Shared`.
public nonisolated struct AgentHookActivityClient: Sendable {
  public var lastEventDates: @Sendable () async -> [SkillAgent: Date]

  public init(lastEventDates: @escaping @Sendable () async -> [SkillAgent: Date]) {
    self.lastEventDates = lastEventDates
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

  /// Shell input for the Developer settings test event: the real hook emit for a
  /// pid-less `idle`, which stamps `lastEventAt` without seeding a presence
  /// record. Typed into a Supacode surface it exercises the OSC 3008 path.
  public static func testEventInput(for agent: SkillAgent) -> String {
    AgentHookSettingsCommand.compositeCommand(
      events: [.idle], forwardStdinAsNotification: false, agent: agent
    ) + "\n"
  }
}

extension AgentHookActivityClient: DependencyKey {
  public static let liveValue = Self(lastEventDates: { mirror.value })
  public static let testValue = Self(lastEventDates: { [:] })
}

extension DependencyValues {
  public var agentHookActivityClient: AgentHookActivityClient {
    get { self[AgentHookActivityClient.self] }
    set { self[AgentHookActivityClient.self] = newValue }
  }
}
