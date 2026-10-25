import RepoRadarCore
import SwiftUI
import WidgetKit

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

  public func getSnapshot(in context: Context, completion: @escaping (RepoRadarWidgetEntry) -> Void)
  {
    if context.isPreview {
      completion(RepoRadarWidgetEntry.previewData)
    } else {
      completion(loader.loadEntry())
    }
  }

  public func getTimeline(
    in context: Context, completion: @escaping (Timeline<RepoRadarWidgetEntry>) -> Void
  ) {
    let entry = loader.loadEntry()
    let nextRefresh =
      Calendar.current.date(byAdding: .minute, value: 15, to: Date())
      ?? Date().addingTimeInterval(900)
    let timeline = Timeline(entries: [entry], policy: .after(nextRefresh))
    completion(timeline)
  }
}

/// Root widget entry view routing to appropriate family presentation (small, medium, large).
public struct RepoRadarWidgetEntryView: View {
  public let entry: RepoRadarWidgetEntry
  @Environment(\.widgetFamily) private var family

  public init(entry: RepoRadarWidgetEntry) {
    self.entry = entry
  }

  public var body: some View {
    Group {
      switch family {
      case .systemSmall:
        SmallWidgetView(entry: entry)
      case .systemMedium:
        MediumWidgetView(entry: entry)
      case .systemLarge:
        LargeWidgetView(entry: entry)
      default:
        SmallWidgetView(entry: entry)
      }
    }
    .containerBackground(.fill.tertiary, for: .widget)
  }
}

// MARK: - Color and Formatting Helpers

extension WidgetDisplayItem {
  var color: Color {
    switch kind {
    case .failingCI:
      return .red
    case .runningCI:
      return .secondary
    case .pullRequest(let isReviewRequested):
      return isReviewRequested ? .purple : Color(red: 0.39, green: 0.40, blue: 0.95)
    case .staleBranch:
      return .orange
    }
  }
}

private func timeString(from date: Date) -> String {
  let formatter = DateFormatter()
  formatter.timeStyle = .short
  return formatter.string(from: date)
}

private func rateLimitNotice(resetAt: Date?, detail: String?) -> String {
  if let resetAt {
    let formatter = DateFormatter()
    formatter.timeStyle = .short
    return "Rate limited · Resets at \(formatter.string(from: resetAt))"
  }
  return detail ?? "Rate limited · Showing cached data"
}

// MARK: - Reusable UI Components

private struct MetricTile: View {
  let title: String
  let count: Int
  let color: Color
  let isAlert: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text("\(count)")
        .font(.system(size: 16, weight: .bold))
        .foregroundStyle(isAlert ? color : .primary)

      Text(title)
        .font(.system(size: 9.5, weight: .medium))
        .foregroundStyle(isAlert ? color : .secondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 7)
    .padding(.vertical, 5)
    .background(
      RoundedRectangle(cornerRadius: 6, style: .continuous)
        .fill(isAlert ? color.opacity(0.14) : Color.primary.opacity(0.05))
    )
  }
}

private struct MetricPill: View {
  let count: Int
  let label: String
  let color: Color
  let isAlert: Bool

  var body: some View {
    HStack(spacing: 3) {
      Text("\(count)")
        .font(.system(size: 10.5, weight: .bold))
        .foregroundStyle(isAlert ? color : .primary)

      Text(label)
        .font(.system(size: 9, weight: .medium))
        .foregroundStyle(isAlert ? color : .secondary)
    }
    .padding(.horizontal, 5)
    .padding(.vertical, 2)
    .background(
      RoundedRectangle(cornerRadius: 4.5, style: .continuous)
        .fill(isAlert ? color.opacity(0.14) : Color.primary.opacity(0.05))
    )
  }
}

private struct WidgetRowView: View {
  let icon: String
  let iconColor: Color
  let title: String
  let meta: String

