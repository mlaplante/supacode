# Agent Presence and Worktree Hygiene Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give Supacode users running many Claude Code and Codex sessions the signals they need to pick the next worktree, keep branches in sync, and clean up dead worktrees.

**Architecture:** One foundation change stamps a `Date` on every agent presence transition; the badge, the needs-you queue, and the agent-state sort all read from it. A second foundation adds ahead/behind, rebase and merge to `GitClient`; the behind-count accessory and the stale classifier read from those. Codex hook parity and the settings health check are independent edges on the same hook pipeline.

**Tech Stack:** Swift 6, SwiftUI, The Composable Architecture (TCA), swift-dependencies, Swift Testing (`@Test`, `#expect`). Build with `make build-app`; test with `make test`.

**Spec:** `docs/superpowers/specs/2026-10-12-agent-presence-and-worktree-hygiene-design.md`

## Global Constraints

- Target macOS 26.0+, Swift 6.0. Modern SwiftUI only (`foregroundStyle()`, `Button` over `onTapGesture()`).
- `@ObservableState` for TCA state; `@Observable` + `@MainActor` for non-TCA stores; never `ObservableObject`.
- `@Shared` directly in reducers for settings; no new dependency clients solely wrapping `@Shared`.
- `SupaLogger` for all logging; never `print()` or `os.Logger`.
- No NSNotification between reducers. No top-level free functions.
- In tests never use `Task.sleep`; use `TestClock` or `.constant` dates.
- Menu-bar closures go through `FocusedAction` with `.focusedSceneAction(_:enabled:token:perform:)`.
- Sidebar per-leaf invalidation: per-row state lives on `SidebarItemFeature.State`; views render `sidebarStructure`, never `sidebarItems[id:]` from a body.
- Buttons must have tooltips (`.help`) naming the action and hotkey. Dynamic Type; `.monospaced()` for counts. System colors only.
- Every reducer logic change gets tests. After every task: `make build-app` passes.
- Commit after each task with `git add <specific files>`; never `git add .`. No AI co-author trailers.
- Running one suite: `make test` runs everything (slow). For one suite use:
  ```bash
  DEVELOPER_DIR="$(./scripts/select-developer-dir.sh)" xcodebuild test -workspace supacode.xcworkspace -scheme supacode-tests -destination "platform=macOS" -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO -skipMacroValidation -only-testing:supacodeTests/<SuiteName> 2>&1 | mise exec -- xcbeautify
  ```
  Replace `<SuiteName>` with the struct name of the test suite (e.g. `AgentPresenceFeatureTests`).

## Review Focus

1. **A pid-less Codex session over SSH** receives `PermissionRequest` before any `session_start`. Expect: the record auto-seeds as `awaitingInput` exactly as Claude's does. Pinned by Task 1 test `codexPermissionRequestMapsToAwaitingInput` plus existing `applyActivity` seed rule.
2. **A layout snapshot written by the previous app version** has no `activitySince`. Expect: restore succeeds and the badge shows elapsed time from launch, not a crash or a 1970 date. Pinned by Task 3 test `restoreWithoutActivitySinceFallsBackToNow`.
3. **An agent flips busy→idle→busy within one second** (tool loop). Expect: the badge's elapsed time resets only on the attention transition the user cares about, and `since` on the row reflects the earliest attention-state agent, not the latest flicker. Pinned by Task 3 test `rowSnapshotSinceIsEarliestAttentionDate`.
4. **Rebase hits a conflict** while the user has unsaved editor buffers. Expect: the worktree is left exactly as before (abort ran), counts unchanged, one alert. Pinned by Task 9 test `rebaseConflictAbortsAndThrows` and Task 10 test `syncConflictShowsAlertAndKeepsCounts`.
5. **A stale sweep runs on a worktree with an open PR but zero ahead commits** (PR opened from another clone). Expect: never classified stale. Pinned by Task 12 test `openPullRequestNeverStale`.

---

## File map

| Workstream | Create | Modify |
|---|---|---|
| W0 Codex hooks | `supacodeTests/CodexHookSettingsTests.swift` | `SupacodeSettingsShared/BusinessLogic/CodexHookSettings.swift`, `SupacodeSettingsShared/Models/SkillAgent.swift`, `supacodeTests/SkillAgentTests.swift` |
| W1 Presence timestamps | — | `supacode/Features/AgentPresence/Reducer/AgentPresenceFeature.swift`, `supacode/Features/Terminal/Models/TerminalLayoutSnapshot.swift`, `supacodeTests/AgentPresenceFeatureTests.swift` |
| W2 Badge elapsed | `supacode/Features/AgentPresence/Views/ElapsedLabel.swift`, `supacodeTests/ElapsedFormatterTests.swift` | `AgentBadgeView.swift`, `AgentAvatarGroupView.swift`, `supacode/Features/Repositories/Views/SidebarItemView.swift` |
| W3 Needs-you queue | `supacodeTests/AppFeatureJumpToNextAwaitingTests.swift` | `MenuBarNotificationList.swift`, `SidebarStructure.swift`, `AppFeature.swift`, `WorktreeCommands.swift`, `AppShortcuts.swift`, `MenuBarNotificationsMenu.swift`, tests |
| W5 Branch sync | `supacodeTests/GitClientAheadBehindTests.swift`, `supacode/Features/Repositories/Models/WorktreeSyncState.swift` | `GitClient.swift`, `GitClientDependency.swift`, `SidebarItemFeature.swift`, `RepositoriesFeature.swift`, `SidebarItemView.swift`, `SidebarItemsView.swift` |
| W4 Stale review | `supacode/Domain/StaleWorktreeClassifier.swift`, `supacode/Features/Repositories/Views/StaleWorktreesDetailView.swift`, `supacodeTests/StaleWorktreeClassifierTests.swift` | `SidebarState.swift`, `SidebarItemFeature.swift`, `RepositoriesFeature.swift`, `GlobalSettings.swift`, `SettingsFeature.swift`, settings view, `SidebarSelection.swift`, `WorktreeDetailView.swift`, `WindowTitle.swift`, `WorktreeCommands.swift` |
| W6 Worktree sort | `supacode/Domain/SidebarWorktreeSort.swift`, `supacodeTests/SidebarWorktreeSortTests.swift` | `SidebarState.swift`, `SidebarStructure.swift`, `SidebarItemsView.swift`, `RepositoriesFeature.swift` |
| W7 Health check | `SupacodeSettingsShared/Clients/CodingAgents/AgentHookActivityClient.swift` | `SettingsFeature.swift`, `DeveloperSettingsView.swift`, `AppFeature.swift`, tests |

Execution order and parallelism: Tasks 1–2 (W0), 3–4 (W1), 9 (W5 git) are independent and can run concurrently. Tasks 5–8 need W1. Task 10 needs 9. Tasks 11–13 need 9 and 10. Task 14 needs 3 and 11. Task 15 needs 3.

---

## W0. Codex hook parity

### Task 1: Extend the Codex hook map

**Files:**
- Modify: `SupacodeSettingsShared/BusinessLogic/CodexHookSettings.swift`
- Create: `supacodeTests/CodexHookSettingsTests.swift`

**Interfaces:**
- Consumes: `AgentHookSettingsCommand.compositeCommand(events:forwardStdinAsNotification:agent:)`, `HookEvent` cases.
- Produces: `CodexHookSettings.hooksByEvent()` now returns groups for `SessionStart`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `PermissionRequest`, `PreCompact`, `Stop`, `SessionEnd`.

- [ ] **Step 1: Write the failing test**

```swift
// supacodeTests/CodexHookSettingsTests.swift
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
```

- [ ] **Step 2: Run the suite to verify it fails**

Run the single-suite command with `CodexHookSettingsTests`. Expected: FAIL on `PermissionRequest`, `PreToolUse`, `PostToolUse`, `PreCompact`, `SessionEnd` being nil.

- [ ] **Step 3: Replace the payload in `CodexHookSettings.swift`**

Replace the `CodexHooksPayload` struct and its leading comment with:

```swift
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
```

Check `AgentHookGroup.init` signature in `AgentHookPayloadSupport.swift`; if `matcher` is not optional, use `.init(hooks:)` for the no-matcher groups and `.init(matcher:hooks:)` for the others, exactly as `ClaudeHooksPayload` does.

- [ ] **Step 4: Run the suite to verify it passes**

Run `CodexHookSettingsTests` and `AgentHookCommandTests`. Expected: PASS. `AgentHookSettingsFileInstallerTests` and `CodexSettingsInstallerTests` must also still pass (prune is marker-based, not event-based).

- [ ] **Step 5: Commit**

```bash
git add SupacodeSettingsShared/BusinessLogic/CodexHookSettings.swift supacodeTests/CodexHookSettingsTests.swift
git commit -m "Codex hooks: add tool, permission, compaction and session-end events"
```

### Task 2: Codex capability flags

**Files:**
- Modify: `SupacodeSettingsShared/Models/SkillAgent.swift` (the `supports(_:)` switch, ~line 88)
- Modify: `supacodeTests/SkillAgentTests.swift`

- [ ] **Step 1: Write the failing test** (append to `SkillAgentTests`)

```swift
@Test func codexReportsInputNeededAndCompactionAfterHookParity() {
  #expect(SkillAgent.codex.supports(.inputNeededBadge))
  #expect(SkillAgent.codex.supports(.compactionBadge))
  #expect(!SkillAgent.codex.supports(.errorDetection))
}
```

- [ ] **Step 2: Run `SkillAgentTests`; expect FAIL** on the first two expectations.

- [ ] **Step 3: Update the flags**

```swift
case .inputNeededBadge:
  self == .claude || self == .codex || self == .grok || self == .copilot || self == .kimi || self == .opencode
case .errorDetection:
  self == .claude || self == .antigravity
case .compactionBadge:
  self == .claude || self == .codex
```

- [ ] **Step 4: Run `SkillAgentTests`; expect PASS.** Also run `SettingsFeatureAgentIntegrationTests` (capability grid snapshots may assert counts).

- [ ] **Step 5: Verify the auto-upgrade path.** In `supacodeTests/AgentHookSettingsFileInstallerTests.swift` find the existing `installState` test for an outdated set and confirm it covers "managed set on disk is a strict subset of canonical → `.outdated`". If no such case exists, add:

```swift
@Test func installStateIsOutdatedWhenCanonicalGainsAnEvent() throws {
  // Install the old three-event Codex map by hand, then ask for state with the new map.
  // Use the installer's own fixture helpers in this file to write a hooks file
  // containing only SessionStart / UserPromptSubmit / Stop managed commands.
  // Expect `.outdated`, which is what triggers SettingsFeature's once-per-session reinstall.
}
```

Fill the body with the fixture helpers present in that file (they create a temp home and write `hooks.json`); assert `installState == .outdated`.

- [ ] **Step 6: Commit**

```bash
git add SupacodeSettingsShared/Models/SkillAgent.swift supacodeTests/SkillAgentTests.swift supacodeTests/AgentHookSettingsFileInstallerTests.swift
git commit -m "Codex: advertise input-needed and compaction badges"
```

---

## W1. Presence timestamps

### Task 3: Stamp `activitySince` on presence records

**Files:**
- Modify: `supacode/Features/AgentPresence/Reducer/AgentPresenceFeature.swift`
- Modify: `supacode/Features/Terminal/Models/TerminalLayoutSnapshot.swift` (`SurfaceAgentRecord`, ~line 94)
- Modify: `supacodeTests/AgentPresenceFeatureTests.swift`

**Interfaces:**
- Produces:
  - `PresenceRecord.activitySince: Date`
  - `AgentInstance.since: Date`
  - `RowSnapshot.since: Date?` (earliest attention-state date, else earliest working date, else nil)
  - `State.lastEventAt: [SkillAgent: Date]`
  - `RestoredRecord.activitySince: Date`, `StagedRestore.activitySince: Date?`
  - `SurfaceAgentRecord.activitySince: Date?` (Codable, optional)
  - `AgentPresenceFeature` reads `@Dependency(\.date.now)`.

- [ ] **Step 1: Write the failing tests** (append inside `AgentPresenceFeatureTests`)

