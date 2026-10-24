import SwiftUI
import WidgetKit

@main
struct HostApp: App {
  var body: some Scene {
    WindowGroup {
      ContentView()
    }
  }
}

struct ContentView: View {
  @State private var statusMessage: String = "Ready"
  @State private var containerPath: String = ""
  @State private var writeCount: Int = 0

  // Team-prefixed group identifier required on macOS for free personal team
  let groupID = "7P5RMM8JP7.com.chriswander.reporadar"

  var body: some View {
    VStack(spacing: 16) {
      Text("App Group + Widget Spike")
        .font(.title)

      Text("Group ID: \(groupID)")
        .font(.subheadline)
        .foregroundColor(.secondary)

      Button("Write to App Group Container") {
        writeToContainer()
      }
      .buttonStyle(.borderedProminent)

      Text(statusMessage)
        .font(.body)

      if !containerPath.isEmpty {
        Text("Path: \(containerPath)")
          .font(.caption)
          .textSelection(.enabled)
      }
    }
    .padding(30)
    .frame(minWidth: 440, minHeight: 260)
    .onAppear {
      writeToContainer()
    }
  }

  func writeToContainer() {
    guard let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID)
    else {
      statusMessage = "❌ containerURL returned nil for group: \(groupID)"
      return
    }
    containerPath = url.path

    writeCount += 1
    let fileURL = url.appendingPathComponent("spike-payload.json")
    let payload: [String: String] = [
      "message": "Hello from Host App! (#\(writeCount))",
      "timestamp": Date().ISO8601Format(),
    ]

    do {
      let data = try JSONSerialization.data(withJSONObject: payload, options: .prettyPrinted)
      try data.write(to: fileURL, options: .atomic)
      WidgetCenter.shared.reloadAllTimelines()
      statusMessage = "✅ Successfully wrote (#\(writeCount)) to container at \(Date().formatted(date: .omitted, time: .standard))"
    } catch {
      statusMessage = "❌ Write failed: \(error.localizedDescription)"
    }
  }
}
