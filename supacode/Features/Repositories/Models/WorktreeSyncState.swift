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

extension GitSyncError {
  /// Alert-friendly text. `.failed` carries the raw `stdout:/stderr:` dump from
  /// the wrapper; prefer the first non-empty stderr line when present.
  var readableMessage: String {
    switch self {
    case .conflict(let operation):
      return "\(operation.verb) stopped on conflicts. The \(operation.rawValue) was aborted and your branch is unchanged."
    case .failed(let raw):
      return Self.firstStderrLine(in: raw) ?? raw
    }
  }

  private static func firstStderrLine(in raw: String) -> String? {
    guard let range = raw.range(of: "stderr:") else { return nil }
    return raw[range.upperBound...]
      .split(whereSeparator: \.isNewline)
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .first { !$0.isEmpty }
  }
}
