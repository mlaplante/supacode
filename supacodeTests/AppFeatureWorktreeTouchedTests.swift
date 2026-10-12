import ComposableArchitecture
import DependenciesTestSupport
import Foundation
import IdentifiedCollections
import OrderedCollections
import Testing

@testable import SupacodeSettingsFeature
@testable import SupacodeSettingsShared
@testable import supacode

@MainActor
struct AppFeatureWorktreeTouchedTests {
  private let now = Date(timeIntervalSince1970: 7_000)

  private func makeStore(surfaceID: UUID) -> (TestStoreOf<AppFeature>, Worktree) {
    let rootURL = URL(fileURLWithPath: "/tmp/repo")
    let worktree = Worktree(
      id: "/tmp/repo/wt-feature",
      name: "feature",
      detail: "",
      workingDirectory: URL(fileURLWithPath: "/tmp/repo/wt-feature"),
      repositoryRootURL: rootURL
    )
    let repository = Repository(
      id: RepositoryID(rootURL.path(percentEncoded: false)),
      rootURL: rootURL,
      name: "repo",
      worktrees: IdentifiedArray(uniqueElements: [worktree])
    )
    var repositoriesState = RepositoriesFeature.State(reconciledRepositories: [repository])
    repositoriesState.sidebarItems[id: worktree.id]?.surfaceIDs = [surfaceID]
    repositoriesState.$sidebar.withLock { sidebar in
      sidebar.sections[repository.id] = .init(
        buckets: [.unpinned: .init(items: [worktree.id: .init()])]
      )
    }
    let appState = AppFeature.State(
      repositories: repositoriesState,
      settings: SettingsFeature.State()
    )
    let store = TestStore(initialState: appState) {
      AppFeature()
    } withDependencies: {
      $0.date = .constant(now)
      $0.continuousClock = ImmediateClock()
      $0.sidebarStructureAutoRecompute = false
      $0.terminalClient.saveLayoutsWithAgents = { _ in }
      $0.terminalClient.send = { _ in }
    }
    store.exhaustivity = .off
    return (store, worktree)
  }

  private func hookEvent(_ name: String, surfaceID: UUID) -> AgentHookEvent {
    AgentHookEvent(agent: "claude", event: name, surfaceID: surfaceID, pid: 42)
  }

  @Test(.dependencies) func busyHookEventTouchesTheSurfacesWorktree() async {
    let surfaceID = UUID()
    let (store, worktree) = makeStore(surfaceID: surfaceID)
    await store.send(.terminalEvent(.agentHookEventReceived(hookEvent("busy", surfaceID: surfaceID))))
    await store.receive(\.repositories.worktreeTouched, worktree.id)
    #expect(store.state.repositories.sidebar.lastFocusedAt(for: worktree.id) == now)
  }

  @Test(.dependencies) func sessionStartHookEventTouchesTheSurfacesWorktree() async {
    let surfaceID = UUID()
    let (store, worktree) = makeStore(surfaceID: surfaceID)
    await store.send(
      .terminalEvent(.agentHookEventReceived(hookEvent("session_start", surfaceID: surfaceID)))
    )
    await store.receive(\.repositories.worktreeTouched, worktree.id)
    #expect(store.state.repositories.sidebar.lastFocusedAt(for: worktree.id) == now)
  }

  @Test(.dependencies) func idleHookEventDoesNotTouch() async {
    let surfaceID = UUID()
    let (store, worktree) = makeStore(surfaceID: surfaceID)
    await store.send(.terminalEvent(.agentHookEventReceived(hookEvent("idle", surfaceID: surfaceID))))
    await store.finish()
    #expect(store.state.repositories.sidebar.lastFocusedAt(for: worktree.id) == nil)
  }

  @Test(.dependencies) func hookEventForUnknownSurfaceDoesNotTouch() async {
    let (store, worktree) = makeStore(surfaceID: UUID())
    await store.send(.terminalEvent(.agentHookEventReceived(hookEvent("busy", surfaceID: UUID()))))
    await store.finish()
    #expect(store.state.repositories.sidebar.lastFocusedAt(for: worktree.id) == nil)
  }
}