  var body: some View {
    HStack(spacing: 7) {
      Image(systemName: icon)
        .font(.system(size: 11, weight: .bold))
        .foregroundStyle(iconColor)
        .frame(width: 14, height: 14)

      VStack(alignment: .leading, spacing: 1) {
        Text(title)
          .font(.system(size: 11, weight: .medium))
          .foregroundStyle(.primary)
          .lineLimit(1)

        Text(meta)
          .font(.system(size: 9))
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }

      Spacer(minLength: 0)
    }
  }
}

private struct WidgetSectionHeader: View {
  let icon: String
  let iconColor: Color
  let title: String
  let count: Int

  var body: some View {
    HStack(spacing: 5) {
      Image(systemName: icon)
        .font(.system(size: 10, weight: .bold))
        .foregroundStyle(iconColor)
        .frame(width: 12, height: 12)

      Text(title)
        .font(.system(size: 9.5, weight: .semibold))
        .foregroundStyle(.secondary)

      Spacer(minLength: 0)

      Text("\(count)")
        .font(.system(size: 9, weight: .bold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 5)
        .padding(.vertical, 0.5)
        .background(Color.primary.opacity(0.06), in: Capsule())
    }
    .frame(height: 16)
  }
}

// MARK: - Small Layout

private struct SmallWidgetView: View {
  let entry: RepoRadarWidgetEntry

  var body: some View {
    switch entry.state {
    case .firstRun:
      SmallEmptyCardView(
        icon: "radar",
        iconColor: Color.indigo,
        title: "Repo Radar",
        message: "Open the menu bar app to configure GitHub access."
      )

    case .noRepos:
      SmallEmptyCardView(
        icon: "book.closed",
        iconColor: Color.indigo,
        title: "No Repositories",
        message: "Add repositories to watch in Settings."
      )

    case .tokenError(let detail):
      SmallEmptyCardView(
        icon: "key.fill",
        iconColor: .red,
        title: "Auth Error",
        message: detail,
        actionHint: "Update in Settings…"
      )

    case .error(let detail):
      SmallEmptyCardView(
        icon: "exclamationmark.triangle.fill",
        iconColor: .orange,
        title: "Error",
        message: detail
      )

    case .allClear(let snapshot):
      SmallAllClearView(snapshot: snapshot)

    case .data(let snapshot):
      SmallDataView(snapshot: snapshot, isDimmed: false, footerText: nil)

    case .offline(let snapshot, let detail):
      if let snapshot {
        SmallDataView(snapshot: snapshot, isDimmed: true, footerText: detail ?? "Offline · Cached")
      } else {
        SmallEmptyCardView(
          icon: "wifi.slash",
          iconColor: .secondary,
          title: "Offline",
          message: detail ?? "Network unreachable. Waiting for connection."
        )
      }

    case .rateLimited(let snapshot, let resetAt, let detail):
      if let snapshot {
        SmallDataView(
          snapshot: snapshot, isDimmed: true,
          footerText: rateLimitNotice(resetAt: resetAt, detail: detail))
      } else {
        SmallEmptyCardView(
          icon: "hourglass",
          iconColor: .orange,
          title: "Rate Limited",
          message: rateLimitNotice(resetAt: resetAt, detail: detail)
        )
      }
    }
  }
}

private struct SmallDataView: View {
  let snapshot: WidgetSnapshot
  let isDimmed: Bool
  let footerText: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 5) {
      // Header
      HStack(spacing: 5) {
        Image(systemName: "radar")
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(Color.indigo)
        Text("Repo Radar")
          .font(.system(size: 12.5, weight: .semibold))
          .foregroundStyle(isDimmed ? .secondary : .primary)

        Spacer(minLength: 0)
      }

      // 4 Metric Count Tiles in 2x2 Grid
      Grid(horizontalSpacing: 5, verticalSpacing: 5) {
        GridRow {
          MetricTile(
            title: "Failing",
            count: snapshot.failingCI.count,
            color: .red,
            isAlert: snapshot.failingCI.count > 0
          )
          MetricTile(
            title: "PRs",
            count: snapshot.pullRequests.count,
            color: Color(red: 0.39, green: 0.40, blue: 0.95),
            isAlert: false
          )
        }
        GridRow {
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
      }
      .opacity(isDimmed ? 0.6 : 1.0)

      Spacer(minLength: 0)

      // Footer
      HStack {
        if let footerText {
          Text(footerText)
            .font(.system(size: 8.5))
            .foregroundStyle(.orange)
            .lineLimit(1)
        } else {
          Text("Updated \(timeString(from: snapshot.updatedAt))")
            .font(.system(size: 9))
            .foregroundStyle(.tertiary)
        }
        Spacer(minLength: 0)
      }
    }
  }
}

