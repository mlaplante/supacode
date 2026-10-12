import Foundation
import Testing

@testable import supacode

struct SidebarPingCyclingDotTests {
  @Test func gridStartIsSharedAndNeverInTheFuture() {
    let early = Date(timeIntervalSinceReferenceDate: 800_000_000.3)
    let late = Date(timeIntervalSinceReferenceDate: 800_000_001.9)
    #expect(SidebarPingCyclingDot.gridStart(before: early) == SidebarPingCyclingDot.gridStart(before: late))
    #expect(SidebarPingCyclingDot.gridStart(before: early) <= early)

    let insideNudge = Date(timeIntervalSinceReferenceDate: 800_000_000.001)
    #expect(SidebarPingCyclingDot.gridStart(before: insideNudge) <= insideNudge)
  }

  @Test func eachGridTickAdvancesTheColor() {
    let start = SidebarPingCyclingDot.gridStart(before: Date(timeIntervalSinceReferenceDate: 800_000_000.7))
    let indices = (0..<4).map { step in
      SidebarPingCyclingDot.colorIndex(
        for: start.addingTimeInterval(Double(step) * SidebarPingCyclingDot.period), count: 3)
    }
    #expect(indices == [1, 2, 0, 1])
  }
}
