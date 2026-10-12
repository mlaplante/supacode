import Foundation
import Testing

@testable import supacode

struct StaleWorktreeClassifierTests {
  private let now = Date(timeIntervalSince1970: 1_000_000)
  private func input(_ edit: (inout StaleWorktreeClassifier.Input) -> Void = { _ in }) -> StaleWorktreeClassifier.Input {
    var i = StaleWorktreeClassifier.Input(
      isMainWorktree: false, isPinned: false, isArchived: false, isMissing: false,
      hasOpenPullRequest: false, aheadCount: 1, isTreeClean: true,
      lastFocusedAt: now, createdAt: now)
    edit(&i)
    return i
  }

  @Test func emptyWhenNothingAheadAndClean() {
    let r = StaleWorktreeClassifier.classify(input { $0.aheadCount = 0 }, now: now, staleAfterDays: 7)
    #expect(r == .empty)
  }

  @Test func notEmptyWhenDirty() {
    let r = StaleWorktreeClassifier.classify(input { $0.aheadCount = 0; $0.isTreeClean = false }, now: now, staleAfterDays: 7)
    #expect(r == nil)
  }

  @Test func unknownCountsAreNeverEmpty() {
    let r = StaleWorktreeClassifier.classify(input { $0.aheadCount = nil }, now: now, staleAfterDays: 7)
    #expect(r == nil)
  }

  @Test func idleAfterThreshold() {
    let old = now.addingTimeInterval(-86_400 * 9)
    let r = StaleWorktreeClassifier.classify(input { $0.lastFocusedAt = old }, now: now, staleAfterDays: 7)
    #expect(r == .idle(days: 9))
  }

  @Test func idleFallsBackToCreatedAtWhenNeverFocused() {
    let r = StaleWorktreeClassifier.classify(
      input { $0.lastFocusedAt = nil; $0.createdAt = now.addingTimeInterval(-86_400 * 8) }, now: now, staleAfterDays: 7)
    #expect(r == .idle(days: 8))
  }

  @Test func zeroDaysDisablesIdleRuleOnly() {
    let old = now.addingTimeInterval(-86_400 * 30)
    #expect(StaleWorktreeClassifier.classify(input { $0.lastFocusedAt = old }, now: now, staleAfterDays: 0) == nil)
    #expect(StaleWorktreeClassifier.classify(input { $0.lastFocusedAt = old; $0.aheadCount = 0 }, now: now, staleAfterDays: 0) == .empty)
  }

  @Test func emptyWinsOverIdle() {
    let old = now.addingTimeInterval(-86_400 * 30)
    #expect(StaleWorktreeClassifier.classify(input { $0.lastFocusedAt = old; $0.aheadCount = 0 }, now: now, staleAfterDays: 7) == .empty)
  }

  @Test func exclusionsNeverStale() {
    let old = now.addingTimeInterval(-86_400 * 30)
    for edit in [
      { (i: inout StaleWorktreeClassifier.Input) in i.isMainWorktree = true },
      { $0.isPinned = true }, { $0.isArchived = true }, { $0.isMissing = true },
    ] {
      #expect(StaleWorktreeClassifier.classify(input { edit(&$0); $0.lastFocusedAt = old; $0.aheadCount = 0 }, now: now, staleAfterDays: 7) == nil)
    }
  }

  @Test func openPullRequestNeverStale() {
    let old = now.addingTimeInterval(-86_400 * 30)
    let r = StaleWorktreeClassifier.classify(input { $0.hasOpenPullRequest = true; $0.lastFocusedAt = old; $0.aheadCount = 0 }, now: now, staleAfterDays: 7)
    #expect(r == nil)
  }
}
