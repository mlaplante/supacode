import Foundation
import Testing

@testable import SupacodeSettingsShared

struct CodexHookSettingsTests {
  private static func commandStrings(in groups: [JSONValue]) -> [String] {
    groups.flatMap { group -> [String] in
      (group.objectValue?["hooks"]?.arrayValue ?? []).compactMap {
        $0.objectValue?["command"]?.stringValue
      }
    }
  }

  @Test func codexMapsPermissionRequestToAwaitingInputWithNotify() throws {
    let groups = try CodexHookSettings.hooksByEvent()
    let permission = try #require(groups["PermissionRequest"])
    let commands = Self.commandStrings(in: permission)
    #expect(commands.count == 1)
    #expect(commands[0].contains("event=awaiting_input"))
    #expect(commands[0].contains("kind=notify"))
  }

  @Test func codexToolHooksTrackBusyAndIdle() throws {
    let groups = try CodexHookSettings.hooksByEvent()
    let pre = Self.commandStrings(in: try #require(groups["PreToolUse"]))
    let post = Self.commandStrings(in: try #require(groups["PostToolUse"]))
    #expect(pre.allSatisfy { $0.contains("event=busy") })
    #expect(post.allSatisfy { $0.contains("event=idle") })
  }

  @Test func codexMapsPreCompactAndSessionEnd() throws {
    let groups = try CodexHookSettings.hooksByEvent()
    let compact = Self.commandStrings(in: try #require(groups["PreCompact"]))
    #expect(compact.allSatisfy { $0.contains("event=compacting") })
    let end = Self.commandStrings(in: try #require(groups["SessionEnd"]))
    #expect(end.count == 1)
    #expect(end[0].contains("event=session_end"))
    #expect(end[0].contains("event=idle"))
  }

  @Test func codexStopStillIdlesAndNotifies() throws {
    let groups = try CodexHookSettings.hooksByEvent()
    let stop = Self.commandStrings(in: try #require(groups["Stop"]))
    #expect(stop.count == 1)
    #expect(stop[0].contains("event=idle"))
    #expect(stop[0].contains("kind=notify"))
  }

  @Test func codexEventSetIsExactlyTheParitySet() throws {
    let groups = try CodexHookSettings.hooksByEvent()
    #expect(
      Set(groups.keys) == [
        "SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse",
        "PermissionRequest", "PreCompact", "Stop", "SessionEnd",
      ])
  }
}
