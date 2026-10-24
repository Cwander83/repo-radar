import SwiftUI
import WidgetKit

struct Provider: TimelineProvider {
  // Team-prefixed group identifier required on macOS for free personal team
  let groupID = "7P5RMM8JP7.com.chriswander.reporadar"

  func placeholder(in context: Context) -> SimpleEntry {
    SimpleEntry(date: Date(), message: "Placeholder", timestamp: "")
  }

  func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> Void) {
    let entry = readEntry()
    completion(entry)
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<SimpleEntry>) -> Void) {
    let entry = readEntry()
    let timeline = Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(60)))
    completion(timeline)
  }

  private func readEntry() -> SimpleEntry {
    guard let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID)
    else {
      return SimpleEntry(date: Date(), message: "❌ containerURL is nil", timestamp: groupID)
    }
    let fileURL = url.appendingPathComponent("spike-payload.json")
    do {
      let data = try Data(contentsOf: fileURL)
      guard let json = try JSONSerialization.jsonObject(with: data) as? [String: String] else {
        return SimpleEntry(
          date: Date(), message: "❌ Invalid JSON", timestamp: "\(data.count) bytes")
      }
      return SimpleEntry(
        date: Date(),
        message: json["message"] ?? "Unknown",
        timestamp: json["timestamp"] ?? ""
      )
    } catch {
      return SimpleEntry(
        date: Date(), message: "❌ \(error.localizedDescription)", timestamp: fileURL.path)
    }
  }
}

struct SimpleEntry: TimelineEntry {
  let date: Date
  let message: String
  let timestamp: String
}

struct SpikeWidgetEntryView: View {
  var entry: Provider.Entry

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("RepoRadar Spike")
        .font(.headline)
      Text(entry.message)
        .font(.subheadline)
      if !entry.timestamp.isEmpty {
        Text("Host time: \(entry.timestamp)")
          .font(.caption2)
          .foregroundColor(.secondary)
      }
      Link(destination: URL(string: "https://github.com/Cwander83/repo-radar")!) {
        Text("Open GitHub ↗")
          .font(.caption)
          .foregroundColor(.blue)
      }
    }
    .padding()
  }
}

@main
struct SpikeWidget: Widget {
  let kind: String = "SpikeWidget"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: Provider()) { entry in
      SpikeWidgetEntryView(entry: entry)
        .containerBackground(.fill.tertiary, for: .widget)
    }
    .configurationDisplayName("Spike Widget")
    .description("Tests App Group sharing on macOS.")
    .supportedFamilies([.systemSmall, .systemMedium])
  }
}