```swift
// MARK: - Activity timestamps.

@Test func activityChangeStampsSince() {
  let t0 = Date(timeIntervalSince1970: 1_000)
  let t1 = Date(timeIntervalSince1970: 1_060)
  var harness = Harness(now: t0)
  let surfaceID = UUID()
  harness.send(.hookEventReceived(makeEvent(.sessionStart, agent: .claude, surfaceID: surfaceID, pid: getpid())))
  harness.now = t1
  harness.send(.hookEventReceived(makeEvent(.awaitingInput, agent: .claude, surfaceID: surfaceID, pid: getpid())))
  let key = AgentPresenceFeature.PresenceKey(agent: .claude, surfaceID: surfaceID)
  #expect(harness.state.records[key]?.activitySince == t1)
}

@Test func unchangedActivityDoesNotRestamp() {
  let t0 = Date(timeIntervalSince1970: 1_000)
  var harness = Harness(now: t0)
  let surfaceID = UUID()
  harness.send(.hookEventReceived(makeEvent(.sessionStart, agent: .claude, surfaceID: surfaceID, pid: getpid())))
  harness.send(.hookEventReceived(makeEvent(.busy, agent: .claude, surfaceID: surfaceID, pid: getpid())))
  harness.now = Date(timeIntervalSince1970: 2_000)
  harness.send(.hookEventReceived(makeEvent(.busy, agent: .claude, surfaceID: surfaceID, pid: getpid())))
  let key = AgentPresenceFeature.PresenceKey(agent: .claude, surfaceID: surfaceID)
  #expect(harness.state.records[key]?.activitySince == t0)
}

@Test func clearAttentionRestamps() {
  let t0 = Date(timeIntervalSince1970: 1_000)
  let t1 = Date(timeIntervalSince1970: 1_500)
  var harness = Harness(now: t0)
  let surfaceID = UUID()
  harness.send(.hookEventReceived(makeEvent(.sessionStart, agent: .claude, surfaceID: surfaceID, pid: getpid())))
  harness.send(.hookEventReceived(makeEvent(.awaitingInput, agent: .claude, surfaceID: surfaceID, pid: getpid())))
  harness.now = t1
  harness.send(.clearAttention(surfaces: [surfaceID]))
  let key = AgentPresenceFeature.PresenceKey(agent: .claude, surfaceID: surfaceID)
  #expect(harness.state.records[key]?.activity == .idle)
  #expect(harness.state.records[key]?.activitySince == t1)
}

@Test func rowSnapshotSinceIsEarliestAttentionDate() {
  var harness = Harness(now: Date(timeIntervalSince1970: 100))
  let a = UUID()
  let b = UUID()
  harness.send(.hookEventReceived(makeEvent(.sessionStart, agent: .claude, surfaceID: a, pid: getpid())))
  harness.send(.hookEventReceived(makeEvent(.sessionStart, agent: .codex, surfaceID: b, pid: getpid())))
  harness.now = Date(timeIntervalSince1970: 200)
  harness.send(.hookEventReceived(makeEvent(.busy, agent: .claude, surfaceID: a, pid: getpid())))
  harness.now = Date(timeIntervalSince1970: 300)
  harness.send(.hookEventReceived(makeEvent(.awaitingInput, agent: .codex, surfaceID: b, pid: getpid())))
  harness.now = Date(timeIntervalSince1970: 400)
  harness.send(.hookEventReceived(makeEvent(.awaitingInput, agent: .claude, surfaceID: a, pid: getpid())))
  let snapshot = harness.state.rowSnapshot(across: [a, b], badgesEnabled: true)
  // Both awaiting; the earliest attention stamp wins (codex at 300).
  #expect(snapshot.since == Date(timeIntervalSince1970: 300))
}

@Test func rowSnapshotSinceFallsBackToWorkingDate() {
  var harness = Harness(now: Date(timeIntervalSince1970: 100))
  let a = UUID()
  harness.send(.hookEventReceived(makeEvent(.sessionStart, agent: .claude, surfaceID: a, pid: getpid())))
  harness.now = Date(timeIntervalSince1970: 200)
  harness.send(.hookEventReceived(makeEvent(.busy, agent: .claude, surfaceID: a, pid: getpid())))
  #expect(harness.state.rowSnapshot(across: [a], badgesEnabled: true).since == Date(timeIntervalSince1970: 200))
}

@Test func lastEventAtIsStampedOnEveryEvent() {
  var harness = Harness(now: Date(timeIntervalSince1970: 100))
  let a = UUID()
  harness.send(.hookEventReceived(makeEvent(.sessionStart, agent: .codex, surfaceID: a, pid: getpid())))
  harness.now = Date(timeIntervalSince1970: 150)
  harness.send(.hookEventReceived(makeEvent(.busy, agent: .codex, surfaceID: a, pid: getpid())))
  harness.now = Date(timeIntervalSince1970: 175)
  harness.send(.hookEventReceived(makeEvent(.busy, agent: .codex, surfaceID: a, pid: getpid())))  // unchanged activity
  #expect(harness.state.lastEventAt[.codex] == Date(timeIntervalSince1970: 175))
  #expect(harness.state.lastEventAt[.claude] == nil)
}

@Test func restoreCarriesActivitySince() {
  let stamped = Date(timeIntervalSince1970: 500)
  var harness = Harness(now: Date(timeIntervalSince1970: 900))
  let surfaceID = UUID()
  harness.restoreFromLayouts([
    makeLayout(surfaces: [(id: surfaceID, agents: [
      .init(agent: "claude", pids: [getpid()], activity: "awaitingInput", activitySince: stamped)
    ])])
  ])
  let key = AgentPresenceFeature.PresenceKey(agent: .claude, surfaceID: surfaceID)
  #expect(harness.state.records[key]?.activitySince == stamped)
}

@Test func restoreWithoutActivitySinceFallsBackToNow() {
  let now = Date(timeIntervalSince1970: 900)
  var harness = Harness(now: now)
  let surfaceID = UUID()
  harness.restoreFromLayouts([
    makeLayout(surfaces: [(id: surfaceID, agents: [
      .init(agent: "claude", pids: [getpid()], activity: "busy", activitySince: nil)
    ])])
  ])
  let key = AgentPresenceFeature.PresenceKey(agent: .claude, surfaceID: surfaceID)
  #expect(harness.state.records[key]?.activitySince == now)
}

@Test func legacySurfaceAgentRecordDecodesWithoutActivitySince() throws {
  let json = #"{"agent":"claude","pids":[42],"activity":"busy"}"#
  let record = try JSONDecoder().decode(TerminalLayoutSnapshot.SurfaceAgentRecord.self, from: Data(json.utf8))
  #expect(record.activitySince == nil)
}
```

Update the private `Harness` so `now` is settable and injected:

```swift
private struct Harness {
  var state = AgentPresenceFeature.State()
  var now: Date
  private let reducer = AgentPresenceFeature()

  init(now: Date = Date(timeIntervalSince1970: 0)) { self.now = now }

  @MainActor mutating func send(_ action: AgentPresenceFeature.Action) {
    let now = self.now
    withDependencies { $0.date = .constant(now) } operation: {
      _ = reducer.reduce(into: &state, action: action)
    }
  }
  // livenessSweep() unchanged.

  @MainActor mutating func restoreFromLayouts(_ layouts: [TerminalLayoutSnapshot]) {
    let staged = AgentPresenceFeature.stageRestore(fromLayouts: layouts)
    let checked = staged.compactMapValues { stage -> AgentPresenceFeature.RestoredRecord? in
      let alive = stage.pids.filter { AgentPresenceFeature.isAlive($0) }
      guard !alive.isEmpty else { return nil }
      return AgentPresenceFeature.RestoredRecord(
        alivePids: alive, activity: stage.activity, activitySince: stage.activitySince ?? now)
    }
    guard !checked.isEmpty else { return }
    send(.restoreFromSnapshotChecked(records: checked))
  }
}
```

`makeLayout` already builds `SurfaceAgentRecord`s; the new memberwise field `activitySince` is appended to each `.init(...)` call in the file (existing calls pass `activitySince: nil`). `withDependencies` needs `import Dependencies` (already imported).

Also update `supacodeTests/AgentPresence+TestHelpers.swift` (`PresenceTestHarness`) the same way: give it a `now: Date` and wrap `reduce` in `withDependencies`.

- [ ] **Step 2: Run `AgentPresenceFeatureTests`; expect FAIL** to compile on `activitySince`, `since`, `lastEventAt`, `Harness(now:)`.

- [ ] **Step 3: Implement in `AgentPresenceFeature.swift`**

Model changes:

```swift
struct AgentInstance: Hashable, Sendable {
  let agent: SkillAgent
  let activity: Activity
  /// When `activity` began. Drives the elapsed-time label and the needs-you order.
  let since: Date
  var awaitingInput: Bool { activity == .awaitingInput }
}

struct RowSnapshot: Equatable, Sendable {
  var agents: [AgentInstance] = []
  var isWorking = false
  var hasError = false
  /// Earliest `since` among attention-state agents, else among working agents,
  /// else nil. The row shows elapsed time off this; the queue orders by it.
  var since: Date?
}

nonisolated struct PresenceRecord: Equatable, Sendable {
  var activity: Activity = .idle
  var pids: Set<pid_t>
  /// When `activity` last changed. Restamped by every transition, including
  /// `clearAttention` and a sticky-state reset on restart.
  var activitySince: Date
}

nonisolated struct RestoredRecord: Sendable {
  let alivePids: Set<pid_t>
  let activity: Activity
  let activitySince: Date
}

struct StagedRestore: Sendable {
  let pids: Set<pid_t>
  let activity: Activity
  /// nil when the snapshot predates the field; the restore uses `now`.
  let activitySince: Date?
}
```

State:

```swift
@ObservableState
struct State: Equatable {
  var records: [PresenceKey: PresenceRecord] = [:]
  var bySurface: [UUID: Set<SkillAgent>] = [:]
  /// Wall-clock of the last hook event per agent, stamped on every
  /// `hookEventReceived` whether or not activity changed. Not persisted; the
  /// settings health check reads it through `AgentHookActivityClient`.
  var lastEventAt: [SkillAgent: Date] = [:]
}
```

Reducer: add `@Dependency(\.date.now) var now` next to `clock` inside `Reduce`, and thread `now` through the mutators:

```swift
case .hookEventReceived(let event):
  if let agent = SkillAgent(rawValue: event.agent) { state.lastEventAt[agent] = now }
  let changed = Self.apply(event: event, now: now, into: &state)
  return Self.surfacesChangedEffect(changed)

case .clearAttention(let surfaces):
  let changed = Self.clearAttention(on: surfaces, now: now, into: &state)
  return Self.surfacesChangedEffect(changed)

case .restoreFromSnapshot(let staged):
  guard !staged.isEmpty else { return .none }
  let now = now
  return .run { send in
    let checked = staged.compactMapValues { stage -> RestoredRecord? in
      let alive = stage.pids.filter { Self.isAlive($0) }
      guard !alive.isEmpty else { return nil }
      return RestoredRecord(alivePids: alive, activity: stage.activity, activitySince: stage.activitySince ?? now)
    }
    guard !checked.isEmpty else { return }
    await send(.restoreFromSnapshotChecked(records: checked))
  }
```

Mutators: add a `now: Date` parameter to `apply`, `applySessionStart`, `applyActivity`, `clearAttention`, `applyRestore`, and pass it down. Stamp at every place `activity` is assigned or a record is created:

```swift
// applyActivity, existing-record branch:
record.activity = activity
record.activitySince = now
// applyActivity, seed branch:
state.records[key] = PresenceRecord(activity: activity, pids: [], activitySince: now)
// applySessionStart: every `PresenceRecord(pids: [])` becomes
PresenceRecord(pids: [], activitySince: now)
// normalizeStickyOnRestart gains `now:` and sets record.activitySince = now when it resets.
// clearAttention: updated.activity = .idle; updated.activitySince = now
// applyRestore: construct PresenceRecord(activity: r.activity, pids: r.alivePids, activitySince: r.activitySince)
```

`stageRestore(fromAgentRecords:)`: pass `activitySince: record.activitySince` into `StagedRestore`.

`agentsBySurface()`: add `activitySince: record.activitySince` to the `SurfaceAgentRecord` init.

`agents(across:badgesEnabled:)`: build `AgentInstance(agent:activity:since:)` reading `record?.activitySince ?? Date.distantPast` only when the record is missing (it cannot be, but keep the fallback explicit).

`rowSnapshot(across:badgesEnabled:)`: compute

```swift
var attentionSince: Date?
var workingSince: Date?
for (key, record) in records where surfaceSet.contains(key.surfaceID) {
  if record.activity.isWorking {
    isWorking = true
    workingSince = min(workingSince ?? record.activitySince, record.activitySince)
  }
  if record.activity == .error, badgesEnabled { hasError = true }
  if record.activity.isAttention {
    attentionSince = min(attentionSince ?? record.activitySince, record.activitySince)
  }
}
return RowSnapshot(agents: ..., isWorking: isWorking, hasError: hasError, since: attentionSince ?? workingSince)
```

`TerminalLayoutSnapshot.SurfaceAgentRecord`:

```swift
struct SurfaceAgentRecord: Codable, Equatable, Sendable {
  let agent: String
  let pids: [Int32]
  let activity: String
  /// Added 2026-10. Optional so snapshots written before it still decode.
  let activitySince: Date?

  init(agent: String, pids: [Int32], activity: String, activitySince: Date?) { ... }
}
```

Synthesized Codable already treats an optional `let` as `decodeIfPresent`; no custom decoder is needed. Confirm the layouts file uses `JSONDecoder` with a date strategy: grep `LayoutPersistence` for `dateDecodingStrategy`. If none is set, Date encodes as a double, which round-trips fine.

Fix every other call site the compiler flags (`AppFeature.swift` builds `AgentInstance` nowhere; `AgentAvatarGroupView.init(agents:)` constructs `.init(agent: $0, activity: .idle)` → add `since: .distantPast`).

- [ ] **Step 4: Run `AgentPresenceFeatureTests`, `AgentPresenceOSCTests`, `SidebarItemFeatureTests`, `SidebarStructureTests`; expect PASS.** Then `make build-app`.

- [ ] **Step 5: Commit**

```bash
git add supacode/Features/AgentPresence/Reducer/AgentPresenceFeature.swift supacode/Features/Terminal/Models/TerminalLayoutSnapshot.swift supacode/Features/AgentPresence/Views/AgentAvatarGroupView.swift supacodeTests/AgentPresenceFeatureTests.swift supacodeTests/AgentPresence+TestHelpers.swift
git commit -m "Agent presence: stamp activitySince on every transition and persist it"
```

### Task 4: Persist and restore the stamp end to end

**Files:**
- Modify: `supacode/Features/App/Reducer/AppFeature.swift` (`stageRestore` call ~line 434; `saveLayoutsWithAgents` ~449–465)
- Test: `supacodeTests/AgentPresenceFeatureTests.swift` (restore tests from Task 3 already cover the stage → apply path)

- [ ] **Step 1: Confirm compile.** `AppFeature` uses `stageRestore(from:)` and `agentsBySurface()`; both changed shape internally only. Run `make build-app`. Expected: builds.

- [ ] **Step 2: Round-trip test.** Append to `AgentPresenceFeatureTests`:

```swift
@Test func agentsBySurfaceRoundTripsActivitySince() {
  let t = Date(timeIntervalSince1970: 777)
  var harness = Harness(now: t)
  let a = UUID()
  harness.send(.hookEventReceived(makeEvent(.sessionStart, agent: .claude, surfaceID: a, pid: getpid())))
  let records = harness.state.agentsBySurface()[a]
  #expect(records?.first?.activitySince == t)
}
```

- [ ] **Step 3: Run `AgentPresenceFeatureTests`; expect PASS.**

- [ ] **Step 4: Commit**

```bash
git add supacodeTests/AgentPresenceFeatureTests.swift
git commit -m "Agent presence: cover activitySince snapshot round trip"
```

---

## W2. Elapsed time in the badge

### Task 5: Elapsed formatter and label view

**Files:**
- Create: `supacode/Features/AgentPresence/Views/ElapsedLabel.swift`
- Create: `supacodeTests/ElapsedFormatterTests.swift`

**Interfaces:**
- Produces: `enum ElapsedFormatter { static func compact(from: Date, to: Date) -> String; static func spoken(from: Date, to: Date) -> String }` and `struct ElapsedLabel: View`.

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import Testing

@testable import supacode

struct ElapsedFormatterTests {
  private let start = Date(timeIntervalSince1970: 0)

  @Test func compactSecondsMinutesHoursDays() {
    #expect(ElapsedFormatter.compact(from: start, to: start.addingTimeInterval(5)) == "5s")
    #expect(ElapsedFormatter.compact(from: start, to: start.addingTimeInterval(65)) == "1m")
    #expect(ElapsedFormatter.compact(from: start, to: start.addingTimeInterval(3_600 * 2 + 60)) == "2h")
    #expect(ElapsedFormatter.compact(from: start, to: start.addingTimeInterval(86_400 * 3)) == "3d")
  }

  @Test func compactClampsNegativeToZero() {
    #expect(ElapsedFormatter.compact(from: start.addingTimeInterval(10), to: start) == "0s")
  }

