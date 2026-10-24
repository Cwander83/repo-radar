import SwiftUI

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

  // Standard group identifier per CHR-77 / CHR-78
  let groupID = "group.com.chriswander.reporadar"

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
  }

  func writeToContainer() {
    guard let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID)
    else {
      statusMessage = "❌ containerURL returned nil for group: \(groupID)"
      return
    }
    containerPath = url.path

    let fileURL = url.appendingPathComponent("spike-payload.json")
    let payload: [String: String] = [
      "message": "Hello from Host App!",
      "timestamp": Date().ISO8601Format(),
    ]

    do {
      let data = try JSONSerialization.data(withJSONObject: payload, options: .prettyPrinted)
      try data.write(to: fileURL, options: .atomic)
      statusMessage = "✅ Successfully wrote to container at \(Date().formatted(date: .omitted, time: .standard))"
    } catch {
      statusMessage = "❌ Write failed: \(error.localizedDescription)"
    }
  }
}
