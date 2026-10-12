import Foundation

nonisolated enum CodexHookSettings {
  /// Single canonical hook map for Codex. See `ClaudeHookSettings` for the
  /// composite-command rationale (one Supacode-managed entry per slot →
  /// idempotent prune-and-replace).
  static func hooksByEvent() throws -> [String: [JSONValue]] {
    try AgentHookPayloadSupport.extractHookGroups(
      from: CodexHooksPayload(),
      invalidConfiguration: CodexHookSettingsError.invalidConfiguration
    )
  }
}

nonisolated enum CodexHookSettingsError: Error {
  case invalidConfiguration
}

// MARK: - Hook payload.

// Codex 0.162+ exposes the same tool- and permission-level hooks Claude does
// (verified against the installed binary: PreToolUse, PostToolUse,
// PermissionRequest, PreCompact, SessionEnd, SubagentStop). The map mirrors
// Claude's: UserPromptSubmit / PreToolUse fire `busy`, PostToolUse fires `idle`
// (the socket debounces between-tool gaps), PermissionRequest is the
// awaiting-input trigger (Codex has no AskUserQuestion-style tool to match), and
// Stop / SessionEnd reset to `idle`. SessionStart fires on the first turn rather
// than on session open (openai/codex#15266). SubagentStop is intentionally
// unmapped: a subagent finishing is not the user's turn.
private nonisolated struct CodexHooksPayload: Encodable {
  private static let busy = AgentHookSettingsCommand.compositeCommand(
    events: [.busy], forwardStdinAsNotification: false, agent: .codex)
  private static let idle = AgentHookSettingsCommand.compositeCommand(
    events: [.idle], forwardStdinAsNotification: false, agent: .codex)
  private static let idleAndNotify = AgentHookSettingsCommand.compositeCommand(
    events: [.idle], forwardStdinAsNotification: true, agent: .codex)
  private static let awaitingInputAndNotify = AgentHookSettingsCommand.compositeCommand(
    events: [.awaitingInput], forwardStdinAsNotification: true, agent: .codex)
  private static let compacting = AgentHookSettingsCommand.compositeCommand(
    events: [.compacting], forwardStdinAsNotification: false, agent: .codex)
  private static let sessionStart = AgentHookSettingsCommand.compositeCommand(
    events: [.sessionStart], forwardStdinAsNotification: false, agent: .codex)
  private static let sessionEndAndIdle = AgentHookSettingsCommand.compositeCommand(
    events: [.sessionEnd, .idle], forwardStdinAsNotification: false, agent: .codex)

  private static func group(_ command: String, matcher: String? = nil) -> AgentHookGroup {
    .init(matcher: matcher, hooks: [.init(command: command, timeout: AgentHookSettingsCommand.timeoutSeconds)])
  }

  let hooks: [String: [AgentHookGroup]] = [
    "SessionStart": [group(Self.sessionStart)],
    "UserPromptSubmit": [group(Self.busy)],
    "PreToolUse": [group(Self.busy, matcher: "")],
    "PostToolUse": [group(Self.idle, matcher: "")],
    "PermissionRequest": [group(Self.awaitingInputAndNotify, matcher: "")],
    "PreCompact": [group(Self.compacting)],
    "Stop": [group(Self.idleAndNotify)],
    "SessionEnd": [group(Self.sessionEndAndIdle, matcher: "")],
  ]
}