private struct SmallAllClearView: View {
  let snapshot: WidgetSnapshot

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 5) {
        Image(systemName: "radar")
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(Color.indigo)
        Text("Repo Radar")
          .font(.system(size: 12.5, weight: .semibold))
        Spacer()
      }

      Spacer(minLength: 0)

      VStack(alignment: .leading, spacing: 3) {
        Image(systemName: "checkmark.seal.fill")
          .font(.system(size: 24))
          .foregroundStyle(.green)

        Text("All Clear")
          .font(.system(size: 13.5, weight: .semibold))

        Text("All CI checks passing and branches up to date.")
          .font(.system(size: 9.5))
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }

      Spacer(minLength: 0)

      HStack {
        Text("Updated \(timeString(from: snapshot.updatedAt))")
          .font(.system(size: 9))
          .foregroundStyle(.tertiary)
        Spacer()
      }
    }
  }
}

private struct SmallEmptyCardView: View {
  let icon: String
  let iconColor: Color
  let title: String
  let message: String
  var actionHint: String? = nil

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 5) {
        Image(systemName: icon)
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(iconColor)
        Text(title)
          .font(.system(size: 12.5, weight: .semibold))
          .foregroundStyle(iconColor == .red ? .red : .primary)
      }

      Spacer(minLength: 0)

      Text(message)
        .font(.system(size: 10))
        .foregroundStyle(.secondary)
        .lineLimit(3)

      if let actionHint {
        Text(actionHint)
          .font(.system(size: 9.5, weight: .medium))
          .foregroundStyle(Color.indigo)
          .padding(.top, 1)
      }

      Spacer(minLength: 0)
    }
  }
}

// MARK: - Medium Layout

private struct MediumWidgetView: View {
  let entry: RepoRadarWidgetEntry

  var body: some View {
    switch entry.state {
    case .firstRun:
      MediumEmptyCardView(
        icon: "radar",
        iconColor: Color.indigo,
        title: "Welcome to Repo Radar",
        subtitle: "Open the menu bar app to configure GitHub access."
      )

    case .noRepos:
      MediumEmptyCardView(
        icon: "book.closed",
        iconColor: Color.indigo,
        title: "No Repositories",
        subtitle: "Add repositories to watch in Settings to see open PRs, CI, and stale branches."
      )

    case .tokenError(let detail):
      MediumEmptyCardView(
        icon: "key.fill",
        iconColor: .red,
        title: "Authentication Error",
        subtitle: detail,
        actionHint: "Update token in Settings…"
      )

    case .error(let detail):
      MediumEmptyCardView(
        icon: "exclamationmark.triangle.fill",
        iconColor: .orange,
        title: "Error",
        subtitle: detail
      )

    case .allClear(let snapshot):
      MediumAllClearView(snapshot: snapshot)

    case .data(let snapshot):
      MediumDataView(snapshot: snapshot, isDimmed: false, footerText: nil)

    case .offline(let snapshot, let detail):
      if let snapshot {
        MediumDataView(
          snapshot: snapshot, isDimmed: true, footerText: detail ?? "Offline · Showing cached data")
      } else {
        MediumEmptyCardView(
          icon: "wifi.slash",
          iconColor: .secondary,
          title: "Offline",
          subtitle: detail ?? "Network unreachable. Waiting for connection."
        )
      }

    case .rateLimited(let snapshot, let resetAt, let detail):
      if let snapshot {
        MediumDataView(
          snapshot: snapshot, isDimmed: true,
          footerText: rateLimitNotice(resetAt: resetAt, detail: detail))
      } else {
        MediumEmptyCardView(
          icon: "hourglass",
          iconColor: .orange,
          title: "Rate Limited",
          subtitle: rateLimitNotice(resetAt: resetAt, detail: detail)
        )
      }
    }
  }
}

