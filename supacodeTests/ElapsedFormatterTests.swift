import Foundation
import SwiftUI
import Testing

@testable import supacode

struct ElapsedFormatterTests {
  private let start = Date(timeIntervalSince1970: 0)

  @Test func compactSecondsMinutesHoursDays() {
    #expect(ElapsedFormatter.compact(from: start, to: start.addingTimeInterval(5)) == "5s")
    #expect(ElapsedFormatter.compact(from: start, to: start.addingTimeInterval(65)) == "1m")
    #expect(ElapsedFormatter.compact(from: start, to: start.addingTimeInterval(3_600 * 2 + 60)) == "2h")
    #expect(ElapsedFormatter.compact(from: start, to: start.addingTimeInterval(86_400 * 3)) == "3d")
  }

  @Test func compactClampsNegativeToZero() {
    #expect(ElapsedFormatter.compact(from: start.addingTimeInterval(10), to: start) == "0s")
  }

  @Test func spokenIsMinutesAndSecondsUnderAnHour() {
    #expect(ElapsedFormatter.spoken(from: start, to: start.addingTimeInterval(252)) == "4m 12s")
    #expect(ElapsedFormatter.spoken(from: start, to: start.addingTimeInterval(3_660)) == "1h 1m")
  }

  @Test func spokenDayTierAndBoundaries() {
    #expect(ElapsedFormatter.spoken(from: start, to: start.addingTimeInterval(86_400 * 2 + 3_600 * 3)) == "2d 3h")
    #expect(ElapsedFormatter.spoken(from: start, to: start.addingTimeInterval(59)) == "59s")
    #expect(ElapsedFormatter.spoken(from: start, to: start.addingTimeInterval(60)) == "1m 0s")
    #expect(ElapsedFormatter.spoken(from: start, to: start.addingTimeInterval(3_599)) == "59m 59s")
    #expect(ElapsedFormatter.spoken(from: start, to: start.addingTimeInterval(3_600)) == "1h 0m")
    #expect(ElapsedFormatter.spoken(from: start, to: start.addingTimeInterval(86_399)) == "23h 59m")
    #expect(ElapsedFormatter.spoken(from: start, to: start.addingTimeInterval(86_400)) == "1d 0h")
  }

  @Test func strideFollowsWhenEachFormatChangesText() {
    #expect(ElapsedFormatter.stride(forElapsed: 59, style: .compact) == 1)
    #expect(ElapsedFormatter.stride(forElapsed: 60, style: .compact) == 60)
    #expect(ElapsedFormatter.stride(forElapsed: 3_600, style: .compact) == 3_600)
    #expect(ElapsedFormatter.stride(forElapsed: 86_400, style: .compact) == 86_400)
    #expect(ElapsedFormatter.stride(forElapsed: 3_599, style: .spoken) == 1)
    #expect(ElapsedFormatter.stride(forElapsed: 3_600, style: .spoken) == 60)
    #expect(ElapsedFormatter.stride(forElapsed: 86_400, style: .spoken) == 3_600)
  }

  @Test func compactScheduleTicksEverySecondThenEveryMinute() {
    let since = Date(timeIntervalSinceReferenceDate: 800_000_000.123)
    let schedule = ElapsedSchedule(start: since, style: .compact, isPaused: false)
    let entries = Array(schedule.entries(from: since.addingTimeInterval(58.5), mode: .normal).prefix(4))
    let offsets = entries.map { $0.timeIntervalSince(since) }
    let expected: [TimeInterval] = [58.5, 59.005, 60.005, 120.005]
    #expect(offsets.count == expected.count)
    for (offset, want) in zip(offsets, expected) {
      #expect(abs(offset - want) < 0.000_1)
    }
  }

  @Test func everyTickShowsTheNewTextAtRealEpochMagnitudes() {
    let since = Date(timeIntervalSinceReferenceDate: 812_345_678.9)
    let schedule = ElapsedSchedule(start: since, style: .compact, isPaused: false)
    let texts = schedule.entries(from: since.addingTimeInterval(59.5), mode: .normal)
      .prefix(4)
      .map { ElapsedFormatter.compact(from: since, to: $0) }
    #expect(Array(texts) == ["59s", "1m", "2m", "3m"])
  }

  @Test func spokenScheduleKeepsSecondTicksForTheFirstHour() {
    let since = Date(timeIntervalSinceReferenceDate: 800_000_000)
    let schedule = ElapsedSchedule(start: since, style: .spoken, isPaused: false)
    let texts = schedule.entries(from: since.addingTimeInterval(3_598.5), mode: .normal)
      .prefix(4)
      .map { ElapsedFormatter.spoken(from: since, to: $0) }
    #expect(Array(texts) == ["59m 58s", "59m 59s", "1h 0m", "1h 1m"])
  }

  @Test func pausedScheduleYieldsOneEntry() {
    let since = Date(timeIntervalSinceReferenceDate: 800_000_000)
    let now = since.addingTimeInterval(10)
    let schedule = ElapsedSchedule(start: since, style: .spoken, isPaused: true)
    #expect(Array(schedule.entries(from: now, mode: .normal)) == [now])
  }

  @Test func scheduleBeforeStartTicksFromZero() {
    let since = Date(timeIntervalSinceReferenceDate: 800_000_000)
    let schedule = ElapsedSchedule(start: since, style: .compact, isPaused: false)
    let second = Array(schedule.entries(from: since.addingTimeInterval(-5), mode: .normal).prefix(2))[1]
    #expect(abs(second.timeIntervalSince(since) - 1.005) < 0.000_1)
  }
}
