import Foundation
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
}