private struct MediumDataView: View {
  let snapshot: WidgetSnapshot
  let isDimmed: Bool
  let footerText: String?

  private var displayItems: [WidgetDisplayItem] {
    Array(snapshot.prioritizedWidgetItems().prefix(3))
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      // Header: App name + metric pills
      HStack(spacing: 6) {
        Image(systemName: "radar")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(Color.indigo)
        Text("Repo Radar")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(isDimmed ? .secondary : .primary)

        Spacer(minLength: 4)

        HStack(spacing: 4) {
          MetricPill(
            count: snapshot.failingCI.count,
            label: "failing",
            color: .red,
            isAlert: snapshot.failingCI.count > 0
          )
          MetricPill(
            count: snapshot.pullRequests.count,
            label: "PRs",
            color: Color(red: 0.39, green: 0.40, blue: 0.95),
            isAlert: false
          )
          MetricPill(
            count: snapshot.pullRequests.filter { $0.isReviewRequested }.count,
            label: "reviews",
            color: .purple,
            isAlert: snapshot.pullRequests.contains { $0.isReviewRequested }
          )
          MetricPill(
            count: snapshot.staleBranches.count,
            label: "stale",
            color: .orange,
            isAlert: false
          )
        }
      }

      // Middle: Active items in section priority order
      VStack(alignment: .leading, spacing: 5) {
        ForEach(displayItems) { item in
          WidgetRowView(
            icon: item.iconName,
            iconColor: item.color,
            title: item.title,
            meta: item.subtitle
          )
        }
      }
      .opacity(isDimmed ? 0.6 : 1.0)

      Spacer(minLength: 0)

      // Footer
      HStack {
        Text("Updated \(timeString(from: snapshot.updatedAt))")
          .font(.system(size: 9.5))
          .foregroundStyle(.tertiary)

        Spacer(minLength: 0)

        if let footerText {
          Text(footerText)
            .font(.system(size: 9))
            .foregroundStyle(.orange)
            .lineLimit(1)
        }
      }
    }
  }
}

private struct MediumAllClearView: View {
  let snapshot: WidgetSnapshot

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 6) {
        Image(systemName: "radar")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(Color.indigo)
        Text("Repo Radar")
          .font(.system(size: 13, weight: .semibold))

        Spacer()

        Text("Updated \(timeString(from: snapshot.updatedAt))")
          .font(.system(size: 9.5))
          .foregroundStyle(.tertiary)
      }

      Spacer(minLength: 0)

      HStack(spacing: 12) {
        Image(systemName: "checkmark.seal.fill")
          .font(.system(size: 30))
          .foregroundStyle(.green)

        VStack(alignment: .leading, spacing: 2) {
          Text("All Clear")
            .font(.system(size: 14, weight: .semibold))

          Text("All CI checks passing and branches up to date.")
            .font(.system(size: 11.5))
            .foregroundStyle(.secondary)
        }
      }

      Spacer(minLength: 0)
    }
  }
}

private struct MediumEmptyCardView: View {
  let icon: String
  let iconColor: Color
  let title: String
  let subtitle: String
  var actionHint: String? = nil

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 6) {
        Image(systemName: "radar")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(Color.indigo)
        Text("Repo Radar")
          .font(.system(size: 13, weight: .semibold))
        Spacer()
      }

      Spacer(minLength: 0)

      HStack(alignment: .top, spacing: 12) {
        Image(systemName: icon)
          .font(.system(size: 26))
          .foregroundStyle(iconColor)
          .frame(width: 32)

        VStack(alignment: .leading, spacing: 3) {
          Text(title)
            .font(.system(size: 13.5, weight: .semibold))
            .foregroundStyle(iconColor == .red ? .red : .primary)

          Text(subtitle)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .lineLimit(2)

          if let actionHint {
            Text(actionHint)
              .font(.system(size: 10.5, weight: .medium))
              .foregroundStyle(Color.indigo)
              .padding(.top, 1)
          }
        }
      }

      Spacer(minLength: 0)
    }
  }
}

