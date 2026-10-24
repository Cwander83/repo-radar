import SwiftUI
import RepoRadarCore

@main
struct RepoRadarApp: App {
  var body: some Scene {
    MenuBarExtra("RepoRadar", systemImage: "radar") {
      Text("RepoRadar")
      Divider()
      Button("Quit") {
        NSApplication.shared.terminate(nil)
      }
      .keyboardShortcut("q")
    }
  }
}
