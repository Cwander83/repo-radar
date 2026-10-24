import SwiftUI
import WidgetKit
import RepoRadarCore

struct Provider: TimelineProvider {
  func placeholder(in context: Context) -> SimpleEntry {
    SimpleEntry(date: Date())
  }

  func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> Void) {
    completion(SimpleEntry(date: Date()))
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<SimpleEntry>) -> Void) {
    let timeline = Timeline(entries: [SimpleEntry(date: Date())], policy: .atEnd)
    completion(timeline)
  }
}

struct SimpleEntry: TimelineEntry {
  let date: Date
}

struct RepoRadarWidgetEntryView: View {
  var entry: Provider.Entry

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Label("RepoRadar", systemImage: "radar")
        .font(.headline)
      Text("Snapshot empty")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .containerBackground(.fill.tertiary, for: .widget)
  }
}

@main
struct RepoRadarWidget: Widget {
  let kind: String = "RepoRadarWidget"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: Provider()) { entry in
      RepoRadarWidgetEntryView(entry: entry)
    }
    .configurationDisplayName("RepoRadar")
    .description("GitHub status at a glance.")
    .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
  }
}
