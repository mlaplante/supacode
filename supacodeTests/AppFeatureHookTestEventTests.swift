import ComposableArchitecture
import DependenciesTestSupport
import Foundation
import IdentifiedCollections
import Testing

@testable import SupacodeSettingsFeature
@testable import SupacodeSettingsShared
@testable import supacode

@MainActor
struct AppFeatureHookTestEventTests {
  @Test(.dependencies) func opensTabRunningTheHookWhenWorktreeSelected() async {
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
    repositoriesState.selection = .worktree(worktree.id)
    let sent = LockIsolated<[TerminalClient.Command]>([])
    let store = TestStore(
      initialState: AppFeature.State(repositories: repositoriesState, settings: SettingsFeature.State())
    ) {
      AppFeature()
    } withDependencies: {
      $0.terminalClient.send = { command in sent.withValue { $0.append(command) } }
    }
    store.exhaustivity = .off

    await store.send(.settings(.delegate(.sendHookTestEvent(.codex))))
    await store.finish()

    guard case .createTabWithInput(let target, let input, _, _, _, _, _)? = sent.value.first else {
      Issue.record("Expected createTabWithInput, got \(sent.value)")
      return
    }
    #expect(target == worktree)
    #expect(input.contains("event=idle"))
    #expect(input.contains("start=codex"))
    #expect(input.hasSuffix("\n"))
  }

  @Test(.dependencies) func reportsFailureWithoutSelectedWorktree() async {
    let sent = LockIsolated<[TerminalClient.Command]>([])
    let store = TestStore(initialState: AppFeature.State()) {
      AppFeature()
    } withDependencies: {
      $0.terminalClient.send = { command in sent.withValue { $0.append(command) } }
    }
    store.exhaustivity = .off

    await store.send(.settings(.delegate(.sendHookTestEvent(.claude))))
    await store.receive(\.settings.hookTestEventFailed) {
      $0.settings.hookTestFailures = [.claude: "Select a worktree first."]
    }
    #expect(sent.value.isEmpty)
  }
}
