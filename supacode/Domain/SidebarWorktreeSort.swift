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

  /// Final tie-break is the input position, so equal keys keep their manual order.
  func ordered<ID>(_ ids: [ID], key: (ID) -> Key) -> [ID] {
    switch self {
    case .manual:
      return ids
    case .recentActivity:
      return Self.sorted(ids, key: key) { lhs, rhs in
        switch (lhs.lastFocusedAt, rhs.lastFocusedAt) {
        case (let left?, let right?) where left != right: return left > right
        case (.some, .none): return true
        case (.none, .some): return false
        default: return Self.nameOrder(lhs.branchName, rhs.branchName)
        }
      }
    case .agentState:
      return Self.sorted(ids, key: key) { lhs, rhs in
        if lhs.rank != rhs.rank { return lhs.rank < rhs.rank }
        switch (lhs.since, rhs.since) {
        case (let left?, let right?) where left != right: return left < right
        case (.some, .none): return true
        case (.none, .some): return false
        default: return Self.nameOrder(lhs.branchName, rhs.branchName)
        }
      }
    }
  }

  private static func sorted<ID>(
    _ ids: [ID],
    key: (ID) -> Key,
    before: (Key, Key) -> Bool
  ) -> [ID] {
    let keyed = ids.enumerated().map { (offset: $0.offset, id: $0.element, key: key($0.element)) }
    return keyed.sorted { lhs, rhs in
      if before(lhs.key, rhs.key) { return true }
      if before(rhs.key, lhs.key) { return false }
      return lhs.offset < rhs.offset
    }.map(\.id)
  }

  /// Strict ordering by name; equal names are "not before" in either direction.
  private static func nameOrder(_ lhs: String, _ rhs: String) -> Bool {
    lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
  }
}
