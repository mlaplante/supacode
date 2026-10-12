import ComposableArchitecture
import DependenciesTestSupport
import Foundation
import IdentifiedCollections
import Testing

@testable import SupacodeSettingsFeature
@testable import SupacodeSettingsShared
@testable import supacode

@MainActor
struct AppFeatureJumpToNextAwaitingTests {
  @Test(.dependencies) func noOpWhenNothingAwaits() async {
    let worktree = makeWorktree(id: "/tmp/repo/wt-1", name: "wt-1")
    let focused = LockIsolated<[TerminalClient.Command]>([])
    let store = makeStore(worktrees: [worktree]) { values in
      values.terminalClient.send = { command in focused.withValue { $0.append(command) } }
    }

    await store.send(.jumpToNextAwaiting)
    await store.finish()

    #expect(focused.value.isEmpty)
  }

  @Test(.dependencies) func selectsLongestWaitingWorktreeAndFocusesItsSurface() async {
    let newer = makeWorktree(id: "/tmp/repo/newer", name: "newer")
    let older = makeWorktree(id: "/tmp/repo/older", name: "older")
    let newerSurface = UUID()
    let olderSurface = UUID()
    let olderTab = TabID(rawValue: UUID())
    let focused = LockIsolated<[TerminalClient.Command]>([])
    let store = makeStore(
      worktrees: [newer, older],
      awaiting: [
        (newer, newerSurface, Date(timeIntervalSince1970: 900)),
        (older, olderSurface, Date(timeIntervalSince1970: 100)),
      ]
    ) { values in
      values.terminalClient.tabID = { worktreeID, surfaceID in
        worktreeID == older.id && surfaceID == olderSurface ? olderTab : nil
      }
      values.terminalClient.send = { command in focused.withValue { $0.append(command) } }
    }

    await store.send(.jumpToNextAwaiting)
    await store.receive(\.repositories.selectWorktree)
    await store.finish()

    let focusCommands = focused.value.filter {
      if case .focusSurface = $0 { return true } else { return false }
    }
    #expect(
      focusCommands == [.focusSurface(older, tabID: olderTab, surfaceID: olderSurface, input: nil)]
    )
  }

  @Test(.dependencies) func rowLeavesTheQueueOnceItsSurfaceIsFocused() async {
    let worktree = makeWorktree(id: "/tmp/repo/wt-1", name: "wt-1")
    let surface = UUID()
    let store = makeStore(
      worktrees: [worktree],
      awaiting: [(worktree, surface, Date(timeIntervalSince1970: 100))]
    ) { values in
      values.date = .constant(Date(timeIntervalSince1970: 1_000))
      values.continuousClock = ImmediateClock()
      values.terminalClient.saveLayoutsWithAgents = { _ in }
    }
    #expect(store.state.repositories.needsYouRowIDs() == [worktree.id])

    await store.send(.agentPresence(.clearAttention(surfaces: [surface])))
    await store.skipReceivedActions()
    await store.finish()
    #expect(store.state.agentPresence.records.values.allSatisfy { !$0.activity.isAttention })

    #expect(store.state.repositories.needsYouRowIDs().isEmpty)
    #expect(store.state.repositories.needsYouCount == 0)
  }

  // MARK: - Helpers.

  private func makeWorktree(id: String, name: String) -> Worktree {
    Worktree(
      id: WorktreeID(id),
      name: name,
      detail: "detail",
      workingDirectory: URL(fileURLWithPath: id),
      repositoryRootURL: URL(fileURLWithPath: "/tmp/repo"),
    )
  }

  private func makeStore(
    worktrees: [Worktree],
    awaiting: [(Worktree, UUID, Date)] = [],
    withAdditionalDependencies: (inout DependencyValues) -> Void
  ) -> TestStoreOf<AppFeature> {
    let repository = Repository(
      id: "/tmp/repo",
      rootURL: URL(fileURLWithPath: "/tmp/repo"),
      name: "repo",
      worktrees: IdentifiedArray(uniqueElements: worktrees),
    )
    var repositoriesState = RepositoriesFeature.State(reconciledRepositories: [repository])
    repositoriesState.isInitialLoadComplete = true
    var presence = AgentPresenceFeature.State()
    for (worktree, surfaceID, since) in awaiting {
      repositoriesState.sidebarItems[id: worktree.id]?.surfaceIDs = [surfaceID]
      repositoriesState.sidebarItems[id: worktree.id]?.agentSnapshot = .init(
        agents: [.init(agent: .claude, activity: .awaitingInput, since: since)],
        isWorking: false, hasError: false, hasAttention: true, since: since)
      presence.records[.init(agent: .claude, surfaceID: surfaceID)] = .init(
        activity: .awaitingInput, pids: [], activitySince: since)
    }
    var state = AppFeature.State(repositories: repositoriesState, settings: SettingsFeature.State())
    state.agentPresence = presence
    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: { values in
      values.terminalClient.tabExists = { _, _ in true }
      values.terminalClient.surfaceExists = { _, _, _ in true }
      withAdditionalDependencies(&values)
    }
    store.exhaustivity = .off
    return store
  }
}
