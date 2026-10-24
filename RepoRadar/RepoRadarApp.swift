import SwiftUI
import RepoRadarCore

@main
struct RepoRadarApp: App {
  @StateObject private var scheduler: RefreshScheduler

  public init() {
    let resolved = RefreshScheduler() ?? RefreshScheduler(
      service: RepoRadarService(
        configStore: ConfigStore(userDefaults: UserDefaults.standard),
        tokenStore: InMemoryTokenStore(),
        snapshotStore: SnapshotStore(
          fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("snapshot.json")
        )
      )
    )
    _scheduler = StateObject(wrappedValue: resolved)
    resolved.start()
  }

  var body: some Scene {
    MenuBarExtra("RepoRadar", systemImage: "radar") {
      Text("RepoRadar: \(scheduler.status.displayTitle)")
      if let lastUpdated = scheduler.lastUpdated {
        Text("Updated: \(lastUpdated.formatted(date: .omitted, time: .standard))")
      }
      Divider()
      Button("Refresh now") {
        Task {
          try? await scheduler.refreshNow()
        }
      }
      .disabled(scheduler.isRefreshing)
      Divider()
      Button("Quit") {
        NSApplication.shared.terminate(nil)
      }
      .keyboardShortcut("q")
    }
  }
}
