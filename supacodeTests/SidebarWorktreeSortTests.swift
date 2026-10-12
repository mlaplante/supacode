import Foundation
import Testing

@testable import supacode

struct SidebarWorktreeSortTests {
  @Test func manualIsIdentityAndReorderable() {
    #expect(SidebarWorktreeSort.manual.allowsReordering)
    #expect(
      SidebarWorktreeSort.manual.ordered(
        ["b", "a"], key: { _ in .init(lastFocusedAt: nil, rank: 0, since: nil, branchName: "") }) == ["b", "a"])
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
    let out = SidebarWorktreeSort.agentState.ordered(
      ["idle", "busy", "waitNew", "waitOld", "err"], key: { keys[$0]! })
    #expect(out == ["err", "waitOld", "waitNew", "busy", "idle"])
  }

  @Test func equalKeysKeepInputOrder() {
    let key = SidebarWorktreeSort.Key(lastFocusedAt: nil, rank: 4, since: nil, branchName: "same")
    #expect(SidebarWorktreeSort.agentState.ordered(["z", "a", "m"], key: { _ in key }) == ["z", "a", "m"])
  }

  @Test func sectionRoundTripsSortAndOmitsManual() throws {
    var section = SidebarState.Section()
    let manual = try JSONEncoder().encode(section)
    let manualText = try #require(String(bytes: manual, encoding: .utf8))
    #expect(!manualText.contains("worktreeSort"))
    #expect(try JSONDecoder().decode(SidebarState.Section.self, from: manual).worktreeSort == .manual)
    section.worktreeSort = .agentState
    let data = try JSONEncoder().encode(section)
    #expect(try JSONDecoder().decode(SidebarState.Section.self, from: data).worktreeSort == .agentState)
  }
}