  @Test func spokenIsMinutesAndSecondsUnderAnHour() {
    #expect(ElapsedFormatter.spoken(from: start, to: start.addingTimeInterval(252)) == "4m 12s")
    #expect(ElapsedFormatter.spoken(from: start, to: start.addingTimeInterval(3_660)) == "1h 1m")
  }
}
```

- [ ] **Step 2: Run `ElapsedFormatterTests`; expect FAIL** (type not found).

- [ ] **Step 3: Implement**

```swift
// supacode/Features/AgentPresence/Views/ElapsedLabel.swift
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
```

`appFont` is the project's Dynamic-Type font helper (used in `DeveloperSettingsView`). If `.caption` is not a supported case there, use `.subheadline`.

- [ ] **Step 4: Run `ElapsedFormatterTests`; expect PASS.** `make build-app`.

- [ ] **Step 5: Commit**

```bash
git add supacode/Features/AgentPresence/Views/ElapsedLabel.swift supacodeTests/ElapsedFormatterTests.swift
git commit -m "Add ElapsedFormatter and ElapsedLabel for agent wait times"
```

### Task 6: Show elapsed time on the badge and sidebar row

**Files:**
- Modify: `supacode/Features/AgentPresence/Views/AgentBadgeView.swift`
- Modify: `supacode/Features/AgentPresence/Views/AgentAvatarGroupView.swift`
- Modify: `supacode/Features/Repositories/Views/SidebarItemView.swift` (`RunningAgentsBadgeContent`, ~line 601)
- Test: `supacodeTests/AgentBadgeVisualTests.swift`

- [ ] **Step 1: Write the failing test** (append to `AgentBadgeVisualTests`)

```swift
@Test func describingIncludesElapsedForAttentionStates() {
  let since = Date(timeIntervalSince1970: 0)
  let now = since.addingTimeInterval(252)
  #expect(AgentBadgeVisual.awaitingInput.describing(.claude, since: since, now: now) == "Claude awaiting input for 4m 12s")
  #expect(AgentBadgeVisual.error.describing(.codex, since: since, now: now) == "Codex stopped on an error 4m 12s ago")
  #expect(AgentBadgeVisual.normal.describing(.claude, since: since, now: now) == "Claude")
}
```

- [ ] **Step 2: Run `AgentBadgeVisualTests`; expect FAIL** (no such overload).

- [ ] **Step 3: Implement**

In `AgentBadgeVisual`:

```swift
func describing(_ agent: SkillAgent, since: Date?, now: Date) -> String {
  guard let since else { return describing(agent) }
  let elapsed = ElapsedFormatter.spoken(from: since, to: now)
  switch self {
  case .awaitingInput: return "\(agent.displayName) awaiting input for \(elapsed)"
  case .error: return "\(agent.displayName) stopped on an error \(elapsed) ago"
  case .compacting, .normal: return describing(agent)
  }
}
```

In `AgentBadgeView` add `let since: Date?` (default `nil` in `init`) and replace the `.help(visual.describing(agent))` with a timeline-driven help only for attention states:

```swift
.modifier(ElapsedHelp(visual: visual, agent: agent, since: visual == .awaitingInput || visual == .error ? since : nil))

private struct ElapsedHelp: ViewModifier {
  let visual: AgentBadgeVisual
  let agent: SkillAgent
  let since: Date?
  func body(content: Content) -> some View {
    if let since {
      TimelineView(.periodic(from: since, by: 1)) { context in
        content.help(visual.describing(agent, since: since, now: context.date))
      }
    } else {
      content.help(visual.describing(agent))
    }
  }
}
```

In `AgentAvatarGroupView`: `Slot` gains `let since: Date`, built from `instance.since`; pass `since: slot.since` to `AgentBadgeView`.

In `SidebarItemView.RunningAgentsBadgeContent`: after the avatar group, when the row's snapshot has an attention-state agent and `since` is non-nil, append `ElapsedLabel(since:)`. The content struct already receives `instances`; add `let since: Date?` and `let showsElapsed: Bool` (true when `instances.contains { $0.activity.isAttention }`), and feed them from the row's `agentSnapshot` where `RunningAgentsBadgeContent` is constructed (~line 549). Keep the `Equatable` conformance by including both new fields.

- [ ] **Step 4: Run `AgentBadgeVisualTests`; expect PASS.** `make build-app`. Launch the app, start `claude` in a worktree, run `/permissions`-style prompt or any tool needing approval; confirm the row shows `Ns` next to the badge and the tooltip reads "Claude awaiting input for …".

- [ ] **Step 5: Commit**

```bash
git add supacode/Features/AgentPresence/Views/AgentBadgeView.swift supacode/Features/AgentPresence/Views/AgentAvatarGroupView.swift supacode/Features/Repositories/Views/SidebarItemView.swift supacodeTests/AgentBadgeVisualTests.swift
git commit -m "Show elapsed wait time on attention-state agent badges"
```

---

## W3. Needs-you queue

### Task 7: Order Active rows and the menu bar by wait time

**Files:**
- Modify: `supacode/Features/Repositories/BusinessLogic/SidebarStructure.swift` (`SidebarHighlightOrdering`, ~line 96; candidate construction ~1125)
- Modify: `supacode/Features/App/Models/MenuBarNotificationList.swift`
- Test: `supacodeTests/SidebarHighlightOrderingTests.swift`, `supacodeTests/MenuBarNotificationListTests.swift`

**Interfaces:**
- Produces: `SidebarHighlightOrdering.Candidate.attentionSince: Date?`; `MenuBarSections.needsYou: [Worktree.ID]`; `RepositoriesFeature.State.needsYouRowIDs() -> [Worktree.ID]`.

- [ ] **Step 1: Write the failing tests**

Append to `SidebarHighlightOrderingTests`:

```swift
@Test func attentionRowsLeadOrderedByLongestWait() {
  let old = Date(timeIntervalSince1970: 100)
  let new = Date(timeIntervalSince1970: 900)
  let candidates = [
    SidebarHighlightOrdering.Candidate(id: "a", branchName: "a", isNotified: false, classification: .agent, attentionSince: nil),
    SidebarHighlightOrdering.Candidate(id: "b", branchName: "b", isNotified: false, classification: .awaitingInput, attentionSince: new),
    SidebarHighlightOrdering.Candidate(id: "c", branchName: "c", isNotified: false, classification: .awaitingInput, attentionSince: old),
  ]
  let ordered = SidebarHighlightOrdering.orderedRowIDs(forPinned: false, prioritizeNotified: false, candidates: candidates)
  #expect(ordered == ["c", "b", "a"])
}

@Test func notifiedStillBeatsAttentionWhenPrioritized() {
  let t = Date(timeIntervalSince1970: 100)
  let candidates = [
    SidebarHighlightOrdering.Candidate(id: "a", branchName: "a", isNotified: true, classification: .agent, attentionSince: nil),
    SidebarHighlightOrdering.Candidate(id: "b", branchName: "b", isNotified: false, classification: .awaitingInput, attentionSince: t),
  ]
  let ordered = SidebarHighlightOrdering.orderedRowIDs(forPinned: false, prioritizeNotified: true, candidates: candidates)
  #expect(ordered == ["a", "b"])
}
```

Use the classification case names that exist in `SidebarActiveClassification` (read the enum at the top of `SidebarStructure.swift`; the awaiting case may be spelled `.awaiting`). `SidebarItemID` is `Worktree.ID`, a string-backed tagged type; if a string literal does not convert, construct with `Worktree.ID(rawValue:)` the way other tests in the file do.

Append to `MenuBarNotificationListTests` (follow that file's state-builder helpers for two worktrees in one repo):

```swift
@Test func needsYouListsAttentionRowsLongestWaitFirst() {
  var state = makeTwoWorktreeState()  // helper already in file; else build RepositoriesFeature.State with two rows
  state.sidebarItems[id: "wt-a"]?.agentSnapshot = .init(
    agents: [.init(agent: .claude, activity: .awaitingInput, since: Date(timeIntervalSince1970: 900))],
    isWorking: false, hasError: false, since: Date(timeIntervalSince1970: 900))
  state.sidebarItems[id: "wt-b"]?.agentSnapshot = .init(
    agents: [.init(agent: .codex, activity: .error, since: Date(timeIntervalSince1970: 100))],
    isWorking: false, hasError: true, since: Date(timeIntervalSince1970: 100))
  let sections = state.computeMenuBarSections()
  #expect(sections.needsYou == ["wt-b", "wt-a"])
  #expect(sections.entries.first?.content == .header("Needs You", .active))
}

@Test func needsYouExcludesArchivedAndIdleRows() {
  var state = makeTwoWorktreeState()
  state.sidebarItems[id: "wt-a"]?.agentSnapshot = .init(
    agents: [.init(agent: .claude, activity: .busy, since: .distantPast)], isWorking: true, hasError: false, since: .distantPast)
  // archive wt-b via state.sidebar.archive(...) helper used elsewhere in this file
  let sections = state.computeMenuBarSections()
  #expect(sections.needsYou.isEmpty)
}
```

- [ ] **Step 2: Run both suites; expect FAIL** to compile.

- [ ] **Step 3: Implement**

`SidebarHighlightOrdering.Candidate` gains `let attentionSince: Date?`. Ordering:

```swift
.sorted { lhs, rhs in
  if prioritizeNotified, lhs.isNotified != rhs.isNotified { return lhs.isNotified }
  switch (lhs.attentionSince, rhs.attentionSince) {
  case let (l?, r?) where l != r: return l < r
  case (.some, .none): return true
  case (.none, .some): return false
  default: return branchNameOrdersBefore(lhs.branchName, id: lhs.id, rhs.branchName, id: rhs.id)
  }
}
```

Where candidates are built (~line 1125) pass `attentionSince: state.agentSnapshot.agents.contains(where: { $0.activity.isAttention }) ? state.agentSnapshot.since : nil`.

`RepositoriesFeature.State` (in `SidebarStructure.swift`, near `menuBarForcedHoists`):

```swift
/// Rows with an agent parked on the user, longest wait first. Archived,
/// missing and terminating rows are excluded. Feeds the menu bar's Needs You
/// section and `jumpToNextAwaiting`.
func needsYouRowIDs() -> [Worktree.ID] {
  let archived = archivedWorktreeIDSet
  return sidebarItems
    .filter { row in
      !archived.contains(row.id) && !row.isMissing && !row.lifecycle.isTerminating
        && row.agentSnapshot.agents.contains(where: { $0.activity.isAttention })
    }
    .sorted { lhs, rhs in
      let l = lhs.agentSnapshot.since ?? .distantFuture
      let r = rhs.agentSnapshot.since ?? .distantFuture
      if l != r { return l < r }
      return SidebarHighlightOrdering.branchNameOrdersBefore(lhs.branchName, id: lhs.id, rhs.branchName, id: rhs.id)
    }
    .map(\.id)
}
```

`MenuBarSections`: add `var needsYou: [Worktree.ID] = []`, include it in `isEmpty`, and render it first in `entries` via `appendSection(&entries, title: "Needs You", rowIDs: needsYou, dotColor: .active)`. In `computeMenuBarSections()` set `sections.needsYou = needsYouRowIDs()`, and dedupe `active` and `unread` against it (`.filter { !needsYouSet.contains($0) }`), and include needs-you rows in the repo-tag loop.

- [ ] **Step 4: Run `SidebarHighlightOrderingTests`, `MenuBarNotificationListTests`, `SidebarStructureTests`, `SidebarActiveClassificationTests`; expect PASS.** `make build-app`.

- [ ] **Step 5: Commit**

```bash
git add supacode/Features/Repositories/BusinessLogic/SidebarStructure.swift supacode/Features/App/Models/MenuBarNotificationList.swift supacodeTests/SidebarHighlightOrderingTests.swift supacodeTests/MenuBarNotificationListTests.swift
git commit -m "Order attention rows by wait time and add a Needs You menu bar section"
```

### Task 8: Jump to Next Awaiting Agent command

**Files:**
- Modify: `SupacodeSettingsShared/App/AppShortcuts.swift` (enum case, codingKey, lookup table, title, static shortcut, the `allCases`-style list at ~675)
- Modify: `supacode/Features/App/Reducer/AppFeature.swift` (action + handler next to `jumpToLatestUnread`)
- Modify: `supacode/Commands/WorktreeCommands.swift`
- Modify: `supacode/Features/App/Views/MenuBarNotificationsMenu.swift` (optional action row)
- Create: `supacodeTests/AppFeatureJumpToNextAwaitingTests.swift`

**Interfaces:**
- Produces: `AppFeature.Action.jumpToNextAwaiting`; `AppShortcutID.jumpToNextAwaiting`; `AppShortcut.jumpToNextAwaiting` (`⌃⇧J`, no existing binding uses key "j").

- [ ] **Step 1: Write the failing test** (copy the store builder from `AppFeatureJumpToLatestUnreadTests.swift` verbatim into the new file)

```swift
@MainActor
struct AppFeatureJumpToNextAwaitingTests {
  @Test(.dependencies) func noOpWhenNothingAwaits() async {
    let worktree = makeWorktree()
    let focused = LockIsolated<[TerminalClient.Command]>([])
    let store = makeStore(worktree: worktree) {
      $0.terminalClient.send = { command in focused.withValue { $0.append(command) } }
    }
    await store.send(.jumpToNextAwaiting)
    await store.finish()
    #expect(focused.value.isEmpty)
  }

