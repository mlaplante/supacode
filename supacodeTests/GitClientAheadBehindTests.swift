import Foundation
import Testing

@testable import SupacodeSettingsShared
@testable import supacode

actor AheadBehindShellCallStore {
  private(set) var calls: [[String]] = []
  func record(_ arguments: [String]) { calls.append(arguments) }
}

struct GitClientAheadBehindTests {
  /// `ShellClient.run` throws `ShellClientError` on a non-zero exit, so the
  /// stub mirrors that instead of returning the failing output.
  private func client(
    store: AheadBehindShellCallStore,
    respond: @escaping @Sendable ([String]) -> ShellOutput
  ) -> GitClient {
    GitClient(
      shell: ShellClient(
        run: { _, arguments, _ in
          await store.record(arguments)
          let output = respond(arguments)
          guard output.exitCode == 0 else {
            throw ShellClientError(
              command: arguments.joined(separator: " "),
              stdout: output.stdout,
              stderr: output.stderr,
              exitCode: output.exitCode
            )
          }
          return output
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

  @Test func nonConflictFailureAbortsAndThrowsFailed() async {
    let store = AheadBehindShellCallStore()
    let client = client(store: store) { args in
      if args.contains("rebase") && !args.contains("--abort") {
        return ShellOutput(stdout: "", stderr: "fatal: invalid upstream 'nope'", exitCode: 128)
      }
      return ShellOutput(stdout: "", stderr: "", exitCode: 0)
    }
    do {
      try await client.rebase(at: URL(fileURLWithPath: "/tmp/wt"), onto: "nope")
      Issue.record("expected throw")
    } catch let error as GitSyncError {
      guard case .failed(let message) = error else {
        Issue.record("expected .failed, got \(error)")
        return
      }
      #expect(message.contains("invalid upstream"))
    } catch {
      Issue.record("unexpected error \(error)")
    }
    let calls = await store.calls
    #expect(calls.contains { $0.contains("rebase") && $0.contains("--abort") })
  }

  @Test func rebaseInProgressThrowsFailedWithoutRebasingOrAborting() async throws {
    let gitDir = FileManager.default.temporaryDirectory
      .appending(path: "sync-in-progress-\(UUID().uuidString)", directoryHint: .isDirectory)
    let marker = gitDir.appending(path: "rebase-merge", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: marker, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: gitDir) }
    let markerPath = marker.path(percentEncoded: false)

    let store = AheadBehindShellCallStore()
    let client = client(store: store) { args in
      if args.contains("rev-parse"), args.last == "rebase-merge" {
        return ShellOutput(stdout: markerPath + "\n", stderr: "", exitCode: 0)
      }
      return ShellOutput(stdout: "", stderr: "", exitCode: 0)
    }
    await #expect(throws: GitSyncError.failed("A rebase or merge is already in progress in this worktree.")) {
      try await client.rebase(at: URL(fileURLWithPath: "/tmp/wt"), onto: "origin/main")
    }
    let calls = await store.calls
    #expect(!calls.contains { $0.contains("rebase") && !$0.contains("rev-parse") })
    #expect(!calls.contains { $0.contains("--abort") })
  }

  @Test func mergeInProgressThrowsFailedWithoutMergingOrAborting() async throws {
    let gitDir = FileManager.default.temporaryDirectory
      .appending(path: "sync-in-progress-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: gitDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: gitDir) }
    let mergeHead = gitDir.appending(path: "MERGE_HEAD")
    try Data("abc\n".utf8).write(to: mergeHead)
    let mergeHeadPath = mergeHead.path(percentEncoded: false)

    let store = AheadBehindShellCallStore()
    let client = client(store: store) { args in
      if args.contains("rev-parse"), args.last == "MERGE_HEAD" {
        return ShellOutput(stdout: mergeHeadPath + "\n", stderr: "", exitCode: 0)
      }
      return ShellOutput(stdout: "", stderr: "", exitCode: 0)
    }
    await #expect(throws: GitSyncError.failed("A rebase or merge is already in progress in this worktree.")) {
      try await client.mergeBase(at: URL(fileURLWithPath: "/tmp/wt"), base: "origin/main")
    }
    let calls = await store.calls
    #expect(!calls.contains { $0.contains("merge") })
    #expect(!calls.contains { $0.contains("--abort") })
  }

  @Test func rebaseSuccessDoesNotAbort() async throws {
    let store = AheadBehindShellCallStore()
    let client = client(store: store) { _ in ShellOutput(stdout: "", stderr: "", exitCode: 0) }
    try await client.rebase(at: URL(fileURLWithPath: "/tmp/wt"), onto: "origin/main")
    let calls = await store.calls
    #expect(!calls.contains { $0.contains("--abort") })
  }
}
