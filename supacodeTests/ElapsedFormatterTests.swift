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
}