  @Test(.dependencies) func selectsLongestWaitingWorktreeAndFocusesItsSurface() async {
    let worktree = makeWorktree()
    let surfaceUUID = UUID()
    let focused = LockIsolated<[TerminalClient.Command]>([])
    let store = makeStore(worktree: worktree) {
      $0.terminalClient.send = { command in focused.withValue { $0.append(command) } }
      $0.terminalClient.surfaceLocation = { _, _ in nil }  // see Step 3: may be unnecessary
    }
    store.exhaustivity = .off
    // Seed the row as awaiting with a surface.
    await store.send(.repositories(.sidebarItems(.element(id: worktree.id, action: .terminalProjectionChanged(
      .init(surfaceIDs: [surfaceUUID], isProgressBusy: false, hasUnseenNotifications: false, allTabsDormant: false)))))) {
      $0.repositories.sidebarItems[id: worktree.id]?.surfaceIDs = [surfaceUUID]
      $0.repositories.sidebarItems[id: worktree.id]?.hasTerminalProjection = true
    }
    await store.send(.repositories(.sidebarItems(.element(id: worktree.id, action: .agentSnapshotChanged(
      .init(agents: [.init(agent: .claude, activity: .awaitingInput, since: .distantPast)],
            isWorking: false, hasError: false, since: .distantPast))))))
    await store.send(.jumpToNextAwaiting)
    await store.receive(\.repositories.selectWorktree)
    await store.finish()
    #expect(focused.value.contains { if case .focusSurface = $0 { true } else { false } })
  }
}
```

Check the exact `TerminalProjection` initializer name/fields in `SidebarItemFeature.swift` and adjust. If `agentSnapshotChanged` is delivered only via the fan-out, sending it directly to the element is still valid in a `TestStore` with exhaustivity off.

- [ ] **Step 2: Run the new suite; expect FAIL** to compile on `.jumpToNextAwaiting`.

- [ ] **Step 3: Implement**

`AppShortcuts.swift`: add `case jumpToNextAwaiting` next to `jumpToLatestUnread` in every switch/table in the file (codingKey `"jumpToNextAwaiting"`, title `"Jump to Next Awaiting Agent"`), and

```swift
public static let jumpToNextAwaiting = AppShortcut(
  id: .jumpToNextAwaiting, key: "j", modifiers: [.control, .shift]
)
```

Add it to the ordered list at ~line 675 right after `jumpToLatestUnread`.

`AppFeature.swift`:

```swift
case jumpToNextAwaiting
...
case .jumpToNextAwaiting:
  guard let worktreeID = state.repositories.needsYouRowIDs().first,
    let worktree = state.repositories.worktree(for: worktreeID),
    let row = state.repositories.sidebarItems[id: worktreeID]
  else {
    jumpLogger.debug("jumpToNextAwaiting invoked with no awaiting agents.")
    return .run { _ in NSSound.beep() }
  }
  // The surface whose agent waited longest. Presence is keyed per surface, so
  // ask the presence state rather than the row snapshot.
  let surfaceID = state.agentPresence.records
    .filter { row.surfaceIDs.contains($0.key.surfaceID) && $0.value.activity.isAttention }
    .min { $0.value.activitySince < $1.value.activitySince }?
    .key.surfaceID
  analyticsClient.capture("agents_jump_to_next_awaiting", nil)
  return .merge(
    .send(.repositories(.selectWorktree(worktreeID, focusTerminal: surfaceID == nil))),
    .run { _ in
      guard let surfaceID else { return }
      await terminalClient.send(.focusSurfaceByID(worktree, surfaceID: surfaceID))
    }
  )
```

`focusSurface` needs a `tabID`; check `TerminalClient.Command` for a variant that focuses by surface id alone (grep `case focusSurface`). If only `focusSurface(_:tabID:surfaceID:input:)` exists, look up the tab via `terminalClient.tabID(forSurface:)` or the `WorktreeTerminalManager` reverse index used by `latestUnreadNotification`; if neither exists, add `var surfaceLocation: @Sendable (Worktree.ID, UUID) -> NotificationLocation?`-style closure to `TerminalClient` backed by the manager's existing surface index, and use it here. Focusing the surface triggers the existing `clearAttention` path, which pops the row off the queue.

Verify `state.agentPresence` is the child state name in `AppFeature.State` (grep `AgentPresenceFeature.State`).

`WorktreeCommands.swift`: after the Jump to Latest Unread button:

```swift
Button("Jump to Next Awaiting Agent", systemImage: "person.crop.circle.badge.exclamationmark") {
  store.send(.jumpToNextAwaiting)
}
.appKeyboardShortcut(jumpToNextAwaiting)
.help("Jump to the agent that has waited longest for input (\(jumpToNextAwaiting?.display ?? "none"))")
.disabled(snapshot.needsYouCount == 0)
```

Add `needsYouCount: Int` to the command snapshot struct this file reads (grep its definition; it is built from `RepositoriesFeature.State`), set from `needsYouRowIDs().count` where `notificationIndicatorCount` is set. Add the shortcut lookup `let jumpToNextAwaiting = shortcuts[.jumpToNextAwaiting]` beside `jumpToLatestUnread`.

Command palette: grep `"Jump to Latest Unread"` in `AppFeature.swift` (~1805) and add a sibling entry sending `.jumpToNextAwaiting`.

`MenuBarNotificationsMenu.swift`: add `MenuBarActionRow(title: "Jump to Next Awaiting Agent", isEnabled: !sections.needsYou.isEmpty) { dismissMenuBarExtra(); showMainWindow(); store.send(.jumpToNextAwaiting) }` above "Mark … as Read".

- [ ] **Step 4: Run `AppFeatureJumpToNextAwaitingTests`, `AppFeatureJumpToLatestUnreadTests`, and `KeyboardShortcuts`-related suites (grep `AppShortcut` in `supacodeTests` for suite names); expect PASS.** `make build-app`.

- [ ] **Step 5: Commit**

```bash
git add SupacodeSettingsShared/App/AppShortcuts.swift supacode/Features/App/Reducer/AppFeature.swift supacode/Commands/WorktreeCommands.swift supacode/Features/App/Views/MenuBarNotificationsMenu.swift supacodeTests/AppFeatureJumpToNextAwaitingTests.swift
git commit -m "Add Jump to Next Awaiting Agent command and shortcut"
```

---

## W5. Branch sync

### Task 9: Git client ahead/behind, rebase and merge

**Files:**
- Modify: `supacode/Clients/Git/GitClient.swift` (`GitOperation` enum; new methods after `lineChanges`)
- Modify: `supacode/Clients/Repositories/GitClientDependency.swift`
- Create: `supacode/Features/Repositories/Models/WorktreeSyncState.swift`
- Create: `supacodeTests/GitClientAheadBehindTests.swift`

**Interfaces:**
- Produces:
  ```swift
  struct GitAheadBehind: Equatable, Sendable { let ahead: Int; let behind: Int }
  enum GitSyncError: Error, Equatable { case conflict(operation: GitSyncOperation); case failed(String) }
  enum GitSyncOperation: String, Sendable { case rebase, merge }
  // GitClient
  func aheadBehind(at worktreeURL: URL, base: String) async -> GitAheadBehind?
  func rebase(at worktreeURL: URL, onto base: String) async throws
  func mergeBase(at worktreeURL: URL, base: String) async throws
  // GitClientDependency
  var aheadBehind: @Sendable (URL, String) async -> GitAheadBehind?
  var rebaseOnto: @Sendable (URL, String) async throws -> Void
  var mergeBaseRef: @Sendable (URL, String) async throws -> Void
  ```

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing

@testable import SupacodeSettingsShared
@testable import supacode

actor AheadBehindShellCallStore {
  private(set) var calls: [[String]] = []
  func record(_ arguments: [String]) { calls.append(arguments) }
}

struct GitClientAheadBehindTests {
  private func client(
    store: AheadBehindShellCallStore,
    respond: @escaping @Sendable ([String]) -> ShellOutput
  ) -> GitClient {
    GitClient(shell: ShellClient(
      run: { _, arguments, _ in
        await store.record(arguments)
        return respond(arguments)
      },
      runLoginImpl: { _, _, _, _ in ShellOutput(stdout: "", stderr: "", exitCode: 0) }
    ))
  }

  @Test func aheadBehindUsesLeftRightCountAndParses() async {
    let store = AheadBehindShellCallStore()
    let client = client(store: store) { _ in ShellOutput(stdout: "3\t5\n", stderr: "", exitCode: 0) }
    let result = await client.aheadBehind(at: URL(fileURLWithPath: "/tmp/wt"), base: "origin/main")
    #expect(result == GitAheadBehind(ahead: 3, behind: 5))
    let args = await store.calls.first ?? []
    #expect(args.contains("rev-list"))
    #expect(args.contains("--left-right"))
    #expect(args.contains("--count"))
    #expect(args.contains("HEAD...origin/main"))
  }

  @Test func aheadBehindReturnsNilOnFailure() async {
    let store = AheadBehindShellCallStore()
    let client = client(store: store) { _ in ShellOutput(stdout: "", stderr: "fatal: bad revision", exitCode: 128) }
    let result = await client.aheadBehind(at: URL(fileURLWithPath: "/tmp/wt"), base: "origin/main")
    #expect(result == nil)
  }

  @Test func rebaseConflictAbortsAndThrows() async {
    let store = AheadBehindShellCallStore()
    let client = client(store: store) { args in
      if args.contains("rebase") && !args.contains("--abort") {
        return ShellOutput(stdout: "", stderr: "CONFLICT (content): Merge conflict in a.txt", exitCode: 1)
      }
      return ShellOutput(stdout: "", stderr: "", exitCode: 0)
    }
    await #expect(throws: GitSyncError.conflict(operation: .rebase)) {
      try await client.rebase(at: URL(fileURLWithPath: "/tmp/wt"), onto: "origin/main")
    }
    let calls = await store.calls
    #expect(calls.contains { $0.contains("rebase") && $0.contains("--abort") })
  }

  @Test func mergeConflictAbortsAndThrows() async {
    let store = AheadBehindShellCallStore()
    let client = client(store: store) { args in
      if args.contains("merge") && !args.contains("--abort") {
        return ShellOutput(stdout: "", stderr: "CONFLICT (content): Merge conflict in a.txt", exitCode: 1)
      }
      return ShellOutput(stdout: "", stderr: "", exitCode: 0)
    }
    await #expect(throws: GitSyncError.conflict(operation: .merge)) {
      try await client.mergeBase(at: URL(fileURLWithPath: "/tmp/wt"), base: "origin/main")
    }
    let calls = await store.calls
    #expect(calls.contains { $0.contains("merge") && $0.contains("--abort") })
  }

  @Test func rebaseSuccessDoesNotAbort() async throws {
    let store = AheadBehindShellCallStore()
    let client = client(store: store) { _ in ShellOutput(stdout: "", stderr: "", exitCode: 0) }
    try await client.rebase(at: URL(fileURLWithPath: "/tmp/wt"), onto: "origin/main")
    let calls = await store.calls
    #expect(!calls.contains { $0.contains("--abort") })
  }
}
```

Check how `ShellClient.run` reports a non-zero exit: if it throws instead of returning `exitCode != 0`, make the stubs `throw` a `ShellError` the way `GitClientLineChangesTests` siblings do (grep `exitCode:` in `supacodeTests/GitClient*Tests.swift`).

- [ ] **Step 2: Run `GitClientAheadBehindTests`; expect FAIL** to compile.

- [ ] **Step 3: Implement**

`WorktreeSyncState.swift`:

```swift
import Foundation

nonisolated struct GitAheadBehind: Equatable, Sendable {
  let ahead: Int
  let behind: Int
}

nonisolated enum GitSyncOperation: String, Sendable, Equatable {
  case rebase
  case merge

  var verb: String { self == .rebase ? "Rebase" : "Merge" }
}

nonisolated enum GitSyncError: Error, Equatable {
  /// The operation stopped on conflicts. The client already ran `--abort`, so
  /// the worktree is exactly as it was.
  case conflict(operation: GitSyncOperation)
  case failed(String)
}
```

`GitClient.swift`: add `GitOperation` cases `aheadBehind = "ahead_behind"`, `rebase = "rebase"`, `mergeRef = "merge_ref"`, `syncAbort = "sync_abort"`. Methods after `lineChanges`:

```swift
/// `HEAD...base` left/right count: left is commits only on HEAD (ahead),
/// right is commits only on base (behind). `nil` on any failure (unknown
/// base, locked index) so the caller keeps its last value.
nonisolated func aheadBehind(at worktreeURL: URL, base: String) async -> GitAheadBehind? {
  let path = worktreeURL.path(percentEncoded: false)
  guard
    let output = try? await runGit(
      operation: .aheadBehind,
      arguments: ["-C", path, "rev-list", "--left-right", "--count", "HEAD...\(base)"])
  else { return nil }
  let parts = output.split(whereSeparator: { $0 == "\t" || $0 == " " }).map { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
  guard parts.count == 2, let ahead = parts[0], let behind = parts[1] else { return nil }
  return GitAheadBehind(ahead: ahead, behind: behind)
}

/// `git rebase <base>`; on failure runs `--abort` and throws `.conflict` so
/// the worktree is never left mid-rebase.
nonisolated func rebase(at worktreeURL: URL, onto base: String) async throws {
  try await runSync(.rebase, worktreeURL: worktreeURL, arguments: ["rebase", base], abortArguments: ["rebase", "--abort"])
}

/// `git merge --no-edit <base>`; on failure runs `--abort` and throws `.conflict`.
nonisolated func mergeBase(at worktreeURL: URL, base: String) async throws {
  try await runSync(.merge, worktreeURL: worktreeURL, arguments: ["merge", "--no-edit", base], abortArguments: ["merge", "--abort"])
}

nonisolated private func runSync(
  _ operation: GitSyncOperation, worktreeURL: URL, arguments: [String], abortArguments: [String]
) async throws {
  let path = worktreeURL.path(percentEncoded: false)
  do {
    _ = try await runGit(
      operation: operation == .rebase ? .rebase : .mergeRef,
      arguments: ["-C", path] + arguments,
      localePinned: true)
  } catch {
    _ = try? await runGit(operation: .syncAbort, arguments: ["-C", path] + abortArguments, localePinned: true)
    let message = error.localizedDescription
    if message.localizedCaseInsensitiveContains("conflict") {
      throw GitSyncError.conflict(operation: operation)
    }
    throw GitSyncError.failed(message)
  }
}
```

If `runGit` only throws on exit != 0 via `wrapShellError`, the `catch` above is correct. If `runGit` returns on non-zero exit, inspect `ShellOutput.exitCode` and branch the same way. Check `wrapShellError` includes stderr in the error's description (the conflict text must survive); if not, match on the error's `stderr` property instead.

`GitClientDependency.swift`: add the three closures to the struct, to `make(shell:)`:

```swift
aheadBehind: { url, base in await GitClient(shell: shell).aheadBehind(at: url, base: base) },
rebaseOnto: { url, base in try await GitClient(shell: shell).rebase(at: url, onto: base) },
mergeBaseRef: { url, base in try await GitClient(shell: shell).mergeBase(at: url, base: base) },
```

and to `testValue`: `value.aheadBehind = { _, _ in nil }` so unstubbed reducer tests never shell out.

- [ ] **Step 4: Run `GitClientAheadBehindTests` and `GitClientLineChangesTests`; expect PASS.** `make build-app`.

- [ ] **Step 5: Commit**

```bash
git add supacode/Clients/Git/GitClient.swift supacode/Clients/Repositories/GitClientDependency.swift supacode/Features/Repositories/Models/WorktreeSyncState.swift supacodeTests/GitClientAheadBehindTests.swift
git commit -m "Git client: ahead/behind count, guarded rebase and merge"
```

### Task 10: Behind-count refresh, row accessory, and sync actions

**Files:**
- Modify: `supacode/Features/Repositories/Reducer/SidebarItemFeature.swift` (State fields + action)
- Modify: `supacode/Features/Repositories/Reducer/RepositoriesFeature.swift` (`.worktreeInfoEvent` ~3506; new actions)
- Modify: `supacode/Features/Repositories/Views/SidebarItemView.swift` (accessory next to `DiffStatsContent`)
- Modify: `supacode/Features/Repositories/Views/SidebarItemsView.swift` (context menu ~line 650)
- Test: `supacodeTests/RepositoriesFeatureTests.swift` (new section at end), `supacodeTests/SidebarItemFeatureTests.swift`

