import Foundation
import Testing

@testable import supacode

/// Deferred surface frees drain one per scheduled pass, so a burst from a
/// memory-pressure sweep or a bulk prune never blocks a single turn for the
/// whole batch.
@MainActor
struct GhosttySurfaceFreeQueueTests {
  @Test func drainsOneFreePerScheduledPass() {
    let previousScheduler = GhosttySurfaceFreeQueue.scheduleDrain
    defer { GhosttySurfaceFreeQueue.scheduleDrain = previousScheduler }
    // Other suites in this process may have armed the live drain; start clean.
    GhosttySurfaceFreeQueue.drainAllNow()
    var scheduled: [@MainActor () -> Void] = []
    GhosttySurfaceFreeQueue.scheduleDrain = { scheduled.append($0) }
    let baseline = 0

    var ran: [Int] = []
    for index in 0..<3 {
      GhosttySurfaceFreeQueue.enqueue { ran.append(index) }
    }
    #expect(GhosttySurfaceFreeQueue.pendingCount == baseline + 3)
    // A burst arms exactly one drain, however many frees it queued.
    #expect(scheduled.count == 1)

    var passes = 0
    while !scheduled.isEmpty, passes < baseline + 3 {
      let drain = scheduled.removeFirst()
      drain()
      passes += 1
      // Each pass frees one surface and arms at most one further pass.
      #expect(scheduled.count <= 1)
    }
    #expect(ran == [0, 1, 2])
    #expect(GhosttySurfaceFreeQueue.pendingCount == 0)
    #expect(scheduled.isEmpty)
  }
}
