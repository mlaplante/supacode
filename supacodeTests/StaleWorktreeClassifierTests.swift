import Foundation
import Testing

@testable import supacode

struct StaleWorktreeClassifierTests {
  private let now = Date(timeIntervalSince1970: 1_000_000)
  private let day: TimeInterval = 86_400

  private func input(
    _ edit: (inout StaleWorktreeClassifier.Input) -> Void = { _ in }
  ) -> StaleWorktreeClassifier.Input {
    var value = StaleWorktreeClassifier.Input(
      isMainWorktree: false, isPinned: false, isArchived: false, isMissing: false,
      hasOpenPullRequest: false, aheadCount: 1, isTreeClean: true,
      lastFocusedAt: now, createdAt: now)
    edit(&value)
    return value
  }

  private func classify(
    _ edit: (inout StaleWorktreeClassifier.Input) -> Void = { _ in },
    staleAfterDays: Int = 7
  ) -> StaleReason? {
    StaleWorktreeClassifier.classify(input(edit), now: now, staleAfterDays: staleAfterDays)
  }

  @Test func emptyWhenNothingAheadAndCleanPastTheGracePeriod() {
    let aged = now.addingTimeInterval(-StaleWorktreeClassifier.emptyGracePeriod)
    #expect(
      classify {
        $0.aheadCount = 0
        $0.lastFocusedAt = aged
      } == .empty)
  }

  @Test func justCreatedCleanWorktreeIsNotEmpty() {
    #expect(classify { $0.aheadCount = 0 } == nil)
    let almost = now.addingTimeInterval(-StaleWorktreeClassifier.emptyGracePeriod + 1)
    #expect(
      classify {
        $0.aheadCount = 0
        $0.lastFocusedAt = almost
      } == nil)
  }

  @Test func emptyFallsBackToCreatedAtAndNeedsAReferenceDate() {
    let aged = now.addingTimeInterval(-day * 2)
    #expect(
      classify {
        $0.aheadCount = 0
        $0.lastFocusedAt = nil
        $0.createdAt = aged
      } == .empty)
    #expect(
      classify {
        $0.aheadCount = 0
        $0.lastFocusedAt = nil
        $0.createdAt = nil
      } == nil)
  }

  @Test func liveAgentOrSelectionIsNeverStale() {
    let old = now.addingTimeInterval(-day * 30)
    #expect(
      classify {
        $0.hasLiveAgent = true
        $0.lastFocusedAt = old
        $0.aheadCount = 0
      } == nil)
    #expect(
      classify {
        $0.isSelected = true
        $0.lastFocusedAt = old
        $0.aheadCount = 0
      } == nil)
  }

  @Test func notEmptyWhenDirty() {
    #expect(
      classify {
        $0.aheadCount = 0
        $0.isTreeClean = false
        $0.lastFocusedAt = now.addingTimeInterval(-day * 2)
      } == nil)
  }

  @Test func unknownCountsAreNeverEmpty() {
    #expect(classify { $0.aheadCount = nil; $0.lastFocusedAt = now.addingTimeInterval(-day * 2) } == nil)
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