**Interfaces:**
- Produces:
  - `SidebarItemFeature.State.aheadCount: Int?`, `behindCount: Int?`, `syncBaseRef: String?`, `isSyncing: Bool`
  - `SidebarItemFeature.Action.aheadBehindChanged(ahead: Int?, behind: Int?, base: String?)`, `.syncStateChanged(Bool)`
  - `RepositoriesFeature.Action.refreshAheadBehind(worktreeID:)`, `.worktreeAheadBehindLoaded(worktreeID:, result: GitAheadBehind?, base: String)`, `.syncWorktreeWithBase(worktreeID:, operation: GitSyncOperation)`, `.syncWorktreeFinished(worktreeID:, result: Result<Void, GitSyncError>)`
  - `RepositoriesFeature.State.canSync(worktreeID:) -> Bool`

- [ ] **Step 1: Write the failing tests** (append to `RepositoriesFeatureTests` using its `makeStore`/fixture helpers; `exhaustivity = .off`)

```swift
// MARK: - Branch sync.

@Test func branchChangedRefreshesAheadBehind() async {
  let worktree = makeWorktree(id: "/tmp/wt")
  let store = makeStore(worktrees: [worktree]) {
    $0.gitClient.branchName = { _ in "feature" }
    $0.gitClient.automaticWorktreeBaseRef = { _ in "origin/main" }
    $0.gitClient.aheadBehind = { _, _ in GitAheadBehind(ahead: 2, behind: 7) }
  }
  store.exhaustivity = .off
  await store.send(.worktreeInfoEvent(.branchChanged(worktreeID: worktree.id)))
  await store.receive(\.worktreeAheadBehindLoaded)
  await store.finish()
  #expect(store.state.sidebarItems[id: worktree.id]?.behindCount == 7)
  #expect(store.state.sidebarItems[id: worktree.id]?.aheadCount == 2)
  #expect(store.state.sidebarItems[id: worktree.id]?.syncBaseRef == "origin/main")
}

@Test func syncIsBlockedWhileAgentWorksOrTreeDirty() async {
  let worktree = makeWorktree(id: "/tmp/wt")
  let store = makeStore(worktrees: [worktree]) { _ in }
  store.exhaustivity = .off
  await store.send(.sidebarItems(.element(id: worktree.id, action: .aheadBehindChanged(ahead: 0, behind: 3, base: "origin/main"))))
  #expect(store.state.canSync(worktreeID: worktree.id))
  await store.send(.sidebarItems(.element(id: worktree.id, action: .agentSnapshotChanged(
    .init(agents: [.init(agent: .claude, activity: .busy, since: .distantPast)], isWorking: true, hasError: false, since: .distantPast)))))
  #expect(!store.state.canSync(worktreeID: worktree.id))
}

@Test func syncConflictShowsAlertAndKeepsCounts() async {
  let worktree = makeWorktree(id: "/tmp/wt")
  let store = makeStore(worktrees: [worktree]) {
    $0.gitClient.fileStatus = { _ in GitStatusSnapshot(entries: []) }  // clean
    $0.gitClient.rebaseOnto = { _, _ in throw GitSyncError.conflict(operation: .rebase) }
  }
  store.exhaustivity = .off
  await store.send(.sidebarItems(.element(id: worktree.id, action: .aheadBehindChanged(ahead: 1, behind: 3, base: "origin/main"))))
  await store.send(.syncWorktreeWithBase(worktreeID: worktree.id, operation: .rebase))
  await store.receive(\.syncWorktreeFinished)
  await store.finish()
  #expect(store.state.sidebarItems[id: worktree.id]?.behindCount == 3)
  #expect(store.state.sidebarItems[id: worktree.id]?.isSyncing == false)
  #expect(store.state.alert != nil)
}

@Test func syncSuccessRefreshesCounts() async {
  let worktree = makeWorktree(id: "/tmp/wt")
  let store = makeStore(worktrees: [worktree]) {
    $0.gitClient.fileStatus = { _ in GitStatusSnapshot(entries: []) }
    $0.gitClient.rebaseOnto = { _, _ in }
    $0.gitClient.automaticWorktreeBaseRef = { _ in "origin/main" }
    $0.gitClient.aheadBehind = { _, _ in GitAheadBehind(ahead: 1, behind: 0) }
    $0.gitClient.lineChanges = { _ in (added: 0, removed: 0) }
  }
  store.exhaustivity = .off
  await store.send(.sidebarItems(.element(id: worktree.id, action: .aheadBehindChanged(ahead: 1, behind: 3, base: "origin/main"))))
  await store.send(.syncWorktreeWithBase(worktreeID: worktree.id, operation: .rebase))
  await store.receive(\.syncWorktreeFinished)
  await store.receive(\.worktreeAheadBehindLoaded)
  await store.finish()
  #expect(store.state.sidebarItems[id: worktree.id]?.behindCount == nil)
}
```

Use the exact `GitStatusSnapshot` empty initializer the codebase provides (grep `GitStatusSnapshot(` in tests). `alert` is whatever the feature's `@Presents var alert` is named (grep `@Presents` in `RepositoriesFeature.swift`).

- [ ] **Step 2: Run `RepositoriesFeatureTests`; expect FAIL** to compile.

- [ ] **Step 3: Implement**

`SidebarItemFeature.State`:

```swift
/// Commits HEAD is ahead of / behind the repo's base ref. `nil` until the
/// first probe, and `behindCount` is `nil` (not 0) when in sync so the
/// accessory renders nothing.
var aheadCount: Int?
var behindCount: Int?
/// The base ref the counts were measured against, for the tooltip and menu.
var syncBaseRef: String?
/// A rebase / merge is in flight; the row menu disables sync meanwhile.
var isSyncing = false
```

Actions and reducer cases:

```swift
case aheadBehindChanged(ahead: Int?, behind: Int?, base: String?)
case syncStateChanged(Bool)
...
case .aheadBehindChanged(let ahead, let behind, let base):
  let nextBehind: Int? = (behind ?? 0) == 0 ? nil : behind
  guard state.aheadCount != ahead || state.behindCount != nextBehind || state.syncBaseRef != base else { return .none }
  state.aheadCount = ahead
  state.behindCount = nextBehind
  state.syncBaseRef = base
  return .none
case .syncStateChanged(let flag):
  guard state.isSyncing != flag else { return .none }
  state.isSyncing = flag
  return .none
```

`RepositoriesFeature`:

Resolve the base ref per worktree with a helper on `State`:

```swift
/// Repo override first, else the automatic base. Called inside an effect
/// because the automatic path shells out.
func syncBaseRefResolver(for worktree: Worktree) -> (@Sendable () async -> String?) {
  @Shared(.settingsFile) var settingsFile
  let override = settingsFile.repositories[repositoryID(containing: worktree.id) ?? ""]?.worktreeBaseRef
  let gitClient = gitClient(for: worktree)
  let root = worktree.repositoryRootURL
  return {
    if let override, !override.isEmpty { return override }
    return await gitClient.automaticWorktreeBaseRef(root)
  }
}
```

Confirm the per-repo settings lookup shape: grep `worktreeBaseRef` in `RepositoriesFeature.swift` for how creation reads it and reuse that exact expression.

