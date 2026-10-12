import ComposableArchitecture
import Foundation
import IdentifiedCollections
import SupacodeSettingsShared
import Testing

@testable import supacode

/// Per-leaf ticks (agent snapshots, terminal projections, line-change loads)
/// fire once per worktree per change. Each used to pay a full sidebar and
/// menu-bar rebuild on the main actor; now they park their structure bits and
/// one flush per `structureCoalesceWindow` rebuilds for all of them.
@MainActor
struct SidebarStructureCoalescingTests {
  @Test func tickParksStructureRebuildUntilTheWindowFlushes() async {
    let (state, worktrees) = makeState()
    let clock = TestClock()
    let store = TestStore(initialState: state) {
      RepositoriesFeature()
    } withDependencies: {
      $0.continuousClock = clock
    }
    store.exhaustivity = .off
    let structureBefore = store.state.sidebarStructure

    await store.send(
      .sidebarItems(.element(id: worktrees[0].id, action: .agentSnapshotChanged(.init(isWorking: true))))
    )
    #expect(store.state.pendingCoalescedInvalidations == .sidebarStructure)
    #expect(store.state.sidebarStructure == structureBefore, "The rebuild must wait for the window")

    await clock.advance(by: RepositoriesFeature.structureCoalesceWindow)
    await store.receive(\.flushCoalescedCacheRecomputes)
    #expect(store.state.pendingCoalescedInvalidations.isEmpty)

    var converged = store.state
    converged.applyCacheRecomputes(.allSidebar)
    #expect(store.state.sidebarStructure == converged.sidebarStructure)
    #expect(store.state.menuBarSectionsCache == converged.menuBarSectionsCache)
    await store.finish()
  }

  @Test func burstAcrossWorktreesSchedulesOneFlush() async {
    let (state, worktrees) = makeState()
    let clock = TestClock()
    let store = TestStore(initialState: state) {
      RepositoriesFeature()
    } withDependencies: {
      $0.continuousClock = clock
    }
    store.exhaustivity = .off

    for worktree in worktrees {
      await store.send(
        .sidebarItems(.element(id: worktree.id, action: .agentSnapshotChanged(.init(isWorking: true))))
      )
      await store.send(
        .sidebarItems(
          .element(
            id: worktree.id,
            action: .terminalProjectionChanged(
              WorktreeRowProjection(
                surfaceIDs: [UUID()],
                isProgressBusy: true,
                hasUnseenNotifications: false,
                notifications: [],
                runningScripts: []
              )
            )
          )
        )
      )
    }
    #expect(store.state.pendingCoalescedInvalidations == .coalescable)

    await clock.advance(by: RepositoriesFeature.structureCoalesceWindow)
    await store.receive(\.flushCoalescedCacheRecomputes)
    // `finish()` fails if a second flush were still queued.
    await store.finish()
    #expect(store.state.pendingCoalescedInvalidations.isEmpty)
  }

  @Test func selectionSliceStillRecomputesSynchronouslyOnATick() async {
    var (state, worktrees) = makeState()
    state.selection = .worktree(worktrees[0].id)
    state.reconcileSidebarForTesting()
    let clock = TestClock()
    let store = TestStore(initialState: state) {
      RepositoriesFeature()
    } withDependencies: {
      $0.continuousClock = clock
    }
    store.exhaustivity = .off
    let scriptID = UUID()

    await store.send(
      .sidebarItems(
        .element(
          id: worktrees[0].id,
          action: .terminalProjectionChanged(
            WorktreeRowProjection(
              surfaceIDs: [],
              isProgressBusy: false,
              hasUnseenNotifications: false,
              notifications: [],
              runningScripts: [.init(id: scriptID, tint: .blue)]
            )
          )
        )
      )
    )
    // Run/Stop in the toolbar reads this; it must not lag the window.
    #expect(store.state.selectedWorktreeSlice?.runningScripts.map(\.id) == [scriptID])
    await clock.advance(by: RepositoriesFeature.structureCoalesceWindow)
    await store.finish()
  }

  @Test func userDrivenActionsRecomputeSynchronously() async {
    let (state, worktrees) = makeState()
    let store = TestStore(initialState: state) {
      RepositoriesFeature()
    }
    store.exhaustivity = .off

    await store.send(
      .sidebarItems(.element(id: worktrees[0].id, action: .lifecycleChanged(.pending)))
    )
    #expect(store.state.pendingCoalescedInvalidations.isEmpty)
    var converged = store.state
    converged.applyCacheRecomputes(.allSidebar)
    #expect(store.state.sidebarStructure == converged.sidebarStructure)
  }

  @Test func onlyPerLeafTicksCoalesce() {
    let id = WorktreeID("/tmp/repo/wt")
    #expect(
      RepositoriesFeature.Action.sidebarItems(.element(id: id, action: .agentSnapshotChanged(.init())))
        .coalescesStructureRecompute
    )
    #expect(
      RepositoriesFeature.Action.worktreeLineChangesLoaded(worktreeID: id, added: 1, removed: 0)
        .coalescesStructureRecompute)
    #expect(
      !RepositoriesFeature.Action.sidebarItems(.element(id: id, action: .lifecycleChanged(.pending)))
        .coalescesStructureRecompute)
    #expect(!RepositoriesFeature.Action.consumeTerminalFocus(id).coalescesStructureRecompute)
    #expect(RepositoriesFeature.Action.flushCoalescedCacheRecomputes.cacheInvalidations.isEmpty)
  }

  // MARK: - Helpers.

  private func makeState() -> (RepositoriesFeature.State, [Worktree]) {
    let repoRoot = URL(fileURLWithPath: "/tmp/repo")
    let worktrees = ["/tmp/repo/wt-a", "/tmp/repo/wt-b", "/tmp/repo/wt-c"].map { path in
      Worktree(
        id: WorktreeID(path),
        name: URL(fileURLWithPath: path).lastPathComponent,
        detail: "",
        workingDirectory: URL(fileURLWithPath: path),
        repositoryRootURL: repoRoot
      )
    }
    let repository = Repository(
      id: RepositoryID(repoRoot.path(percentEncoded: false)),
      rootURL: repoRoot,
      name: "repo",
      worktrees: IdentifiedArray(uniqueElements: worktrees)
    )
    var state = RepositoriesFeature.State(reconciledRepositories: [repository])
    state.isInitialLoadComplete = true
    state.reconcileSidebarForTesting()
    return (state, worktrees)
  }
}
