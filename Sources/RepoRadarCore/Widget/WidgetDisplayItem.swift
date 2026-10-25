import Foundation

/// Display representation of an active item for widget medium and large layouts.
public struct WidgetDisplayItem: Identifiable, Sendable, Equatable {
  public enum ItemKind: Sendable, Equatable {
    case failingCI
    case runningCI
    case pullRequest(isReviewRequested: Bool)
    case staleBranch
  }

  public let id: String
  public let kind: ItemKind
  public let repo: String
  public let title: String
  public let subtitle: String
  public let iconName: String
  public let url: URL?

  public init(
    id: String,
    kind: ItemKind,
    repo: String,
    title: String,
    subtitle: String,
    iconName: String,
    url: URL? = nil
  ) {
    self.id = id
    self.kind = kind
    self.repo = repo
    self.title = title
    self.subtitle = subtitle
    self.iconName = iconName
    self.url = url
  }
}

extension WidgetSnapshot {
  /// Computes relative time strings like "just now", "12m ago", "3h ago", "5d ago".
  public static func relativeTimeString(from date: Date, relativeTo now: Date = Date()) -> String {
    let diff = max(0, Int(now.timeIntervalSince(date)))
    if diff < 60 {
      return "just now"
    } else if diff < 3600 {
      return "\(diff / 60)m ago"
    } else if diff < 86400 {
      return "\(diff / 3600)h ago"
    } else {
      return "\(diff / 86400)d ago"
    }
  }

  /// Ordered active items for widgets following the strict priority order:
  /// 1. Failing CI runs
  /// 2. In-progress CI runs
  /// 3. Pull requests (review requested first, then authored PRs)
  /// 4. Stale branches
  public func prioritizedWidgetItems(now: Date = Date()) -> [WidgetDisplayItem] {
    var items: [WidgetDisplayItem] = []

    // 1. Failing CI
    for item in failingCI {
      let timeText =
        item.completedAt.map { Self.relativeTimeString(from: $0, relativeTo: now) } ?? "failed"
      items.append(
        WidgetDisplayItem(
          id: "failing-\(item.id)",
          kind: .failingCI,
          repo: item.repo,
          title: "\(item.repo) · \(item.ref)",
          subtitle: "\(item.check) · \(timeText)",
          iconName: "xmark.circle.fill",
          url: WidgetGitHubURL.url(for: item)
        )
      )
    }

    // 2. Running CI
    for item in runningCI {
      items.append(
        WidgetDisplayItem(
          id: "running-\(item.id)",
          kind: .runningCI,
          repo: item.repo,
          title: "\(item.repo) · \(item.ref)",
          subtitle: "\(item.check) · running",
          iconName: "circle.dashed",
          url: WidgetGitHubURL.url(for: item)
        )
      )
    }

    // 3. Pull requests (review requested first, then authored PRs)
    let sortedPRs = pullRequests.sorted {
      ($0.isReviewRequested ? 0 : 1) < ($1.isReviewRequested ? 0 : 1)
    }
    for pr in sortedPRs {
      let timeText = Self.relativeTimeString(from: pr.updatedAt, relativeTo: now)
      let subtitle =
        pr.isReviewRequested
        ? "\(pr.repo) #\(pr.number) · review requested · \(timeText)"
        : "\(pr.repo) #\(pr.number) · \(timeText)"
      items.append(
        WidgetDisplayItem(
          id: "pr-\(pr.id)",
          kind: .pullRequest(isReviewRequested: pr.isReviewRequested),
          repo: pr.repo,
          title: pr.title,
          subtitle: subtitle,
          iconName: pr.isReviewRequested ? "eye" : "arrow.triangle.pull",
          url: WidgetGitHubURL.url(for: pr)
        )
      )
    }

    // 4. Stale branches
    for branch in staleBranches {
      items.append(
        WidgetDisplayItem(
          id: "stale-\(branch.id)",
          kind: .staleBranch,
          repo: branch.repo,
          title: branch.branch,
          subtitle: "\(branch.repo) · \(branch.ageDays)d",
          iconName: "arrow.triangle.branch",
          url: WidgetGitHubURL.url(for: branch)
        )
      )
    }

    return items
  }
}