In `.worktreeInfoEvent(.branchChanged)`: after the branch-name effect, merge `.send(.refreshAheadBehind(worktreeID:))`. Also send `.refreshAheadBehind` from wherever the reconcile pass lands per worktree (the `filesChanged` event is the reconcile's per-worktree signal; add a 1-in-N guard: only refresh ahead/behind on `filesChanged` when `row.aheadCount == nil` so the first paint happens without waiting for a branch change, and otherwise rely on `branchChanged` and the HEAD kqueue).

```swift
case .refreshAheadBehind(let worktreeID):
  guard let worktree = state.worktree(for: worktreeID), !worktree.isMissing else { return .none }
  let gitClient = gitClient(for: worktree)
  let resolveBase = state.syncBaseRefResolver(for: worktree)
  let url = worktree.workingDirectory
  return .run { send in
    guard let base = await resolveBase() else { return }
    let result = await gitClient.aheadBehind(url, base)
    await send(.worktreeAheadBehindLoaded(worktreeID: worktreeID, result: result, base: base))
  }
  .cancellable(id: CancelID.worktreeAheadBehind(worktreeID), cancelInFlight: true)

case .worktreeAheadBehindLoaded(let worktreeID, let result, let base):
  return .send(.sidebarItems(.element(id: worktreeID, action: .aheadBehindChanged(
    ahead: result?.ahead, behind: result?.behind, base: base))))

case .syncWorktreeWithBase(let worktreeID, let operation):
  guard state.canSync(worktreeID: worktreeID),
    let worktree = state.worktree(for: worktreeID),
    let base = state.sidebarItems[id: worktreeID]?.syncBaseRef
  else { return .none }
  let gitClient = gitClient(for: worktree)
  let url = worktree.workingDirectory
  return .concatenate(
    .send(.sidebarItems(.element(id: worktreeID, action: .syncStateChanged(true)))),
    .run { send in
      // Dirty-tree guard runs here, not in canSync, because fileStatus is async.
      if let status = await gitClient.fileStatus(url), !status.isClean {
        await send(.syncWorktreeFinished(worktreeID: worktreeID, result: .failure(.failed("Commit or stash your changes first."))))
        return
      }
      do {
        switch operation {
        case .rebase: try await gitClient.rebaseOnto(url, base)
        case .merge: try await gitClient.mergeBaseRef(url, base)
        }
        await send(.syncWorktreeFinished(worktreeID: worktreeID, result: .success(())))
      } catch let error as GitSyncError {
        await send(.syncWorktreeFinished(worktreeID: worktreeID, result: .failure(error)))
      } catch {
        await send(.syncWorktreeFinished(worktreeID: worktreeID, result: .failure(.failed(error.localizedDescription))))
      }
    }
  )

case .syncWorktreeFinished(let worktreeID, let result):
  var effects: [Effect<Action>] = [
    .send(.sidebarItems(.element(id: worktreeID, action: .syncStateChanged(false))))
  ]
  switch result {
  case .success:
    effects.append(.send(.refreshAheadBehind(worktreeID: worktreeID)))
    effects.append(.send(.worktreeInfoEvent(.filesChanged(worktreeID: worktreeID))))
  case .failure(let error):
    let message: String
    switch error {
    case .conflict(let op):
      message = "\(op.verb) stopped on conflicts. The \(op.rawValue) was aborted and your branch is unchanged."
    case .failed(let text):
      message = text
    }
    state.alert = AlertState { TextState("Couldn't Sync With Base") } message: { TextState(message) }
  }
  return .merge(effects)
```

`GitStatusSnapshot.isClean`: add a computed property if missing (`entries.isEmpty`). Add `case worktreeAheadBehind(Worktree.ID)` to the feature's `CancelID` enum. `canSync`:

```swift
func canSync(worktreeID: Worktree.ID) -> Bool {
  guard let row = sidebarItems[id: worktreeID], let behind = row.behindCount, behind > 0 else { return false }
  return !row.isSyncing && !row.hasAgentActivity && !row.isMissing && row.lifecycle == .idle && !row.isMainWorktree
}
```

The alert: use the feature's existing `AlertState<Alert>` pattern (grep `AlertState {` in `RepositoriesFeature.swift`); if the alert enum needs a case, add `case dismissSync` with no buttons beyond the default OK.

`SidebarItemView.swift`: next to the `DiffStatsContent` usage, when `store.behindCount` is non-nil:

```swift
if let behind = store.behindCount {
  BehindCountContent(behind: behind, base: store.syncBaseRef ?? "base")
}

private struct BehindCountContent: View, Equatable {
  let behind: Int
  let base: String
  var body: some View {
    Label("\(behind)", systemImage: "arrow.down")
      .labelStyle(.titleAndIcon)
      .appFont(.caption)
      .monospacedDigit()
      .foregroundStyle(.secondary)
      .help("\(behind) commit\(behind == 1 ? "" : "s") behind \(base)")
      .accessibilityLabel("\(behind) commits behind \(base)")
  }
}
```

`SidebarItemsView.swift` context menu, after "Rename Branch…":

```swift
if !rowIsFolder, !row.isMissing, row.isAttached, let base = row.syncBaseRef {
  let canSync = store.state.canSync(worktreeID: rowID)
  Button("Rebase onto \(base)", systemImage: "arrow.triangle.branch") {
    store.send(.syncWorktreeWithBase(worktreeID: rowID, operation: .rebase))
  }
  .help(canSync ? "Rebase this branch onto \(base)" : "Available when the branch is behind, the tree is clean, and no agent is working")
  .disabled(!canSync)
  Button("Merge \(base) into Branch", systemImage: "arrow.triangle.merge") {
    store.send(.syncWorktreeWithBase(worktreeID: rowID, operation: .merge))
  }
  .help(canSync ? "Merge \(base) into this branch" : "Available when the branch is behind, the tree is clean, and no agent is working")
  .disabled(!canSync)
}
```

`row` in that menu is the row's state value already in scope (it reads `row.isMissing`), so `row.syncBaseRef` is available without touching `sidebarItems[id:]` in the body.

- [ ] **Step 4: Run `RepositoriesFeatureTests` (new section), `SidebarItemFeatureTests`, `SidebarStructureTests`; expect PASS.** `make build-app`. Manually: create a worktree from an old commit, confirm `↓N` appears within a minute (or after `Refresh Worktrees`), right-click → Rebase; confirm the count clears.

- [ ] **Step 5: Commit**

```bash
git add supacode/Features/Repositories/Reducer/SidebarItemFeature.swift supacode/Features/Repositories/Reducer/RepositoriesFeature.swift supacode/Features/Repositories/Views/SidebarItemView.swift supacode/Features/Repositories/Views/SidebarItemsView.swift supacodeTests/RepositoriesFeatureTests.swift
git commit -m "Show commits-behind on worktree rows with guarded rebase and merge"
```

---

## W4. Stale worktree review

### Task 11: Track `lastFocusedAt` and add the stale setting

**Files:**
- Modify: `supacode/Features/Repositories/BusinessLogic/SidebarState.swift` (`Item`, ~line 193)
- Modify: `supacode/Features/Repositories/Reducer/RepositoriesFeature.swift` (`.selectWorktree` ~4065; `.agentHookEventReceived` fan-out lives in `AppFeature.swift` ~2112, so add a `RepositoriesFeature.Action.worktreeTouched(Worktree.ID)` the parent sends)
- Modify: `SupacodeSettingsShared/Models/GlobalSettings.swift`, `SupacodeSettingsFeature/Reducer/SettingsFeature.swift`, the Worktrees settings view (`grep -rl autoDeleteArchivedWorktreesAfterDays SupacodeSettingsFeature/Views supacode/Features/Settings/Views`)
- Test: `supacodeTests/RepositoriesFeatureTests.swift`, `supacodeTests/GlobalSettingsTests.swift` (or the settings decode suite; grep `autoDeleteArchivedWorktreesAfterDays` in `supacodeTests`)

**Interfaces:**
- Produces: `SidebarState.Item.lastFocusedAt: Date?`; `SidebarState.touch(worktree:in:at:)`; `SidebarState.lastFocusedAt(for:) -> Date?`; `RepositoriesFeature.Action.worktreeTouched(Worktree.ID)`; `GlobalSettings.staleWorktreeAfterDays: Int` (default 7, 0 disables).

- [ ] **Step 1: Write the failing tests**

```swift
// RepositoriesFeatureTests
@Test func selectingWorktreeStampsLastFocusedAt() async {
  let worktree = makeWorktree(id: "/tmp/wt")
  let now = Date(timeIntervalSince1970: 4_000)
  let store = makeStore(worktrees: [worktree]) { $0.date = .constant(now) }
  store.exhaustivity = .off
  await store.send(.selectWorktree(worktree.id, focusTerminal: false))
  #expect(store.state.sidebar.lastFocusedAt(for: worktree.id) == now)
}

@Test func worktreeTouchedStampsLastFocusedAt() async {
  let worktree = makeWorktree(id: "/tmp/wt")
  let now = Date(timeIntervalSince1970: 5_000)
  let store = makeStore(worktrees: [worktree]) { $0.date = .constant(now) }
  store.exhaustivity = .off
  await store.send(.worktreeTouched(worktree.id))
  #expect(store.state.sidebar.lastFocusedAt(for: worktree.id) == now)
}

// Settings decode suite
@Test func staleWorktreeAfterDaysDefaultsToSevenWhenAbsent() throws {
  let json = #"{}"#
  let settings = try JSONDecoder().decode(GlobalSettings.self, from: Data(json.utf8))
  #expect(settings.staleWorktreeAfterDays == 7)
}
```

Match the decode fixture style used in the existing settings test file (it may need a fuller JSON object).

- [ ] **Step 2: Run both suites; expect FAIL** to compile.

- [ ] **Step 3: Implement**

`SidebarState.Item`: add `var lastFocusedAt: Date?`, a `CodingKeys` case, `decodeIfPresent`, `encodeIfPresent`, and the memberwise `init` parameter (default nil). Add mutators in the write-side extension:

```swift
/// Stamp the worktree as used at `date`. Looks in every bucket so an
/// archived row that receives a late hook event still records it.
mutating func touch(worktree worktreeID: Worktree.ID, in repositoryID: Repository.ID, at date: Date) {
  guard var section = sections[repositoryID] else { return }
  for (bucketID, var bucket) in section.buckets where bucket.items[worktreeID] != nil {
    bucket.items[worktreeID]?.lastFocusedAt = date
    section.buckets[bucketID] = bucket
    sections[repositoryID] = section
    return
  }
}

func lastFocusedAt(for worktreeID: Worktree.ID) -> Date? {
  for section in sections.values {
    for bucket in section.buckets.values {
      if let item = bucket.items[worktreeID] { return item.lastFocusedAt }
    }
  }
  return nil
}
```

Use the file's own `OrderedDictionary` iteration idiom (it may expose `.elements`). `sidebar` is `@Shared`-backed in `RepositoriesFeature.State` (check how `pin` is called from the reducer, e.g. `state.$sidebar.withLock { $0.pin(...) }`) and mirror that call shape.

`RepositoriesFeature`:

```swift
case worktreeTouched(Worktree.ID)
...
case .worktreeTouched(let worktreeID):
  state.touchWorktree(worktreeID)
  return .none
```

with

```swift
mutating func touchWorktree(_ worktreeID: Worktree.ID) {
  @Dependency(\.date.now) var now
  guard let repositoryID = repositoryID(containing: worktreeID) else { return }
  $sidebar.withLock { $0.touch(worktree: worktreeID, in: repositoryID, at: now) }
}
```

In `.selectWorktree`, after `setSingleWorktreeSelection`, call `if let worktreeID { state.touchWorktree(worktreeID) }`.

`AppFeature.swift` at the `agentHookEventReceived` handler (~2112): resolve the surface's worktree with the existing `surfaceToItemID` index and append `.send(.repositories(.worktreeTouched(itemID)))` to the returned effects. Only do this when the event name is `.busy` or `.sessionStart` so a 1 Hz idle debounce does not rewrite the sidebar file each second; the `$sidebar` write is persisted, so keep it rare.

`GlobalSettings`: add `public var staleWorktreeAfterDays: Int` with default `7`, a `CodingKeys` entry, `decodeIfPresent ?? Self.default.staleWorktreeAfterDays`, and the memberwise init parameter. `SettingsFeature.State` mirrors it exactly as `autoDeleteArchivedWorktreesAfterDays` is mirrored (fields at ~76, ~212, ~402) with a `BindingAction`-driven write-through; copy the binding handling used by another plain `Int`/`Bool` setting in that reducer. In the Worktrees settings view add, under the auto-delete control:

```swift
Stepper(value: $store.staleWorktreeAfterDays, in: 0...90) {
  LabeledContent("Mark worktrees stale after") {
    Text(store.staleWorktreeAfterDays == 0 ? "Never" : "\(store.staleWorktreeAfterDays) days")
      .monospacedDigit()
  }
}
.help("Worktrees not opened for this many days appear in Review Stale Worktrees. 0 turns the idle rule off.")
```

- [ ] **Step 4: Run `RepositoriesFeatureTests`, the settings decode suite, `AppFeatureSettingsChangedTests`; expect PASS.** `make build-app`.

- [ ] **Step 5: Commit**

```bash
git add supacode/Features/Repositories/BusinessLogic/SidebarState.swift supacode/Features/Repositories/Reducer/RepositoriesFeature.swift supacode/Features/App/Reducer/AppFeature.swift SupacodeSettingsShared/Models/GlobalSettings.swift SupacodeSettingsFeature/Reducer/SettingsFeature.swift <worktrees-settings-view-path> supacodeTests/RepositoriesFeatureTests.swift <settings-test-path>
git commit -m "Record worktree last-focused time and add the stale-after-days setting"
```

### Task 12: Stale classifier

**Files:**
- Create: `supacode/Domain/StaleWorktreeClassifier.swift`
- Create: `supacodeTests/StaleWorktreeClassifierTests.swift`

**Interfaces:**
- Produces:
  ```swift
  enum StaleReason: Equatable, Sendable { case empty; case idle(days: Int) }
  enum StaleWorktreeClassifier {
    struct Input: Equatable, Sendable {
      var isMainWorktree: Bool; var isPinned: Bool; var isArchived: Bool; var isMissing: Bool
      var hasOpenPullRequest: Bool; var aheadCount: Int?; var isTreeClean: Bool?
      var lastFocusedAt: Date?; var createdAt: Date?
    }
    static func classify(_ input: Input, now: Date, staleAfterDays: Int) -> StaleReason?
  }
  ```

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing

@testable import supacode

struct StaleWorktreeClassifierTests {
  private let now = Date(timeIntervalSince1970: 1_000_000)
  private func input(_ edit: (inout StaleWorktreeClassifier.Input) -> Void = { _ in }) -> StaleWorktreeClassifier.Input {
    var i = StaleWorktreeClassifier.Input(
      isMainWorktree: false, isPinned: false, isArchived: false, isMissing: false,
      hasOpenPullRequest: false, aheadCount: 1, isTreeClean: true,
      lastFocusedAt: now, createdAt: now)
    edit(&i)
    return i
  }

  @Test func emptyWhenNothingAheadAndClean() {
    let r = StaleWorktreeClassifier.classify(input { $0.aheadCount = 0 }, now: now, staleAfterDays: 7)
    #expect(r == .empty)
  }

  @Test func notEmptyWhenDirty() {
    let r = StaleWorktreeClassifier.classify(input { $0.aheadCount = 0; $0.isTreeClean = false }, now: now, staleAfterDays: 7)
    #expect(r == nil)
  }

  @Test func unknownCountsAreNeverEmpty() {
    let r = StaleWorktreeClassifier.classify(input { $0.aheadCount = nil }, now: now, staleAfterDays: 7)
    #expect(r == nil)
  }

  @Test func idleAfterThreshold() {
    let old = now.addingTimeInterval(-86_400 * 9)
    let r = StaleWorktreeClassifier.classify(input { $0.lastFocusedAt = old }, now: now, staleAfterDays: 7)
    #expect(r == .idle(days: 9))
  }

  @Test func idleFallsBackToCreatedAtWhenNeverFocused() {
    let r = StaleWorktreeClassifier.classify(
      input { $0.lastFocusedAt = nil; $0.createdAt = now.addingTimeInterval(-86_400 * 8) }, now: now, staleAfterDays: 7)
    #expect(r == .idle(days: 8))
  }

  @Test func zeroDaysDisablesIdleRuleOnly() {
    let old = now.addingTimeInterval(-86_400 * 30)
    #expect(StaleWorktreeClassifier.classify(input { $0.lastFocusedAt = old }, now: now, staleAfterDays: 0) == nil)
    #expect(StaleWorktreeClassifier.classify(input { $0.lastFocusedAt = old; $0.aheadCount = 0 }, now: now, staleAfterDays: 0) == .empty)
  }

  @Test func emptyWinsOverIdle() {
    let old = now.addingTimeInterval(-86_400 * 30)
    #expect(StaleWorktreeClassifier.classify(input { $0.lastFocusedAt = old; $0.aheadCount = 0 }, now: now, staleAfterDays: 7) == .empty)
  }

  @Test func exclusionsNeverStale() {
    let old = now.addingTimeInterval(-86_400 * 30)
    for edit in [
      { (i: inout StaleWorktreeClassifier.Input) in i.isMainWorktree = true },
      { $0.isPinned = true }, { $0.isArchived = true }, { $0.isMissing = true },
    ] {
      #expect(StaleWorktreeClassifier.classify(input { edit(&$0); $0.lastFocusedAt = old; $0.aheadCount = 0 }, now: now, staleAfterDays: 7) == nil)
    }
  }

  @Test func openPullRequestNeverStale() {
    let old = now.addingTimeInterval(-86_400 * 30)
    let r = StaleWorktreeClassifier.classify(input { $0.hasOpenPullRequest = true; $0.lastFocusedAt = old; $0.aheadCount = 0 }, now: now, staleAfterDays: 7)
    #expect(r == nil)
  }
}
```

- [ ] **Step 2: Run `StaleWorktreeClassifierTests`; expect FAIL** (type missing).

- [ ] **Step 3: Implement**

```swift
// supacode/Domain/StaleWorktreeClassifier.swift
import Foundation

/// Why a worktree is a cleanup candidate. `empty` beats `idle`: a branch with
/// nothing on it is stale regardless of age.
nonisolated enum StaleReason: Equatable, Sendable {
  /// No commits ahead of base and a clean tree.
  case empty
  /// Not opened for this many days (last focus, else directory creation).
  case idle(days: Int)

  var title: String {
    switch self {
    case .empty: "Nothing on this branch"
    case .idle(let days): "Not opened for \(days) day\(days == 1 ? "" : "s")"
    }
  }
}

/// Pure rule. Unknown counts (`aheadCount == nil`, `isTreeClean == nil`) never
/// produce `empty`; a missing probe must not look like a verdict.
nonisolated enum StaleWorktreeClassifier {
  struct Input: Equatable, Sendable {
    var isMainWorktree: Bool
    var isPinned: Bool
    var isArchived: Bool
    var isMissing: Bool
    var hasOpenPullRequest: Bool
    var aheadCount: Int?
    var isTreeClean: Bool?
    var lastFocusedAt: Date?
    var createdAt: Date?
  }

  static func classify(_ input: Input, now: Date, staleAfterDays: Int) -> StaleReason? {
    if input.isMainWorktree || input.isPinned || input.isArchived || input.isMissing || input.hasOpenPullRequest {
      return nil
    }
    if input.aheadCount == 0, input.isTreeClean == true { return .empty }
    guard staleAfterDays > 0, let reference = input.lastFocusedAt ?? input.createdAt else { return nil }
    let days = Int(now.timeIntervalSince(reference) / 86_400)
    return days >= staleAfterDays ? .idle(days: days) : nil
  }
}
```

- [ ] **Step 4: Run `StaleWorktreeClassifierTests`; expect PASS.**

- [ ] **Step 5: Commit**

```bash
git add supacode/Domain/StaleWorktreeClassifier.swift supacodeTests/StaleWorktreeClassifierTests.swift
git commit -m "Add pure stale worktree classifier"
```

### Task 13: Stale state on rows, indicator, and review view

**Files:**
- Modify: `supacode/Features/Repositories/Reducer/SidebarItemFeature.swift` (`staleReason: StaleReason?`, `isTreeClean: Bool?`, actions)
- Modify: `supacode/Features/Repositories/Reducer/RepositoriesFeature.swift` (classify after `aheadBehindChanged`, `fileStatus` probe, `selectStaleWorktrees`, `staleWorktreesByRepository()`)
- Modify: `supacode/Features/Repositories/Views/SidebarSelection.swift`, `WorktreeDetailView.swift` (~276), `supacode/App/WindowTitle.swift` (~25), `supacode/Commands/WorktreeCommands.swift`, `supacode/Features/Repositories/Views/SidebarItemView.swift`
- Create: `supacode/Features/Repositories/Views/StaleWorktreesDetailView.swift`
- Test: `supacodeTests/RepositoriesFeatureTests.swift`, `supacodeTests/AppFeatureArchivedSelectionTests.swift` (sibling test for stale selection)

**Interfaces:**
- Produces: `SidebarItemFeature.State.staleReason`, `.isTreeClean`; `SidebarItemFeature.Action.staleReasonChanged(StaleReason?)`, `.treeCleanChanged(Bool?)`; `RepositoriesFeature.Action.selectStaleWorktrees`, `.reclassifyStale(worktreeID:)`, `.worktreeTreeCleanLoaded(worktreeID:isClean:)`; `SidebarSelection.staleWorktrees`; `RepositoriesFeature.State.staleWorktreesByRepository() -> [(repository: Repository, rows: [(worktree: Worktree, reason: StaleReason, lastFocusedAt: Date?, ahead: Int?)])]`.

- [ ] **Step 1: Write the failing tests**

```swift
// RepositoriesFeatureTests
@Test func aheadBehindLoadTriggersStaleClassification() async {
  let worktree = makeWorktree(id: "/tmp/wt")
  let now = Date(timeIntervalSince1970: 10_000_000)
  let store = makeStore(worktrees: [worktree]) {
    $0.date = .constant(now)
    $0.gitClient.fileStatus = { _ in GitStatusSnapshot(entries: []) }
  }
  store.exhaustivity = .off
  await store.send(.worktreeAheadBehindLoaded(worktreeID: worktree.id, result: GitAheadBehind(ahead: 0, behind: 0), base: "origin/main"))
  await store.receive(\.worktreeTreeCleanLoaded)
  await store.finish()
  #expect(store.state.sidebarItems[id: worktree.id]?.staleReason == .empty)
}

@Test func selectStaleWorktreesClearsWorktreeSelection() async {
  let worktree = makeWorktree(id: "/tmp/wt")
  let store = makeStore(worktrees: [worktree]) { _ in }
  store.exhaustivity = .off
  await store.send(.selectStaleWorktrees) {
    $0.selection = .staleWorktrees
    $0.sidebarSelectedWorktreeIDs = []
  }
}
```

- [ ] **Step 2: Run `RepositoriesFeatureTests`; expect FAIL** to compile.

- [ ] **Step 3: Implement**

`SidebarItemFeature.State`: `var staleReason: StaleReason?` and `var isTreeClean: Bool?`, with the two actions guarding on equality like `aheadBehindChanged`.

`RepositoriesFeature`:

```swift
case .worktreeAheadBehindLoaded(let worktreeID, let result, let base):
  guard let worktree = state.worktree(for: worktreeID) else { return .none }
  let gitClient = gitClient(for: worktree)
  let url = worktree.workingDirectory
  return .concatenate(
    .send(.sidebarItems(.element(id: worktreeID, action: .aheadBehindChanged(ahead: result?.ahead, behind: result?.behind, base: base)))),
    .run { send in
      let status = await gitClient.fileStatus(url)
      await send(.worktreeTreeCleanLoaded(worktreeID: worktreeID, isClean: status.map(\.isClean)))
    }
    .cancellable(id: CancelID.worktreeTreeClean(worktreeID), cancelInFlight: true)
  )

case .worktreeTreeCleanLoaded(let worktreeID, let isClean):
  return .concatenate(
    .send(.sidebarItems(.element(id: worktreeID, action: .treeCleanChanged(isClean)))),
    .send(.reclassifyStale(worktreeID: worktreeID))
  )

case .reclassifyStale(let worktreeID):
  @Dependency(\.date.now) var now
  @Shared(.settingsFile) var settingsFile
  guard let row = state.sidebarItems[id: worktreeID], let worktree = state.worktree(for: worktreeID) else { return .none }
  let input = StaleWorktreeClassifier.Input(
    isMainWorktree: row.isMainWorktree, isPinned: row.isPinned,
    isArchived: state.archivedWorktreeIDSet.contains(worktreeID), isMissing: row.isMissing,
    hasOpenPullRequest: row.pullRequest.map { $0.state == .open } ?? false,
    aheadCount: row.aheadCount, isTreeClean: row.isTreeClean,
    lastFocusedAt: state.sidebar.lastFocusedAt(for: worktreeID), createdAt: worktree.createdAt)
  let reason = StaleWorktreeClassifier.classify(input, now: now, staleAfterDays: settingsFile.global.staleWorktreeAfterDays)
  return .send(.sidebarItems(.element(id: worktreeID, action: .staleReasonChanged(reason))))
```

Check `ForgePullRequest` for how "open" is represented (grep `isOpen` / `state ==`) and use that. Also send `.reclassifyStale` from `.selectWorktree` (after touch) and from the `pullRequestChanged` landing so a PR opening un-stales the row. Sending it on `settingsChanged` for `staleWorktreeAfterDays`: in the handler that reacts to `setAutoDeleteArchivedWorktreesAfterDays` (`AppFeatureSettingsChangedTests` shows the pattern), add a sibling that sends `.reclassifyStale` for every row.

```swift
case .selectStaleWorktrees:
  state.selection = .staleWorktrees
  state.sidebarSelectedWorktreeIDs = []
  return .send(.delegate(.selectedWorktreeChanged(nil)))
```

`SidebarSelection`: add `case staleWorktrees` and extend both computed properties' `case` lists. `WindowTitle`: `case .staleWorktrees: return "Stale Worktrees"`. `WorktreeDetailView`: before the archived branch, `if repositories.isShowingStaleWorktrees { StaleWorktreesDetailView(store: ...) }` with `var isShowingStaleWorktrees: Bool { selection == .staleWorktrees }` next to `isShowingArchivedWorktrees`.

```swift
func staleWorktreesByRepository() -> [(repository: Repository, rows: [StaleWorktreeRow])] {
  var groups: [(repository: Repository, rows: [StaleWorktreeRow])] = []
  for repository in repositories {
    let rows = repository.worktrees.compactMap { worktree -> StaleWorktreeRow? in
      guard let row = sidebarItems[id: worktree.id], let reason = row.staleReason else { return nil }
      return StaleWorktreeRow(worktree: worktree, reason: reason, lastFocusedAt: sidebar.lastFocusedAt(for: worktree.id), ahead: row.aheadCount)
    }
    if !rows.isEmpty { groups.append((repository: repository, rows: rows)) }
  }
  return groups
}

struct StaleWorktreeRow: Equatable, Identifiable {
  let worktree: Worktree
  let reason: StaleReason
  let lastFocusedAt: Date?
  let ahead: Int?
  var id: Worktree.ID { worktree.id }
}
```

`StaleWorktreesDetailView.swift`: copy `ArchivedWorktreesDetailView` structurally. Differences: title "Stale Worktrees", `systemImage: "clock.badge.xmark"`, empty description "Worktrees with nothing on them, or untouched for a while, show up here.", row shows branch name, `reason.title`, and "Last opened \(lastFocusedAt.formatted(.relative(presentation: .named)))" when present, plus `+N` ahead when non-nil; row buttons are "Archive" (`store.send(.requestArchiveWorktree(worktree.id))`) and "Delete". Toolbar: "Archive Selected" (`requestArchiveWorktrees(targets)` building `ArchiveWorktreeTarget`s, struct at `RepositoriesFeature.swift:639`) and "Delete Selected". Both with `.help`. Use `List(selection:)`, `.listStyle(.sidebar)` exactly as the archived view does.

`WorktreeCommands.swift`: after "Archived Worktrees", add

```swift
Button("Review Stale Worktrees", systemImage: "clock.badge.xmark") {
  store.send(.repositories(.selectStaleWorktrees))
}
.help("Review worktrees with nothing on them or untouched for a while")
.disabled(!snapshot.isInitialLoadComplete)
```

Add a command palette entry next to the archived one (`AppFeature.swift` ~1805).

`SidebarItemView.swift`: next to the behind-count accessory, `if let reason = store.staleReason { Image(systemName: "clock.badge.xmark").foregroundStyle(.tertiary).help(reason.title).accessibilityLabel("Stale: \(reason.title)") }`.

- [ ] **Step 4: Run `RepositoriesFeatureTests`, `AppFeatureArchivedSelectionTests` (add a sibling `selectStaleWorktrees` test mirroring it), `SidebarStructureTests`; expect PASS.** `make build-app`. Manually: create a throwaway worktree, confirm it appears under Review Stale Worktrees as "Nothing on this branch", archive from the view.

- [ ] **Step 5: Commit**

```bash
git add supacode/Features/Repositories/Reducer/SidebarItemFeature.swift supacode/Features/Repositories/Reducer/RepositoriesFeature.swift supacode/Features/Repositories/Views/SidebarSelection.swift supacode/Features/Repositories/Views/WorktreeDetailView.swift supacode/App/WindowTitle.swift supacode/Commands/WorktreeCommands.swift supacode/Features/Repositories/Views/SidebarItemView.swift supacode/Features/Repositories/Views/StaleWorktreesDetailView.swift supacode/Features/App/Reducer/AppFeature.swift supacodeTests/RepositoriesFeatureTests.swift supacodeTests/AppFeatureArchivedSelectionTests.swift
git commit -m "Classify stale worktrees and add the Review Stale Worktrees view"
```

---

## W6. Sort worktrees within a repo

### Task 14: Per-section worktree sort

**Files:**
- Create: `supacode/Domain/SidebarWorktreeSort.swift`
- Modify: `supacode/Features/Repositories/BusinessLogic/SidebarState.swift` (`Section`, ~line 91)
- Modify: `supacode/Features/Repositories/BusinessLogic/SidebarStructure.swift` (`computeSlots` ~1146; `moveBehavior` ~162)
- Modify: `supacode/Features/Repositories/Reducer/RepositoriesFeature.swift` (`setWorktreeSort(repositoryID:sort:)`)
- Modify: `supacode/Features/Repositories/Views/SidebarItemsView.swift` (section header context menu; find where `Sort Sidebar Sections` is offered in `SidebarCommands.swift` and add a per-repo submenu in the repo header's context menu, grep `contextMenu` in the header view file that renders repo sections)
- Create: `supacodeTests/SidebarWorktreeSortTests.swift`; modify `supacodeTests/SidebarStructureTests.swift`

**Interfaces:**
- Produces:
  ```swift
  enum SidebarWorktreeSort: String, CaseIterable, Codable { case manual, recentActivity, agentState; var menuTitle: String; var allowsReordering: Bool }
  SidebarState.Section.worktreeSort: SidebarWorktreeSort  // default .manual, Codable optional-decoded
  RepositoriesFeature.Action.setWorktreeSort(repositoryID: Repository.ID, sort: SidebarWorktreeSort)
  SidebarItemGroup.moveBehavior honours the sort (returns .disabled when !allowsReordering)
  ```

- [ ] **Step 1: Write the failing tests**

```swift
// supacodeTests/SidebarWorktreeSortTests.swift
import Foundation
import Testing
@testable import supacode

struct SidebarWorktreeSortTests {
  @Test func manualIsIdentityAndReorderable() {
    #expect(SidebarWorktreeSort.manual.allowsReordering)
    #expect(SidebarWorktreeSort.manual.ordered(["b", "a"], key: { _ in .init(lastFocusedAt: nil, rank: 0, since: nil, branchName: "") }) == ["b", "a"])
  }

  @Test func recentActivityOrdersNewestFirstThenName() {
    let keys: [String: SidebarWorktreeSort.Key] = [
      "a": .init(lastFocusedAt: Date(timeIntervalSince1970: 100), rank: 0, since: nil, branchName: "a"),
      "b": .init(lastFocusedAt: Date(timeIntervalSince1970: 900), rank: 0, since: nil, branchName: "b"),
      "c": .init(lastFocusedAt: nil, rank: 0, since: nil, branchName: "c"),
    ]
    #expect(SidebarWorktreeSort.recentActivity.ordered(["a", "b", "c"], key: { keys[$0]! }) == ["b", "a", "c"])
    #expect(!SidebarWorktreeSort.recentActivity.allowsReordering)
  }

  @Test func agentStateOrdersByRankThenWaitThenName() {
    let keys: [String: SidebarWorktreeSort.Key] = [
      "idle": .init(lastFocusedAt: nil, rank: 4, since: nil, branchName: "idle"),
      "busy": .init(lastFocusedAt: nil, rank: 2, since: Date(timeIntervalSince1970: 50), branchName: "busy"),
      "waitNew": .init(lastFocusedAt: nil, rank: 1, since: Date(timeIntervalSince1970: 900), branchName: "waitNew"),
      "waitOld": .init(lastFocusedAt: nil, rank: 1, since: Date(timeIntervalSince1970: 100), branchName: "waitOld"),
      "err": .init(lastFocusedAt: nil, rank: 0, since: Date(timeIntervalSince1970: 500), branchName: "err"),
    ]
    let out = SidebarWorktreeSort.agentState.ordered(["idle", "busy", "waitNew", "waitOld", "err"], key: { keys[$0]! })
    #expect(out == ["err", "waitOld", "waitNew", "busy", "idle"])
  }
}
```

Append to `SidebarStructureTests`:

```swift
@Test func agentStateSortAppliesToUnpinnedTailOnlyAndDisablesMove() {
  // Build a repo with: main, one pinned row, three unpinned rows, where one unpinned row is awaiting.
  // Set state.sidebar.sections[repo]?.worktreeSort = .agentState (through the setter used in production).
  // Expect: pinnedTail order unchanged; unpinnedTail puts the awaiting row first;
  // the unpinnedTail group's moveBehavior == .disabled.
}
```

Fill the body with this file's state builders (it has helpers that create a `RepositoriesFeature.State` with N worktrees and a sidebar bucket layout; look at the nearest test that asserts `unpinnedTail` order and copy its setup).

- [ ] **Step 2: Run both suites; expect FAIL** to compile.

- [ ] **Step 3: Implement**

```swift
// supacode/Domain/SidebarWorktreeSort.swift
import Foundation

/// Display order for the worktrees inside one repository section. A sorted
/// mode is an overlay on the persisted drag order and never rewrites it, so
/// drag-reorder is off outside `.manual`.
nonisolated enum SidebarWorktreeSort: String, CaseIterable, Codable, Equatable, Hashable, Identifiable, Sendable {
  case manual
  case recentActivity
  case agentState

  static let `default` = SidebarWorktreeSort.manual
  var id: String { rawValue }

  var menuTitle: String {
    switch self {
    case .manual: "Manual Order"
    case .recentActivity: "By Recent Activity"
    case .agentState: "By Agent State"
    }
  }

  /// Everything a comparator may read, resolved once per row by the caller so
  /// sorting never reaches back into reducer state.
  struct Key: Equatable, Sendable {
    var lastFocusedAt: Date?
    /// 0 error, 1 awaiting, 2 working, 3 idle-with-agent, 4 no agent.
    var rank: Int
    var since: Date?
    var branchName: String
  }

  var allowsReordering: Bool { self == .manual }

  func ordered<ID: Hashable & Comparable>(_ ids: [ID], key: (ID) -> Key) -> [ID] {
    switch self {
    case .manual:
      return ids
    case .recentActivity:
      let keyed = ids.map { ($0, key($0)) }
      return keyed.sorted { l, r in
        switch (l.1.lastFocusedAt, r.1.lastFocusedAt) {
        case let (a?, b?) where a != b: return a > b
        case (.some, .none): return true
        case (.none, .some): return false
        default: return Self.nameOrdersBefore(l.1.branchName, l.0, r.1.branchName, r.0)
        }
      }.map(\.0)
    case .agentState:
      let keyed = ids.map { ($0, key($0)) }
      return keyed.sorted { l, r in
        if l.1.rank != r.1.rank { return l.1.rank < r.1.rank }
        switch (l.1.since, r.1.since) {
        case let (a?, b?) where a != b: return a < b
        case (.some, .none): return true
        case (.none, .some): return false
        default: return Self.nameOrdersBefore(l.1.branchName, l.0, r.1.branchName, r.0)
        }
      }.map(\.0)
    }
  }

  private static func nameOrdersBefore<ID: Comparable>(_ a: String, _ aID: ID, _ b: String, _ bID: ID) -> Bool {
    switch a.localizedCaseInsensitiveCompare(b) {
    case .orderedAscending: return true
    case .orderedDescending: return false
    case .orderedSame: return aID < bID
    }
  }
}
```

`Worktree.ID` must be `Comparable`; if it is a `Tagged<_, String>` it already is. Otherwise compare `rawValue` by passing a `String` id into `ordered`.

`SidebarState.Section`: add `var worktreeSort: SidebarWorktreeSort`, default `.manual`, in the init, `SectionCodingKeys`, `decodeIfPresent ?? .manual` (wrapped in `try?` like `color`), and encode only when `!= .manual`.

`SidebarStructure.swift` `computeSlots`: after the `nestWorktreesByBranch` block,

```swift
let sort = state.sidebar.sections[repositoryID]?.worktreeSort ?? .manual
if sort != .manual {
  let key: (SidebarItemID) -> SidebarWorktreeSort.Key = { id in
    let row = state.sidebarItems[id: id]
    return .init(
      lastFocusedAt: state.sidebar.lastFocusedAt(for: id),
      rank: Self.agentRank(row),
      since: row?.agentSnapshot.since,
      branchName: row?.branchName ?? id.rawValue)
  }
  unpinnedTail = sort.ordered(unpinnedTail, key: key)
}
```

with

```swift
private static func agentRank(_ row: SidebarItemFeature.State?) -> Int {
  guard let row else { return 4 }
  if row.hasAgentError { return 0 }
  if row.hasAgentAwaitingInput { return 1 }
  if row.hasAgentActivity { return 2 }
  if !row.agents.isEmpty { return 3 }
  return 4
}
```

Pinned tail is deliberately left in manual order. `SidebarItemGroup` gains `let sortAllowsReordering: Bool` set from the section's sort in `computeSlots`, and `moveBehavior` returns `.disabled` when it is false. Note `SidebarItemsView` already omits `.onMove` for `.disabled`.

Because sorting now reads `sidebar.lastFocusedAt` and `agentSnapshot`, confirm `recomputeSidebarStructureIfChanged` is already triggered by `agentSnapshotChanged` (it is, per `SidebarStructure.swift:427/454`) and by the `$sidebar` write in `touchWorktree` (grep how `pin` triggers recompute and mirror it; if `sidebar` changes already flow through `sidebarGrouping` rebuild, nothing more is needed).

`RepositoriesFeature`:

```swift
case setWorktreeSort(repositoryID: Repository.ID, sort: SidebarWorktreeSort)
...
case .setWorktreeSort(let repositoryID, let sort):
  state.$sidebar.withLock { $0.sections[repositoryID]?.worktreeSort = sort }
  return .none
```

and make sure the structure recomputes after it (same path as `setCustomization`).

Section header context menu (the view that renders a repo section header; grep `"Rename Section"` or `setCustomization` in `supacode/Features/Repositories/Views`): add

```swift
Picker("Sort Worktrees", selection: Binding(
  get: { store.state.sidebar.sections[repositoryID]?.worktreeSort ?? .manual },
  set: { store.send(.setWorktreeSort(repositoryID: repositoryID, sort: $0)) }
)) {
  ForEach(SidebarWorktreeSort.allCases) { Text($0.menuTitle).tag($0) }
}
.help("Order this repository's worktrees")
```

Reading `store.state.sidebar.sections[...]` in a header body is a single-section read, not a per-row fan-out; acceptable.

- [ ] **Step 4: Run `SidebarWorktreeSortTests`, `SidebarStructureTests`, `SidebarStructureCoalescingTests`, `RepositoriesFeatureSidebarTests`; expect PASS**, including the existing manual-order tests byte-identical. `make build-app`.

- [ ] **Step 5: Commit**

```bash
git add supacode/Domain/SidebarWorktreeSort.swift supacode/Features/Repositories/BusinessLogic/SidebarState.swift supacode/Features/Repositories/BusinessLogic/SidebarStructure.swift supacode/Features/Repositories/Reducer/RepositoriesFeature.swift <section-header-view-path> supacodeTests/SidebarWorktreeSortTests.swift supacodeTests/SidebarStructureTests.swift
git commit -m "Sort worktrees within a repository by recent activity or agent state"
```

---

## W7. Hook health check

### Task 15: Last-event signal in settings and a test-event button

**Files:**
- Create: `SupacodeSettingsShared/Clients/CodingAgents/AgentHookActivityClient.swift`
- Modify: `SupacodeSettingsFeature/Reducer/SettingsFeature.swift` (state `lastHookEventAt: [SkillAgent: Date]`, actions `refreshHookActivity`, `hookActivityLoaded([SkillAgent: Date])`, `agentSendTestEventTapped(SkillAgent)`)
- Modify: `supacode/Features/Settings/Views/DeveloperSettingsView.swift` (`AgentIntegrationRow`)
- Modify: `supacode/Features/App/Reducer/AppFeature.swift` (provide the live client from presence state) and `supacode/App/supacodeApp.swift` or wherever `SettingsFeature` dependencies are prepared (grep `prepareDependencies` / `withDependencies` near settings store creation)
- Test: `supacodeTests/SettingsFeatureAgentIntegrationTests.swift`

**Interfaces:**
- Produces:
  ```swift
  public struct AgentHookActivityClient: Sendable {
    public var lastEventDates: @Sendable () async -> [SkillAgent: Date]
    /// Runs the agent's own installed hook command with SUPACODE_* env set to the focused surface, so the full OSC path is exercised.
    public var sendTestEvent: @Sendable (SkillAgent) async throws -> Void
  }
  ```

- [ ] **Step 1: Write the failing tests** (append to `SettingsFeatureAgentIntegrationTests`, following its `TestStore` setup)

```swift
@Test func hookActivityLoadsIntoState() async {
  let t = Date(timeIntervalSince1970: 123)
  let store = makeStore {  // this file's store builder
    $0.agentHookActivityClient.lastEventDates = { [.claude: t] }
  }
  store.exhaustivity = .off
  await store.send(.refreshHookActivity)
  await store.receive(\.hookActivityLoaded) { $0.lastHookEventAt = [.claude: t] }
}

@Test func hookStatusLineVariants() {
  let now = Date(timeIntervalSince1970: 1_000)
  #expect(AgentHookStatus.resolve(installed: .installed, lastEventAt: now.addingTimeInterval(-120), now: now)
    == .healthy(lastEvent: "2m 0s"))
  #expect(AgentHookStatus.resolve(installed: .installed, lastEventAt: nil, now: now) == .installedNoEvents)
  #expect(AgentHookStatus.resolve(installed: .outdated, lastEventAt: nil, now: now) == .outdated)
  #expect(AgentHookStatus.resolve(installed: .notInstalled, lastEventAt: nil, now: now) == .notInstalled)
}
```

- [ ] **Step 2: Run the suite; expect FAIL** to compile.

- [ ] **Step 3: Implement**

Client:

```swift
import ComposableArchitecture
import Foundation

