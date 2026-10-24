import SwiftUI
import RepoRadarCore

@MainActor
final class AppModel: ObservableObject {
  let scheduler: RefreshScheduler?

  init(scheduler: RefreshScheduler? = RefreshScheduler()) {
    self.scheduler = scheduler
    scheduler?.start()
  }
}

@main
struct RepoRadarApp: App {
  @StateObject private var model = AppModel()

  var body: some Scene {
    MenuBarExtra("RepoRadar", systemImage: "radar") {
      if let scheduler = model.scheduler {
        SchedulerMenu(scheduler: scheduler)
      } else {
        Text("App Group unavailable — reinstall/re-sign")
        Divider()
        Button("Quit") {
          NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
      }
    }
  }
}

private struct SchedulerMenu: View {
  @ObservedObject var scheduler: RefreshScheduler

  var body: some View {
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
