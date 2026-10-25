import SwiftUI
import WidgetKit
import RepoRadarCore

/// Timeline provider that reads the snapshot from the shared App Group container.
/// Performs zero network calls inside the widget extension.
public struct Provider: TimelineProvider {
  private let loader: WidgetTimelineLoader

  public init(loader: WidgetTimelineLoader = WidgetTimelineLoader()) {
    self.loader = loader
  }

  public func placeholder(in context: Context) -> RepoRadarWidgetEntry {
    RepoRadarWidgetEntry.previewAllClear
  }

  public func getSnapshot(in context: Context, completion: @escaping (RepoRadarWidgetEntry) -> Void) {
    if context.isPreview {
      completion(RepoRadarWidgetEntry.previewData)
    } else {
      completion(loader.loadEntry())
    }
  }

  public func getTimeline(in context: Context, completion: @escaping (Timeline<RepoRadarWidgetEntry>) -> Void) {
    let entry = loader.loadEntry()
    let nextRefresh = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date().addingTimeInterval(900)
    let timeline = Timeline(entries: [entry], policy: .after(nextRefresh))
    completion(timeline)
  }
}

/// Root widget entry view routing to appropriate state presentations.
public struct RepoRadarWidgetEntryView: View {
  public let entry: RepoRadarWidgetEntry

  public init(entry: RepoRadarWidgetEntry) {
    self.entry = entry
  }

  public var body: some View {
    Group {
      switch entry.state {
      case .firstRun:
        FirstRunWidgetView()

      case .noRepos:
        NoReposWidgetView()

      case .tokenError(let detail):
        TokenErrorWidgetView(detail: detail)

      case .error(let detail):
        ErrorWidgetView(detail: detail)

      case .allClear(let snapshot):
        AllClearWidgetView(snapshot: snapshot)

      case .data(let snapshot):
        DataWidgetView(snapshot: snapshot, isDimmed: false, footerText: nil)

      case .offline(let snapshot, let detail):
        if let snapshot {
          DataWidgetView(snapshot: snapshot, isDimmed: true, footerText: detail ?? "Offline · Showing cached data")
        } else {
          OfflineEmptyWidgetView(detail: detail)
        }

      case .rateLimited(let snapshot, let resetAt, let detail):
        if let snapshot {
          DataWidgetView(
            snapshot: snapshot,
            isDimmed: true,
            footerText: rateLimitFooter(resetAt: resetAt, detail: detail)
          )
        } else {
          RateLimitedEmptyWidgetView(resetAt: resetAt)
        }
      }
    }
    .containerBackground(.fill.tertiary, for: .widget)
  }

  private func rateLimitFooter(resetAt: Date?, detail: String?) -> String {
    if let resetAt {
      let formatter = DateFormatter()
      formatter.timeStyle = .short
      return "Rate limited · Resets at \(formatter.string(from: resetAt))"
    }
    return detail ?? "Rate limited · Showing cached data"
  }
}

// MARK: - State Subviews

private struct FirstRunWidgetView: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 6) {
        Image(systemName: "radar")
          .foregroundStyle(Color.indigo)
        Text("Repo Radar")
          .font(.headline)
      }

      Spacer()

      Text("Welcome to Repo Radar")
        .font(.subheadline.weight(.semibold))

      Text("Open the menu bar app to configure GitHub access.")
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)

      Spacer()
    }
  }
}

private struct NoReposWidgetView: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 6) {
        Image(systemName: "book.closed")
          .foregroundStyle(Color.indigo)
        Text("No Repositories")
          .font(.headline)
      }

      Spacer()

      Text("Add repositories to watch in Settings to see open PRs, CI, and stale branches.")
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)

      Spacer()
    }
  }
}

private struct TokenErrorWidgetView: View {
  let detail: String

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 6) {
        Image(systemName: "key.fill")
          .foregroundStyle(.red)
        Text("Authentication Error")
          .font(.headline)
          .foregroundStyle(.red)
      }

      Spacer()

      Text(detail)
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(3)

      Text("Update token in Settings…")
        .font(.caption.weight(.medium))
        .foregroundStyle(Color.indigo)

      Spacer()
    }
  }
}

private struct ErrorWidgetView: View {
  let detail: String

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 6) {
        Image(systemName: "exclamationmark.triangle.fill")
          .foregroundStyle(.orange)
        Text("Error")
          .font(.headline)
      }

      Spacer()

      Text(detail)
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(4)

      Spacer()
    }
  }
}

private struct OfflineEmptyWidgetView: View {
  let detail: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 6) {
        Image(systemName: "wifi.slash")
          .foregroundStyle(.secondary)
        Text("Offline")
          .font(.headline)
      }

      Spacer()

      Text(detail ?? "Network unreachable. Waiting for connection.")
        .font(.caption)
        .foregroundStyle(.secondary)

      Spacer()
    }
  }
}