/// App-side hook liveness exposed to the settings module, which cannot see
/// presence state directly. Wraps app state, not `@Shared`.
public nonisolated struct AgentHookActivityClient: Sendable {
  public var lastEventDates: @Sendable () async -> [SkillAgent: Date]
  public var sendTestEvent: @Sendable (SkillAgent) async throws -> Void

  public init(
    lastEventDates: @escaping @Sendable () async -> [SkillAgent: Date],
    sendTestEvent: @escaping @Sendable (SkillAgent) async throws -> Void
  ) {
    self.lastEventDates = lastEventDates
    self.sendTestEvent = sendTestEvent
  }
}

extension AgentHookActivityClient: TestDependencyKey {
  public static let testValue = Self(lastEventDates: { [:] }, sendTestEvent: { _ in })
}

extension DependencyValues {
  public var agentHookActivityClient: AgentHookActivityClient {
    get { self[AgentHookActivityClient.self] }
    set { self[AgentHookActivityClient.self] = newValue }
  }
}
```

`liveValue` lives in the app target (it needs presence state): in `AppFeature` or the app entry, where the settings store is created, set

```swift
$0.agentHookActivityClient = AgentHookActivityClient(
  lastEventDates: { await MainActor.run { presenceStore.lastEventAt } },
  sendTestEvent: { agent in
    // Resolve the agent's installed hook command (the SessionStart group) via
    // AgentIntegrationFactory.make(for: agent, configDirectoryURL: nil).installedHookCommand(event: "SessionStart")
    // and run it through ShellClient.live with env SUPACODE_SURFACE_ID / SUPACODE_TAB_ID /
    // SUPACODE_WORKTREE_ID / SUPACODE_SOCKET_PATH copied from the focused surface's env
    // (terminalClient exposes the focused surface's env; grep `SUPACODE_SURFACE_ID` in Terminal/ for the builder).
  })
