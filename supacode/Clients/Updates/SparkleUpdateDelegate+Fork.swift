import Foundation
import Sparkle

// Personal fork: never check upstream's appcast. An upstream release would
// replace this build with the licensed one. Pull updates via git instead.
extension SparkleUpdateDelegate {
  nonisolated func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
    throw NSError(
      domain: "app.supabit.supacode.fork", code: 1,
      userInfo: [
        NSLocalizedDescriptionKey: "Updates are disabled in this build.",
        NSLocalizedRecoverySuggestionErrorKey:
          "This is a personal fork. Merge upstream with git and rebuild instead.",
      ]
    )
  }
}