// MARK: - Large Layout

private struct LargeWidgetView: View {
  let entry: RepoRadarWidgetEntry

  var body: some View {
    switch entry.state {
    case .firstRun:
      LargeEmptyCardView(
        icon: "radar",
        iconColor: Color.indigo,
        title: "Welcome to Repo Radar",
        description:
          "Open the menu bar app to configure GitHub access. Your widget fills in after the first refresh."
      )

    case .noRepos:
      LargeEmptyCardView(
        icon: "book.closed",
        iconColor: Color.indigo,
        title: "No Repositories",
        description:
          "Add repositories to watch in Settings to see open PRs, CI, and stale branches across your projects."
      )

    case .tokenError(let detail):
      LargeEmptyCardView(
        icon: "key.fill",
        iconColor: .red,
        title: "Authentication Error",
        description: detail,
        actionHint: "Update token in Settings…"
      )

    case .error(let detail):
      LargeEmptyCardView(
        icon: "exclamationmark.triangle.fill",
        iconColor: .orange,
        title: "Error",
        description: detail
      )

    case .allClear(let snapshot):
      LargeAllClearView(snapshot: snapshot)

    case .data(let snapshot):
      LargeDataView(snapshot: snapshot, isDimmed: false, footerText: nil)

    case .offline(let snapshot, let detail):
      if let snapshot {
        LargeDataView(
          snapshot: snapshot, isDimmed: true, footerText: detail ?? "Offline · Showing cached data")
      } else {
        LargeEmptyCardView(
          icon: "wifi.slash",
          iconColor: .secondary,
          title: "Offline",
          description: detail ?? "Network unreachable. Waiting for connection."
        )
      }

    case .rateLimited(let snapshot, let resetAt, let detail):
      if let snapshot {
        LargeDataView(
          snapshot: snapshot, isDimmed: true,
          footerText: rateLimitNotice(resetAt: resetAt, detail: detail))
      } else {
        LargeEmptyCardView(
          icon: "hourglass",
          iconColor: .orange,
          title: "Rate Limited",
          description: rateLimitNotice(resetAt: resetAt, detail: detail)
        )
      }
    }
  }
}

private struct LargeDataView: View {
  let snapshot: WidgetSnapshot
  let isDimmed: Bool
  let footerText: String?

  private var failingDisplay: [FailingCIItem] {
    Array(snapshot.failingCI.prefix(2))
  }

  private var runningDisplay: [RunningCIItem] {
    Array(snapshot.runningCI.prefix(1))
  }

  private var prDisplay: [ClassifiedPullRequest] {
    let sorted = snapshot.pullRequests.sorted {
      ($0.isReviewRequested ? 0 : 1) < ($1.isReviewRequested ? 0 : 1)
    }
    return Array(sorted.prefix(2))
  }

  private var staleDisplay: [StaleBranchItem] {
    Array(snapshot.staleBranches.prefix(2))
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      // Header
      HStack {
        HStack(spacing: 6) {
          Image(systemName: "radar")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Color.indigo)
          Text("Repo Radar")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(isDimmed ? .secondary : .primary)
        }

        Spacer()

        Text("Updated \(timeString(from: snapshot.updatedAt))")
          .font(.system(size: 10))
          .foregroundStyle(.tertiary)
      }

      // Offline or rate limit banner
      if let footerText {
        HStack(spacing: 6) {
          Image(systemName: "exclamationmark.circle.fill")
            .font(.system(size: 11))
            .foregroundStyle(.orange)
          Text(footerText)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.orange)
            .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
      }

      // 4 Metric Count Tiles
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
          color: Color(red: 0.39, green: 0.40, blue: 0.95),
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

      Divider()
        .padding(.vertical, 1)