```

If no "installedHookCommand" accessor exists, add `func managedCommand(forEvent:) -> String?` to `AgentHookSettingsFileInstaller` that reads the hooks file and returns the first managed command under that event. If no focused-surface env accessor exists, throw `AgentHookActivityError.noFocusedSurface` with message "Focus a terminal first." and surface it under the row.

Grep how `AppFeature.State` holds presence (`agentPresence`) and how `SettingsFeature` gets its dependencies (it may be a child reducer, in which case the dependency can be set with `.dependency(\.agentHookActivityClient, ...)` on the scoped reducer in `AppFeature.body`, reading `state.agentPresence.lastEventAt` through a `@Shared`-free closure that captures a `LockIsolated` copy updated on `surfacesChanged`). Simplest correct option: in `AppFeature`, on every `.agentPresence(.hookEventReceived)` also mirror `lastEventAt` into a `LockIsolated<[SkillAgent: Date]>` held by the live client. Pick whichever the codebase's existing cross-module clients use (compare `AgentIntegrationClient` wiring).

Status model (put it in `SupacodeSettingsShared/Models/AgentHookStatus.swift`):

```swift
public nonisolated enum AgentHookStatus: Equatable, Sendable {
  case healthy(lastEvent: String)
  case installedNoEvents
  case outdated
  case notInstalled

  public static func resolve(installed: AgentIntegrationState, lastEventAt: Date?, now: Date) -> AgentHookStatus {
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
    case .healthy(let e): "Hooks installed · last event \(e) ago"
    case .installedNoEvents: "Hooks installed · no events received this session"
    case .outdated: "Hooks outdated"
    case .notInstalled: "Hooks not installed"
    }
  }
}
```

Check the exact case names of `AgentIntegrationState` (grep its enum) and adjust.

`SettingsFeature`: add `public var lastHookEventAt: [SkillAgent: Date] = [:]`, actions, and:

```swift
case .refreshHookActivity:
  return .run { send in await send(.hookActivityLoaded(await agentHookActivityClient.lastEventDates())) }
case .hookActivityLoaded(let dates):
  state.lastHookEventAt = dates
  return .none
case .agentSendTestEventTapped(let agent):
  return .run { send in
    do {
      try await agentHookActivityClient.sendTestEvent(agent)
      try await clock.sleep(for: .seconds(3))
      await send(.refreshHookActivity)
    } catch {
      await send(.hookTestEventFailed(agent, reason: error.localizedDescription))
    }
  }
```

Add `hookTestEventFailed(SkillAgent, reason: String)` storing into `hookTestFailures: [SkillAgent: String]`. Send `.refreshHookActivity` wherever `.refreshAgentIntegrationStates` is sent (on `task` and on the Developer section appearing). Use the feature's `@Dependency(\.continuousClock)` for the sleep; tests drive it with `TestClock`.

`DeveloperSettingsView.AgentIntegrationRow`: under the capability grid, before the targets loop:

```swift
let rowState = store.agentIntegrationStates[agent] ?? .checking
if case .ready(let installed) = rowState {
  TimelineView(.periodic(from: .now, by: 30)) { context in
    let status = AgentHookStatus.resolve(installed: installed, lastEventAt: store.lastHookEventAt[agent], now: context.date)
    HStack(spacing: 6) {
      Circle().fill(statusColor(status)).frame(width: 7, height: 7)
      Text(status.text).appFont(.subheadline).foregroundStyle(.secondary)
      Spacer()
      if installed == .installed {
        Button("Send Test Event") { store.send(.agentSendTestEventTapped(agent)) }
          .help("Run \(agent.displayName)'s installed hook against the focused terminal to confirm events reach Supacode")
      }
    }
  }
  if let failure = store.hookTestFailures[agent] {
    Text(failure).appFont(.subheadline).foregroundStyle(.orange)
  }
}
```

with `statusColor`: `.green` for healthy, `.secondary`-ish `Color.gray` for no events / not installed, `.orange` for outdated. System colors only.

- [ ] **Step 4: Run `SettingsFeatureAgentIntegrationTests`; expect PASS.** `make build-app`. Manually: open Settings → Developer, confirm the status line; start `claude` in a terminal, return, confirm "last event Ns ago"; click Send Test Event with a terminal focused.

- [ ] **Step 5: Commit**

```bash
git add SupacodeSettingsShared/Clients/CodingAgents/AgentHookActivityClient.swift SupacodeSettingsShared/Models/AgentHookStatus.swift SupacodeSettingsFeature/Reducer/SettingsFeature.swift supacode/Features/Settings/Views/DeveloperSettingsView.swift supacode/Features/App/Reducer/AppFeature.swift supacodeTests/SettingsFeatureAgentIntegrationTests.swift
git commit -m "Settings: show hook liveness per agent and add a test-event button"
```

---

## Final verification

- [ ] `make build-app` on the branch head.
- [ ] `make test` full run; paste the failure summary if any and fix before declaring done.
- [ ] `make lint` and `make format`; commit any formatting diffs separately: `git commit -m "Format"`.
- [ ] Manual pass with one Claude and one Codex session side by side:
  1. Codex permission prompt → awaiting badge + notification; elapsed label ticks.
  2. `⌃⇧J` jumps to the longest-waiting row; the badge clears on focus.
  3. Menu bar shows "Needs You" first.
  4. Worktree behind base shows `↓N`; rebase from the row menu; conflict path shows the alert and leaves the tree intact (test with a deliberately conflicting commit on base).
  5. Empty worktree appears in Review Stale Worktrees; archive from there runs the archive script.
  6. Section sort "By Agent State" reorders live; drag is disabled; "Manual Order" restores drag.
  7. Settings → Developer shows hook status and the test event flips it.
- [ ] Append a session note to `/Users/mlaplante/Documents/obsidian/10-Projects/supacode.md` per the global capture rule.
