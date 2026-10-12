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