      // Sections in priority order: Failing CI, PRs, Stale branches
      VStack(alignment: .leading, spacing: 8) {
        // Section 1: Failing CI
        if !snapshot.failingCI.isEmpty || !snapshot.runningCI.isEmpty {
          VStack(alignment: .leading, spacing: 3) {
            WidgetSectionHeader(
              icon: "xmark.circle.fill",
              iconColor: .red,
              title: "FAILING CI",
              count: snapshot.failingCI.count + snapshot.runningCI.count
            )

            ForEach(failingDisplay) { item in
              let timeText =
                item.completedAt.map { WidgetSnapshot.relativeTimeString(from: $0) } ?? "failed"
              WidgetRowView(
                icon: "xmark.circle.fill",
                iconColor: .red,
                title: "\(item.repo) · \(item.ref)",
                meta: "\(item.check) · \(timeText)"
              )
            }

            ForEach(runningDisplay) { item in
              WidgetRowView(
                icon: "circle.dashed",
                iconColor: .secondary,
                title: "\(item.repo) · \(item.ref)",
                meta: "\(item.check) · running"
              )
            }
          }
        }

        // Section 2: Pull Requests
        if !snapshot.pullRequests.isEmpty {
          VStack(alignment: .leading, spacing: 3) {
            WidgetSectionHeader(
              icon: "arrow.triangle.pull",
              iconColor: Color(red: 0.39, green: 0.40, blue: 0.95),
              title: "PULL REQUESTS",
              count: snapshot.pullRequests.count
            )

            ForEach(prDisplay) { pr in
              let timeText = WidgetSnapshot.relativeTimeString(from: pr.updatedAt)
              let meta =
                pr.isReviewRequested
                ? "\(pr.repo) #\(pr.number) · review requested · \(timeText)"
                : "\(pr.repo) #\(pr.number) · \(timeText)"
              WidgetRowView(
                icon: pr.isReviewRequested ? "eye" : "arrow.triangle.pull",
                iconColor: pr.isReviewRequested
                  ? .purple : Color(red: 0.39, green: 0.40, blue: 0.95),
                title: pr.title,
                meta: meta
              )
            }
          }
        }

        // Section 3: Stale Branches
        if !snapshot.staleBranches.isEmpty {
          VStack(alignment: .leading, spacing: 3) {
            WidgetSectionHeader(
              icon: "arrow.triangle.branch",
              iconColor: .orange,
              title: "STALE BRANCHES",
              count: snapshot.staleBranches.count
            )

            ForEach(staleDisplay) { item in
              WidgetRowView(
                icon: "arrow.triangle.branch",
                iconColor: .orange,
                title: item.branch,
                meta: "\(item.repo) · \(item.ageDays)d"
              )
            }
          }
        }
      }
      .opacity(isDimmed ? 0.6 : 1.0)

      Spacer(minLength: 0)
    }
  }
}

private struct LargeAllClearView: View {
  let snapshot: WidgetSnapshot

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        HStack(spacing: 6) {
          Image(systemName: "radar")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Color.indigo)
          Text("Repo Radar")
            .font(.system(size: 14, weight: .semibold))
        }

        Spacer()

        Text("Updated \(timeString(from: snapshot.updatedAt))")
          .font(.system(size: 10))
          .foregroundStyle(.tertiary)
      }

      // 4 Metric Count Tiles showing all clear
      HStack(spacing: 6) {
        MetricTile(
          title: "CI passing",
          count: 0,
          color: .green,
          isAlert: false
        )
        MetricTile(
          title: "PRs",
          count: 0,
          color: Color(red: 0.39, green: 0.40, blue: 0.95),
          isAlert: false
        )
        MetricTile(
          title: "Reviews",
          count: 0,
          color: .purple,
          isAlert: false
        )
        MetricTile(
          title: "Stale",
          count: 0,
          color: .orange,
          isAlert: false
        )
      }

      Divider()
        .padding(.vertical, 2)

      Spacer(minLength: 0)

      VStack(spacing: 8) {
        Image(systemName: "checkmark.seal.fill")
          .font(.system(size: 38))
          .foregroundStyle(.green)

        Text("All Clear")
          .font(.system(size: 16, weight: .semibold))

        Text("All CI checks passing and branches up to date.")
          .font(.system(size: 12))
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
      }
      .frame(maxWidth: .infinity)

      Spacer(minLength: 0)
    }
  }
}

