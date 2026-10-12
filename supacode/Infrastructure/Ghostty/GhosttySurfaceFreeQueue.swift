import Foundation

/// Spreads deferred `ghostty_surface_free` calls over successive run-loop
/// passes, one per pass.
///
/// A free joins the surface's renderer, IO and search threads and tears down
/// its Metal state, so it costs tens of milliseconds. A memory-pressure sweep,
/// a bulk prune, or closing a worktree with many tabs used to queue every
/// free onto the same turn, and the main thread then served none of the
/// user's events until the whole batch had joined. Draining one per pass
/// keeps each gap short and lets input and rendering interleave.
@MainActor
enum GhosttySurfaceFreeQueue {
  private static var pending: [@MainActor () -> Void] = []
  private static var drainScheduled = false

  /// Schedules the next drain. The live value hops through a main-queue timer
  /// so the run loop services events between frees (a plain `async` enqueued
  /// from inside a main-queue drain runs in the same pass). Tests swap in a
  /// trampoline they fire by hand.
  static var scheduleDrain: (@escaping @MainActor () -> Void) -> Void = { drain in
    // The main queue, not a `Task`: a free must run outside any reducer's
    // inherited task-local scope, where an isolated-deinit release it triggers
    // can abort as an invalid free.
    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(1)) {
      MainActor.assumeIsolated { drain() }
    }
  }

  /// Number of frees still waiting. Test seam.
  static var pendingCount: Int { pending.count }

  /// Runs every queued free now and disarms the scheduled drain. For teardown
  /// paths that must not leave surfaces half-freed, and for tests that need a
  /// known-empty queue.
  static func drainAllNow() {
    drainScheduled = false
    while !pending.isEmpty {
      pending.removeFirst()()
    }
  }

  static func enqueue(_ free: @escaping @MainActor () -> Void) {
    pending.append(free)
    scheduleDrainIfNeeded()
  }

  private static func scheduleDrainIfNeeded() {
    guard !drainScheduled, !pending.isEmpty else { return }
    drainScheduled = true
    scheduleDrain {
      drainScheduled = false
      guard !pending.isEmpty else { return }
      let next = pending.removeFirst()
      next()
      scheduleDrainIfNeeded()
    }
  }
}
