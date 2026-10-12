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

/// Pure rule. A live agent or the selected worktree is never stale. Unknown counts
/// (`aheadCount == nil`, `isTreeClean == nil`) never produce `empty`; a missing probe
/// must not look like a verdict.
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
    /// An agent is running in the worktree right now.
    var hasLiveAgent = false
    /// The user is looking at this worktree.
    var isSelected = false
  }

  /// A clean, zero-ahead worktree is only `empty` once it is this old (since last
  /// focus, else creation). A just-created worktree is always clean and zero-ahead.
  static let emptyGracePeriod: TimeInterval = 86_400

  static func classify(_ input: Input, now: Date, staleAfterDays: Int) -> StaleReason? {
    if input.isMainWorktree || input.isPinned || input.isArchived || input.isMissing || input.hasOpenPullRequest
      || input.hasLiveAgent || input.isSelected
    {
      return nil
    }
    guard let reference = input.lastFocusedAt ?? input.createdAt else { return nil }
    if input.aheadCount == 0, input.isTreeClean == true, now.timeIntervalSince(reference) >= emptyGracePeriod {
      return .empty
    }
    guard staleAfterDays > 0 else { return nil }
    let days = Int(now.timeIntervalSince(reference) / 86_400)
    return days >= staleAfterDays ? .idle(days: days) : nil
  }
}
