import Foundation
import Testing

@testable import supacode

struct StaleWorktreeClassifierTests {
  private let now = Date(timeIntervalSince1970: 1_000_000)
  private let day: TimeInterval = 86_400

  private func input(
    _ edit: (inout StaleWorktreeClassifier.Input) -> Void = { _ in }
  ) -> StaleWorktreeClassifier.Input {
    var i = StaleWorktreeClassifier.Input(
      isMainWorktree: false, isPinned: false, isArchived: false, isMissing: false,
      hasOpenPullRequest: false, aheadCount: 1, isTreeClean: true,
      lastFocusedAt: now, createdAt: now)
    edit(&i)
    return i
  }

  private func classify(
    _ edit: (inout StaleWorktreeClassifier.Input) -> Void = { _ in },
    staleAfterDays: Int = 7
  ) -> StaleReason? {
    StaleWorktreeClassifier.classify(input(edit), now: now, staleAfterDays: staleAfterDays)
  }

  @Test func emptyWhenNothingAheadAndClean() {
    #expect(classify { $0.aheadCount = 0 } == .empty)
  }

  @Test func notEmptyWhenDirty() {
    #expect(
      classify {
        $0.aheadCount = 0
        $0.isTreeClean = false
      } == nil)
  }

  @Test func unknownCountsAreNeverEmpty() {
    #expect(classify { $0.aheadCount = nil } == nil)
  }

  @Test func idleAfterThreshold() {
    let old = now.addingTimeInterval(-day * 9)
    #expect(classify { $0.lastFocusedAt = old } == .idle(days: 9))
  }

  @Test func idleFallsBackToCreatedAtWhenNeverFocused() {
    let created = now.addingTimeInterval(-day * 8)
    #expect(
      classify {
        $0.lastFocusedAt = nil
        $0.createdAt = created
      } == .idle(days: 8))
  }

  @Test func zeroDaysDisablesIdleRuleOnly() {
    let old = now.addingTimeInterval(-day * 30)
    #expect(classify({ $0.lastFocusedAt = old }, staleAfterDays: 0) == nil)
    #expect(
      classify(
        {
          $0.lastFocusedAt = old
          $0.aheadCount = 0
        }, staleAfterDays: 0) == .empty)
  }

  @Test func emptyWinsOverIdle() {
    let old = now.addingTimeInterval(-day * 30)
    #expect(
      classify {
        $0.lastFocusedAt = old
        $0.aheadCount = 0
      } == .empty)
  }

  @Test func exclusionsNeverStale() {
    let old = now.addingTimeInterval(-day * 30)
    let exclusions: [(inout StaleWorktreeClassifier.Input) -> Void] = [
      { $0.isMainWorktree = true },
      { $0.isPinned = true },
      { $0.isArchived = true },
      { $0.isMissing = true },
    ]
    for exclusion in exclusions {
      #expect(
        classify {
          exclusion(&$0)
          $0.lastFocusedAt = old
          $0.aheadCount = 0
        } == nil)
    }
  }

  @Test func openPullRequestNeverStale() {
    let old = now.addingTimeInterval(-day * 30)
    #expect(
      classify {
        $0.hasOpenPullRequest = true
        $0.lastFocusedAt = old
        $0.aheadCount = 0
      } == nil)
  }
}