private struct LargeEmptyCardView: View {
  let icon: String
  let iconColor: Color
  let title: String
  let description: String
  var actionHint: String? = nil

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 6) {
        Image(systemName: "radar")
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(Color.indigo)
        Text("Repo Radar")
          .font(.system(size: 14, weight: .semibold))
        Spacer()
      }

      Spacer(minLength: 0)

      VStack(spacing: 10) {
        ZStack {
          RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(iconColor.opacity(0.12))
            .frame(width: 48, height: 48)

          Image(systemName: icon)
            .font(.system(size: 24, weight: .semibold))
            .foregroundStyle(iconColor)
        }

        Text(title)
          .font(.system(size: 15, weight: .semibold))
          .foregroundStyle(iconColor == .red ? .red : .primary)

        Text(description)
          .font(.system(size: 12))
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .lineSpacing(2)
          .padding(.horizontal, 16)

        if let actionHint {
          Text(actionHint)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Color.indigo)
            .padding(.top, 2)
        }
      }
      .frame(maxWidth: .infinity)

      Spacer(minLength: 0)
    }
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

// MARK: - Previews: Small

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

#Preview("Error - Small", as: .systemSmall) {
  RepoRadarWidget()
} timeline: {
  RepoRadarWidgetEntry.previewError
}

// MARK: - Previews: Medium

#Preview("Data - Medium", as: .systemMedium) {
  RepoRadarWidget()
} timeline: {
  RepoRadarWidgetEntry.previewData
}

#Preview("All Clear - Medium", as: .systemMedium) {
  RepoRadarWidget()
} timeline: {
  RepoRadarWidgetEntry.previewAllClear
}

#Preview("First Run - Medium", as: .systemMedium) {
  RepoRadarWidget()
} timeline: {
  RepoRadarWidgetEntry.previewFirstRun
}

#Preview("No Repos - Medium", as: .systemMedium) {
  RepoRadarWidget()
} timeline: {
  RepoRadarWidgetEntry.previewNoRepos
}

#Preview("Token Error - Medium", as: .systemMedium) {
  RepoRadarWidget()
} timeline: {
  RepoRadarWidgetEntry.previewTokenError
}

#Preview("Offline - Medium", as: .systemMedium) {
  RepoRadarWidget()
} timeline: {
  RepoRadarWidgetEntry.previewOffline
}

#Preview("Rate Limited - Medium", as: .systemMedium) {
  RepoRadarWidget()
} timeline: {
  RepoRadarWidgetEntry.previewRateLimited
}

#Preview("Error - Medium", as: .systemMedium) {
  RepoRadarWidget()
} timeline: {
  RepoRadarWidgetEntry.previewError
}

// MARK: - Previews: Large

#Preview("Data - Large", as: .systemLarge) {
  RepoRadarWidget()
} timeline: {
  RepoRadarWidgetEntry.previewData
}

#Preview("All Clear - Large", as: .systemLarge) {
  RepoRadarWidget()
} timeline: {
  RepoRadarWidgetEntry.previewAllClear
}

#Preview("First Run - Large", as: .systemLarge) {
  RepoRadarWidget()
} timeline: {
  RepoRadarWidgetEntry.previewFirstRun
}

#Preview("No Repos - Large", as: .systemLarge) {
  RepoRadarWidget()
} timeline: {
  RepoRadarWidgetEntry.previewNoRepos
}

#Preview("Token Error - Large", as: .systemLarge) {
  RepoRadarWidget()
} timeline: {
  RepoRadarWidgetEntry.previewTokenError
}

#Preview("Offline - Large", as: .systemLarge) {
  RepoRadarWidget()
} timeline: {
  RepoRadarWidgetEntry.previewOffline
}

#Preview("Rate Limited - Large", as: .systemLarge) {
  RepoRadarWidget()
} timeline: {
  RepoRadarWidgetEntry.previewRateLimited
}

#Preview("Error - Large", as: .systemLarge) {
  RepoRadarWidget()
} timeline: {
  RepoRadarWidgetEntry.previewError
}