private struct RateLimitedEmptyWidgetView: View {
  let resetAt: Date?

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 6) {
        Image(systemName: "hourglass")
          .foregroundStyle(.orange)
        Text("Rate Limited")
          .font(.headline)
      }

      Spacer()

      if let resetAt {
        Text("Resets at \(resetAt, style: .time)")
          .font(.caption)
          .foregroundStyle(.secondary)
      } else {
        Text("GitHub rate limit exceeded.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Spacer()
    }
  }
}

private struct AllClearWidgetView: View {
  let snapshot: WidgetSnapshot

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 6) {
        Image(systemName: "checkmark.seal.fill")
          .foregroundStyle(.green)
        Text("All Clear")
          .font(.headline)
      }

      Spacer()

      Text("All CI checks passing and branches up to date.")
        .font(.caption)
        .foregroundStyle(.secondary)

      Spacer()

      HStack {
        Text("Updated \(snapshot.updatedAt, style: .time)")
          .font(.system(size: 9.5))
          .foregroundStyle(.tertiary)
        Spacer()
      }
    }
  }
}

private struct DataWidgetView: View {
  let snapshot: WidgetSnapshot
  let isDimmed: Bool
  let footerText: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      // Header
      HStack {
        Label("Repo Radar", systemImage: "radar")
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(isDimmed ? .secondary : .primary)

        Spacer()

        if let footerText {
          Text(footerText)
            .font(.system(size: 9))
            .foregroundStyle(.orange)
            .lineLimit(1)
        }
      }

      // Metric Chips
      HStack(spacing: 6) {
        MetricTile(
          title: "Failing",
          count: snapshot.failingCI.count,
          color: .red,
          isAlert: snapshot.failingCI.count > 0
        )
        MetricTile(
          title: "PRs",
          count: snapshot.pullRequests.count,
          color: .indigo,
          isAlert: false
        )
        MetricTile(
          title: "Reviews",
          count: snapshot.pullRequests.filter { $0.isReviewRequested }.count,
          color: .purple,
          isAlert: snapshot.pullRequests.contains { $0.isReviewRequested }
        )
        MetricTile(
          title: "Stale",
          count: snapshot.staleBranches.count,
          color: .orange,
          isAlert: false
        )
      }
      .opacity(isDimmed ? 0.6 : 1.0)

      Spacer(minLength: 0)

      // Footer
      HStack {
        Text("Updated \(snapshot.updatedAt, style: .time)")
          .font(.system(size: 9.5))
          .foregroundStyle(.tertiary)
        Spacer()
      }
    }
  }
}

private struct MetricTile: View {
  let title: String
  let count: Int
  let color: Color
  let isAlert: Bool

  var body: some View {
    VStack(spacing: 2) {
      Text("\(count)")
        .font(.system(size: 15, weight: .bold))
        .foregroundStyle(isAlert ? color : .primary)

      Text(title)
        .font(.system(size: 9, weight: .medium))
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 4)
    .background(
      RoundedRectangle(cornerRadius: 6)
        .fill(isAlert ? color.opacity(0.12) : Color.primary.opacity(0.04))
    )
  }
}

@main
struct RepoRadarWidget: Widget {
  let kind: String = "RepoRadarWidget"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: Provider()) { entry in
      RepoRadarWidgetEntryView(entry: entry)
    }
    .configurationDisplayName("Repo Radar")
    .description("Glance at open PRs, failing CI, and stale branches across your GitHub repos.")
    .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
  }
}

// MARK: - Previews

#Preview("Data - Small", as: .systemSmall) {
  RepoRadarWidget()
} timeline: {
  RepoRadarWidgetEntry.previewData
}

#Preview("All Clear - Small", as: .systemSmall) {
  RepoRadarWidget()
} timeline: {
  RepoRadarWidgetEntry.previewAllClear
}

#Preview("First Run - Small", as: .systemSmall) {
  RepoRadarWidget()
} timeline: {
  RepoRadarWidgetEntry.previewFirstRun
}

#Preview("No Repos - Small", as: .systemSmall) {
  RepoRadarWidget()
} timeline: {
  RepoRadarWidgetEntry.previewNoRepos
}

#Preview("Token Error - Small", as: .systemSmall) {
  RepoRadarWidget()
} timeline: {
  RepoRadarWidgetEntry.previewTokenError
}

#Preview("Offline - Small", as: .systemSmall) {
  RepoRadarWidget()
} timeline: {
  RepoRadarWidgetEntry.previewOffline
}

#Preview("Rate Limited - Small", as: .systemSmall) {
  RepoRadarWidget()
} timeline: {
  RepoRadarWidgetEntry.previewRateLimited
}
