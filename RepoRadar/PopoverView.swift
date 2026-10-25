import SwiftUI
import RepoRadarCore
#if canImport(AppKit)
import AppKit
#endif

/// Presents the full RepoRadar popover UI covering the states:
/// issues, clear, token expired, offline, error, and first run setup.
public struct PopoverView: View {
  @ObservedObject var scheduler: RefreshScheduler
  @State private var showAllStale: Bool = false
  @Environment(\.openSettings) private var openSettingsAction

  public init(scheduler: RefreshScheduler) {
    self.scheduler = scheduler
  }

  private var config: RepoRadarConfig {
    scheduler.service.configStore.load()
  }

  private var hasToken: Bool {
    scheduler.service.tokenStore.hasToken()
  }

  private var state: PopoverState {
    PopoverState.current(
      hasToken: hasToken,
      watchedRepos: config.watchedRepos,
      snapshot: scheduler.latestSnapshot
    )
  }

  public var body: some View {
    PopoverContentView(
      state: state,
      repoCount: config.watchedRepos.count,
      lastUpdated: scheduler.lastUpdated,
      isRefreshing: scheduler.isRefreshing,
      staleDaysThreshold: config.staleDays,
      snapshot: scheduler.latestSnapshot,
      showAllStale: $showAllStale,
      onRefresh: {
        Task {
          try? await scheduler.refreshNow()
        }
      },
      onOpenSettings: {
        openSettings()
      }
    )
    .frame(width: 340)
  }

  private func openSettings() {
    #if canImport(AppKit)
    NSApp.activate(ignoringOtherApps: true)
    #endif
    openSettingsAction()
  }
}

/// Standalone presentation container usable in live app and SwiftUI previews.
public struct PopoverContentView: View {
  let state: PopoverState
  let repoCount: Int
  let lastUpdated: Date?
  let isRefreshing: Bool
  let staleDaysThreshold: Int
  let snapshot: WidgetSnapshot?
  @Binding var showAllStale: Bool
  let onRefresh: () -> Void
  let onOpenSettings: () -> Void

  public init(
    state: PopoverState,
    repoCount: Int,
    lastUpdated: Date?,
    isRefreshing: Bool,
    staleDaysThreshold: Int = 30,
    snapshot: WidgetSnapshot?,
    showAllStale: Binding<Bool>,
    onRefresh: @escaping () -> Void,
    onOpenSettings: @escaping () -> Void
  ) {
    self.state = state
    self.repoCount = repoCount
    self.lastUpdated = lastUpdated
    self.isRefreshing = isRefreshing
    self.staleDaysThreshold = staleDaysThreshold
    self.snapshot = snapshot
    self._showAllStale = showAllStale
    self.onRefresh = onRefresh
    self.onOpenSettings = onOpenSettings
  }

  private var isWaitingForFirstRefresh: Bool {
    snapshot == nil || snapshot?.status == .missing
  }

  private var failingCI: [FailingCIItem] {
    snapshot?.failingCI ?? []
  }

  private var runningCI: [RunningCIItem] {
    snapshot?.runningCI ?? []
  }

  private var pullRequests: [ClassifiedPullRequest] {
    snapshot?.pullRequests ?? []
  }

  private var staleBranches: [StaleBranchItem] {
    snapshot?.staleBranches ?? []
  }

  public var body: some View {
    VStack(spacing: 0) {
      // Header
      headerView

      // Banners for token error, offline, or neutral server/system error
      if state == .token {
        bannerView(
          icon: "key.fill",
          iconColor: .red,
          title: "GitHub token rejected",
          bodyText: "GitHub rejected the token. The data below is from your last refresh.",
          actionTitle: "Update Token…",
          action: onOpenSettings
        )
      } else if state == .offline {
        bannerView(
          icon: "wifi.slash",
          iconColor: .orange,
          title: "You’re offline",
          bodyText: "Showing cached data. Repo Radar retries when you’re back online.",
          actionTitle: nil,
          action: nil
        )
      } else if state == .error {
        let detail = snapshot?.status.errorDetail ?? "GitHub server error"
        bannerView(
          icon: "exclamationmark.triangle.fill",
          iconColor: .red,
          title: "Couldn't refresh",
          bodyText: "\(detail). The data below is from your last refresh.",
          actionTitle: nil,
          action: nil
        )
      }

      if state == .setup {
        // Welcome first-run card
        welcomeSetupView
      } else {
        // Data content
        ScrollView(.vertical, showsIndicators: false) {
          VStack(spacing: 10) {
            // 4 Count Tiles
            chipsGrid

            Divider()
              .padding(.horizontal, 12)

            // Sections
            sectionsList
          }
          .padding(.vertical, 8)
        }
        .opacity(state == .token || state == .offline || state == .error ? 0.5 : 1.0)
      }

      Divider()

      // Footer
      footerView
    }
    .background(Color(nsColor: .windowBackgroundColor))
  }

  // MARK: - Header

  private var headerView: some View {
    HStack(spacing: 10) {
      ZStack {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
          .fill(Color.indigo.opacity(0.14))
          .frame(width: 28, height: 28)
        Image(systemName: "radar")
          .font(.system(size: 16, weight: .semibold))
          .foregroundStyle(Color(red: 0.39, green: 0.40, blue: 0.95))
      }

      VStack(alignment: .leading, spacing: 1) {
        Text("Repo Radar")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(.primary)

        Text(subtitleText)
          .font(.system(size: 11))
          .foregroundStyle(subtitleColor)
      }

      Spacer()

      Button(action: onRefresh) {
        Image(systemName: "arrow.clockwise")
          .font(.system(size: 13, weight: .medium))
          .foregroundStyle(.secondary)
          .rotationEffect(.degrees(isRefreshing ? 360 : 0))
          .animation(
            isRefreshing ? .linear(duration: 1).repeatForever(autoreverses: false) : .default,
            value: isRefreshing
          )
          .frame(width: 28, height: 28)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .disabled(isRefreshing || state == .setup)
      .accessibilityLabel("Refresh now")
    }
    .padding(.horizontal, 14)
    .padding(.top, 14)
    .padding(.bottom, 10)
  }

  private var subtitleText: String {
    if isWaitingForFirstRefresh && state != .setup {
      return "\(repoCount) repos · Waiting for first refresh"
    }

    switch state {
    case .issues:
      if let lastUpdated {
        return "\(repoCount) repos · Updated \(relativeTimeString(from: lastUpdated))"
      }
      return "\(repoCount) repos"
    case .clear:
      if let lastUpdated {
        return "\(repoCount) repos · Updated \(relativeTimeString(from: lastUpdated))"
      }
      return "\(repoCount) repos · Waiting for first refresh"
    case .token:
      if let lastUpdated {
        return "Not refreshing · last update \(lastUpdated.formatted(date: .abbreviated, time: .shortened))"
      }
      return "Not refreshing · Authentication required"
    case .offline:
      if let lastUpdated {
        return "Offline · last update \(relativeTimeString(from: lastUpdated))"
      }
      return "Offline"
    case .error:
      if let lastUpdated {
        return "Couldn't refresh · last update \(relativeTimeString(from: lastUpdated))"
      }
      return "Couldn't refresh"
    case .setup:
      return "Not set up yet"
    }
  }

  private var subtitleColor: Color {
    switch state {
    case .token, .error:
      return .red
    case .offline:
      return .orange
    default:
      return .secondary
    }
  }

  // MARK: - Banner

  private func bannerView(
    icon: String,
    iconColor: Color,
    title: String,
    bodyText: String,
    actionTitle: String?,
    action: (() -> Void)?
  ) -> some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: icon)
        .font(.system(size: 14))
        .foregroundStyle(iconColor)
        .frame(width: 16, height: 16)
        .padding(.top, 1)

      VStack(alignment: .leading, spacing: 3) {
        Text(title)
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(iconColor)

        Text(bodyText)
          .font(.system(size: 11))
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)

        if let actionTitle, let action {
          Button(action: action) {
            Text(actionTitle)
              .font(.system(size: 12, weight: .medium))
              .foregroundStyle(.white)
              .padding(.horizontal, 10)
              .padding(.vertical, 3)
              .background(Color(red: 0.31, green: 0.27, blue: 0.90), in: RoundedRectangle(cornerRadius: 6))
          }
          .buttonStyle(.plain)
          .padding(.top, 4)
        }
      }
      Spacer(minLength: 0)
    }
    .padding(10)
    .background(iconColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    .padding(.horizontal, 12)
    .padding(.bottom, 8)
  }

  // MARK: - Chips Grid (4 Count Tiles)

  private var chipsGrid: some View {
    let myPRsCount = pullRequests.filter { $0.reason == .mine }.count
    let reviewsCount = pullRequests.filter { $0.reason == .reviewRequested }.count

    return HStack(spacing: 6) {
      if isWaitingForFirstRefresh {
        chipTile(count: "-", label: "CI passing", tint: Color.primary.opacity(0.06), textColor: .secondary)
        chipTile(count: "-", label: "my PRs", tint: Color.primary.opacity(0.06), textColor: .secondary)
        chipTile(count: "-", label: "reviews", tint: Color.primary.opacity(0.06), textColor: .secondary)
        chipTile(count: "-", label: "stale", tint: Color.primary.opacity(0.06), textColor: .secondary)
      } else if state == .clear {
        chipTile(count: "✓", label: "CI passing", tint: Color.green.opacity(0.14), textColor: .green)
        chipTile(count: "\(myPRsCount)", label: "my PRs", tint: Color.indigo.opacity(0.14), textColor: Color(red: 0.39, green: 0.40, blue: 0.95))
        chipTile(count: "\(reviewsCount)", label: "reviews", tint: Color.purple.opacity(0.14), textColor: .purple)
        chipTile(count: "\(staleBranches.count)", label: "stale", tint: Color.orange.opacity(0.14), textColor: .orange)
      } else {
        chipTile(count: "\(failingCI.count)", label: "failing", tint: Color.red.opacity(0.14), textColor: .red)
        chipTile(count: "\(myPRsCount)", label: "my PRs", tint: Color.indigo.opacity(0.14), textColor: Color(red: 0.39, green: 0.40, blue: 0.95))
        chipTile(count: "\(reviewsCount)", label: "review", tint: Color.purple.opacity(0.14), textColor: .purple)
        chipTile(count: "\(staleBranches.count)", label: "stale", tint: Color.orange.opacity(0.14), textColor: .orange)
      }
    }
    .padding(.horizontal, 12)
  }

  private func chipTile(count: String, label: String, tint: Color, textColor: Color) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(count)
        .font(.system(size: 17, weight: .bold))
        .foregroundStyle(textColor)

      Text(label)
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(textColor)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 8)
    .padding(.vertical, 7)
    .background(tint, in: RoundedRectangle(cornerRadius: 8))
  }

  // MARK: - Sections

  private var sectionsList: some View {
    VStack(alignment: .leading, spacing: 12) {
      // CI Section
      ciSection

      // Pull Requests Section
      prSection

      // Stale Branches Section
      staleSection
    }
    .padding(.horizontal, 8)
  }

  private var ciSection: some View {
    VStack(alignment: .leading, spacing: 3) {
      sectionHeader(
        icon: isWaitingForFirstRefresh ? "arrow.clockwise" : (state == .clear ? "checkmark.circle.fill" : "xmark.circle.fill"),
        iconColor: isWaitingForFirstRefresh ? .secondary : (state == .clear ? .green : .red),
        title: state == .clear || isWaitingForFirstRefresh ? "CI" : "FAILING CI",
        count: isWaitingForFirstRefresh || state == .clear ? 0 : failingCI.count + runningCI.count
      )

      if isWaitingForFirstRefresh {
        PopoverRowView(
          icon: "arrow.clockwise",
          iconColor: .secondary,
          title: "Waiting for first refresh…",
          meta: "Checking \(repoCount) watched repositories",
          url: nil
        )
      } else if state == .clear {
        let checkedText: String = {
          if let lastUpdated {
            return "checked \(relativeTimeString(from: lastUpdated))"
          }
          return "checked just now"
        }()

        PopoverRowView(
          icon: "checkmark.circle.fill",
          iconColor: .green,
          title: "All \(repoCount) repos passing",
          meta: "Default branches and your PRs · \(checkedText)",
          url: nil
        )
      } else {
        ForEach(failingCI) { item in
          PopoverRowView(
            icon: "xmark.circle.fill",
            iconColor: .red,
            title: "\(item.repo) · \(item.ref)",
            meta: "\(item.check) · failed \(relativeTimeString(from: item.completedAt ?? Date()))",
            url: item.url
          )
        }

        ForEach(runningCI) { item in
          PopoverRowView(
            icon: "circle.dashed",
            iconColor: .secondary,
            title: "\(item.repo) · \(item.ref)",
            meta: "\(item.check) · running \(durationString(from: item.startedAt ?? Date()))",
            url: item.url
          )
        }
      }
    }
  }

  private var prSection: some View {
    VStack(alignment: .leading, spacing: 3) {
      sectionHeader(
        icon: "arrow.triangle.pull",
        iconColor: Color(red: 0.39, green: 0.40, blue: 0.95),
        title: "PULL REQUESTS",
        count: pullRequests.count
      )

      if isWaitingForFirstRefresh {
        Text("No pull request data yet.")
          .font(.system(size: 12))
          .foregroundStyle(.secondary)
          .padding(.leading, 32)
          .padding(.vertical, 4)
      } else if pullRequests.isEmpty {
        Text("No open pull requests.")
          .font(.system(size: 12))
          .foregroundStyle(.secondary)
          .padding(.leading, 32)
          .padding(.vertical, 4)
      } else {
        // Sort: review requests first, then authored PRs
        let sortedPRs = pullRequests.sorted {
          ($0.reason == .reviewRequested ? 0 : 1) < ($1.reason == .reviewRequested ? 0 : 1)
        }

        ForEach(sortedPRs) { pr in
          let isReview = pr.reason == .reviewRequested
          PopoverRowView(
            icon: isReview ? "eye" : "arrow.triangle.pull",
            iconColor: isReview ? .purple : Color(red: 0.39, green: 0.40, blue: 0.95),
            title: pr.title,
            meta: isReview
              ? "\(pr.repo) #\(pr.number) · review requested · \(relativeTimeString(from: pr.updatedAt))"
              : "\(pr.repo) #\(pr.number) · \(relativeTimeString(from: pr.updatedAt))",
            url: pr.url
          )
        }
      }
    }
  }

  private var staleSection: some View {
    VStack(alignment: .leading, spacing: 3) {
      sectionHeader(
        icon: "arrow.triangle.branch",
        iconColor: .orange,
        title: "STALE BRANCHES",
        count: staleBranches.count
      )

      if isWaitingForFirstRefresh {
        Text("No branch data yet.")
          .font(.system(size: 12))
          .foregroundStyle(.secondary)
          .padding(.leading, 32)
          .padding(.vertical, 4)
      } else if staleBranches.isEmpty {
        Text("No branches older than \(staleDaysThreshold) days.")
          .font(.system(size: 12))
          .foregroundStyle(.secondary)
          .padding(.leading, 32)
          .padding(.vertical, 4)
      } else {
        let visibleBranches = showAllStale ? staleBranches : Array(staleBranches.prefix(2))
        ForEach(visibleBranches) { item in
          let branchURL = URL(string: "https://github.com/\(item.repo)/tree/\(item.branch)")
          PopoverRowView(
            icon: "arrow.triangle.branch",
            iconColor: .orange,
            title: item.branch,
            meta: "\(item.repo) · \(item.ageDays) days",
            url: branchURL
          )
        }

        if staleBranches.count > 2 {
          Button {
            showAllStale.toggle()
          } label: {
            Text(showAllStale ? "Show less" : "Show \(staleBranches.count - 2) more")
              .font(.system(size: 12, weight: .medium))
              .foregroundStyle(Color(red: 0.39, green: 0.40, blue: 0.95))
              .padding(.leading, 32)
              .padding(.vertical, 2)
          }
          .buttonStyle(.plain)
        }
      }
    }
  }

  private func sectionHeader(icon: String, iconColor: Color, title: String, count: Int) -> some View {
    HStack(spacing: 6) {
      Image(systemName: icon)
        .font(.system(size: 11, weight: .bold))
        .foregroundStyle(iconColor)
        .frame(width: 14, height: 14)

      Text(title)
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(.secondary)

      Spacer()

      Text("\(count)")
        .font(.system(size: 10, weight: .bold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 6)
        .padding(.vertical, 1)
        .background(Color.primary.opacity(0.06), in: Capsule())
    }
    .padding(.horizontal, 8)
    .frame(height: 20)
  }

  // MARK: - Welcome / Setup View

  private var welcomeSetupView: some View {
    VStack(spacing: 12) {
      Spacer(minLength: 24)

      ZStack {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .fill(Color.indigo.opacity(0.14))
          .frame(width: 56, height: 56)
        Image(systemName: "radar")
          .font(.system(size: 30, weight: .semibold))
          .foregroundStyle(Color(red: 0.39, green: 0.40, blue: 0.95))
      }

      Text("Welcome to Repo Radar")
        .font(.system(size: 15, weight: .semibold))

      Text("Add a read-only GitHub token and choose which repositories to watch. Your widget fills in after the first refresh.")
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .lineSpacing(2)
        .padding(.horizontal, 24)

      Button(action: onOpenSettings) {
        Text("Open Settings…")
          .font(.system(size: 13, weight: .medium))
          .foregroundStyle(.white)
          .padding(.horizontal, 14)
          .padding(.vertical, 6)
          .background(Color(red: 0.31, green: 0.27, blue: 0.90), in: RoundedRectangle(cornerRadius: 6))
      }
      .buttonStyle(.plain)
      .padding(.top, 4)

      if let tokenURL = URL(string: "https://github.com/settings/personal-access-tokens/new") {
        Link("How to create a token ↗", destination: tokenURL)
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(Color(red: 0.39, green: 0.40, blue: 0.95))
      }

      Spacer(minLength: 24)
    }
    .padding(.horizontal, 16)
  }

  // MARK: - Footer

  private var footerView: some View {
    HStack {
      Button(action: onOpenSettings) {
        HStack(spacing: 6) {
          Image(systemName: "slider.horizontal.3")
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
          Text("Settings…")
            .font(.system(size: 13))
          Text("⌘,")
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .keyboardShortcut(",", modifiers: .command)

      Spacer()

      Button {
        #if canImport(AppKit)
        NSApplication.shared.terminate(nil)
        #endif
      } label: {
        HStack(spacing: 4) {
          Text("Quit")
            .font(.system(size: 13))
          Text("⌘Q")
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .keyboardShortcut("q", modifiers: .command)
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 8)
  }

  // MARK: - Time Formatting Helpers

  private func relativeTimeString(from date: Date) -> String {
    let diff = Int(Date().timeIntervalSince(date))
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

  private func durationString(from date: Date) -> String {
    let diff = max(0, Int(Date().timeIntervalSince(date)))
    if diff < 60 {
      return "\(diff)s"
    } else {
      return "\(diff / 60)m"
    }
  }
}

/// An interactive row in the popover that links to GitHub.
private struct PopoverRowView: View {
  let icon: String
  let iconColor: Color
  let title: String
  let meta: String
  let url: URL?

  @State private var isHovered = false

  var body: some View {
    Button {
      if let url {
        #if canImport(AppKit)
        NSWorkspace.shared.open(url)
        #endif
      }
    } label: {
      HStack(spacing: 8) {
        Image(systemName: icon)
          .font(.system(size: 13))
          .foregroundStyle(iconColor)
          .frame(width: 16, height: 16)

        VStack(alignment: .leading, spacing: 1) {
          Text(title)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .truncationMode(.tail)

          Text(meta)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.tail)
        }

        Spacer(minLength: 4)

        if isHovered && url != nil {
          Image(systemName: "arrow.up.right")
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }
      }
      .padding(.horizontal, 8)
      .padding(.vertical, 5)
      .background(isHovered ? Color.primary.opacity(0.06) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
      .contentShape(RoundedRectangle(cornerRadius: 6))
    }
    .buttonStyle(.plain)
    .onHover { isHovered = $0 }
  }
}

// MARK: - Previews for All States (Light + Dark)

private enum PopoverPreviewData {
  static let failingSnapshot = WidgetSnapshot(
    updatedAt: Date().addingTimeInterval(-120),
    status: .ok,
    failingCI: [
      FailingCIItem(
        repo: "gravity-bar",
        ref: "main",
        kind: .defaultBranch,
        check: "Build & Test (macOS)",
        conclusion: "FAILURE",
        url: URL(string: "https://github.com/Cwander83/gravity-bar/actions")!,
        completedAt: Date().addingTimeInterval(-720)
      ),
      FailingCIItem(
        repo: "repo-radar",
        ref: "#12 add-graphql-fetcher",
        kind: .myPullRequest,
        check: "Security & Secret Scan",
        conclusion: "FAILURE",
        url: URL(string: "https://github.com/Cwander83/repo-radar/actions")!,
        completedAt: Date().addingTimeInterval(-3600)
      )
    ],
    runningCI: [
      RunningCIItem(
        repo: "ollama-bar",
        ref: "develop",
        kind: .defaultBranch,
        check: "Build & Test (macOS)",
        status: "IN_PROGRESS",
        url: URL(string: "https://github.com/Cwander83/ollama-bar/actions")!,
        startedAt: Date().addingTimeInterval(-180)
      )
    ],
    pullRequests: [
      ClassifiedPullRequest(
        repo: "gravity-bar",
        number: 14,
        title: "Fix popover hover state",
        url: URL(string: "https://github.com/Cwander83/gravity-bar/pull/14")!,
        headRefName: "fix/hover-state",
        reason: .reviewRequested,
        updatedAt: Date().addingTimeInterval(-18000)
      ),
      ClassifiedPullRequest(
        repo: "repo-radar",
        number: 12,
        title: "Add GraphQL fetcher",
        url: URL(string: "https://github.com/Cwander83/repo-radar/pull/12")!,
        headRefName: "feat/graphql",
        reason: .mine,
        updatedAt: Date().addingTimeInterval(-172800)
      ),
      ClassifiedPullRequest(
        repo: "ollama-bar",
        number: 9,
        title: "Bump actions/checkout to v8",
        url: URL(string: "https://github.com/Cwander83/ollama-bar/pull/9")!,
        headRefName: "chore/bump-actions",
        reason: .mine,
        updatedAt: Date().addingTimeInterval(-518400)
      ),
      ClassifiedPullRequest(
        repo: "workout-tracker",
        number: 31,
        title: "Workout history chart",
        url: URL(string: "https://github.com/Cwander83/workout-tracker/pull/31")!,
        headRefName: "feat/chart",
        reason: .mine,
        updatedAt: Date().addingTimeInterval(-777600)
      )
    ],
    staleBranches: [
      StaleBranchItem(
        repo: "gravity-bar",
        branch: "feat/weekly-window",
        ageDays: 58,
        lastCommitDate: Date().addingTimeInterval(-58 * 86400),
        lastCommitOid: "1234567"
      ),
      StaleBranchItem(
        repo: "repo-radar",
        branch: "spike/app-groups",
        ageDays: 41,
        lastCommitDate: Date().addingTimeInterval(-41 * 86400),
        lastCommitOid: "7654321"
      ),
      StaleBranchItem(
        repo: "ollama-bar",
        branch: "refactor/model-loader",
        ageDays: 35,
        lastCommitDate: Date().addingTimeInterval(-35 * 86400),
        lastCommitOid: "abcdef1"
      ),
      StaleBranchItem(
        repo: "workout-tracker",
        branch: "test/sync-provider",
        ageDays: 32,
        lastCommitDate: Date().addingTimeInterval(-32 * 86400),
        lastCommitOid: "fedcba9"
      )
    ]
  )

  static let clearSnapshot = WidgetSnapshot(
    updatedAt: Date().addingTimeInterval(-120),
    status: .ok,
    failingCI: [],
    runningCI: [],
    pullRequests: [
      ClassifiedPullRequest(
        repo: "repo-radar",
        number: 12,
        title: "Add GraphQL fetcher",
        url: URL(string: "https://github.com/Cwander83/repo-radar/pull/12")!,
        headRefName: "feat/graphql",
        reason: .mine,
        updatedAt: Date().addingTimeInterval(-172800)
      ),
      ClassifiedPullRequest(
        repo: "ollama-bar",
        number: 9,
        title: "Bump actions/checkout to v8",
        url: URL(string: "https://github.com/Cwander83/ollama-bar/pull/9")!,
        headRefName: "chore/bump-actions",
        reason: .mine,
        updatedAt: Date().addingTimeInterval(-518400)
      ),
      ClassifiedPullRequest(
        repo: "workout-tracker",
        number: 31,
        title: "Workout history chart",
        url: URL(string: "https://github.com/Cwander83/workout-tracker/pull/31")!,
        headRefName: "feat/chart",
        reason: .mine,
        updatedAt: Date().addingTimeInterval(-777600)
      )
    ],
    staleBranches: []
  )

  static let serverErrorSnapshot = WidgetSnapshot(
    updatedAt: Date().addingTimeInterval(-1800),
    status: .serverError(detail: "HTTP 502 Bad Gateway"),
    failingCI: failingSnapshot.failingCI,
    runningCI: failingSnapshot.runningCI,
    pullRequests: failingSnapshot.pullRequests,
    staleBranches: failingSnapshot.staleBranches
  )
}

#Preview("1. Issues - Light") {
  PopoverContentView(
    state: .issues,
    repoCount: 5,
    lastUpdated: Date().addingTimeInterval(-120),
    isRefreshing: false,
    snapshot: PopoverPreviewData.failingSnapshot,
    showAllStale: .constant(false),
    onRefresh: {},
    onOpenSettings: {}
  )
  .frame(width: 340)
  .preferredColorScheme(.light)
}

#Preview("1. Issues - Dark") {
  PopoverContentView(
    state: .issues,
    repoCount: 5,
    lastUpdated: Date().addingTimeInterval(-120),
    isRefreshing: false,
    snapshot: PopoverPreviewData.failingSnapshot,
    showAllStale: .constant(false),
    onRefresh: {},
    onOpenSettings: {}
  )
  .frame(width: 340)
  .preferredColorScheme(.dark)
}

#Preview("2. All Clear - Light") {
  PopoverContentView(
    state: .clear,
    repoCount: 5,
    lastUpdated: Date().addingTimeInterval(-120),
    isRefreshing: false,
    snapshot: PopoverPreviewData.clearSnapshot,
    showAllStale: .constant(false),
    onRefresh: {},
    onOpenSettings: {}
  )
  .frame(width: 340)
  .preferredColorScheme(.light)
}

#Preview("2. All Clear - Dark") {
  PopoverContentView(
    state: .clear,
    repoCount: 5,
    lastUpdated: Date().addingTimeInterval(-120),
    isRefreshing: false,
    snapshot: PopoverPreviewData.clearSnapshot,
    showAllStale: .constant(false),
    onRefresh: {},
    onOpenSettings: {}
  )
  .frame(width: 340)
  .preferredColorScheme(.dark)
}

#Preview("3. Token Rejected - Light") {
  PopoverContentView(
    state: .token,
    repoCount: 5,
    lastUpdated: Date().addingTimeInterval(-86400 * 4),
    isRefreshing: false,
    snapshot: PopoverPreviewData.failingSnapshot,
    showAllStale: .constant(false),
    onRefresh: {},
    onOpenSettings: {}
  )
  .frame(width: 340)
  .preferredColorScheme(.light)
}

#Preview("3. Token Rejected - Dark") {
  PopoverContentView(
    state: .token,
    repoCount: 5,
    lastUpdated: Date().addingTimeInterval(-86400 * 4),
    isRefreshing: false,
    snapshot: PopoverPreviewData.failingSnapshot,
    showAllStale: .constant(false),
    onRefresh: {},
    onOpenSettings: {}
  )
  .frame(width: 340)
  .preferredColorScheme(.dark)
}

#Preview("4. Offline - Light") {
  PopoverContentView(
    state: .offline,
    repoCount: 5,
    lastUpdated: Date().addingTimeInterval(-2520),
    isRefreshing: false,
    snapshot: PopoverPreviewData.failingSnapshot,
    showAllStale: .constant(false),
    onRefresh: {},
    onOpenSettings: {}
  )
  .frame(width: 340)
  .preferredColorScheme(.light)
}

#Preview("4. Offline - Dark") {
  PopoverContentView(
    state: .offline,
    repoCount: 5,
    lastUpdated: Date().addingTimeInterval(-2520),
    isRefreshing: false,
    snapshot: PopoverPreviewData.failingSnapshot,
    showAllStale: .constant(false),
    onRefresh: {},
    onOpenSettings: {}
  )
  .frame(width: 340)
  .preferredColorScheme(.dark)
}

#Preview("5. Error (Server) - Light") {
  PopoverContentView(
    state: .error,
    repoCount: 5,
    lastUpdated: Date().addingTimeInterval(-1800),
    isRefreshing: false,
    snapshot: PopoverPreviewData.serverErrorSnapshot,
    showAllStale: .constant(false),
    onRefresh: {},
    onOpenSettings: {}
  )
  .frame(width: 340)
  .preferredColorScheme(.light)
}

#Preview("5. Error (Server) - Dark") {
  PopoverContentView(
    state: .error,
    repoCount: 5,
    lastUpdated: Date().addingTimeInterval(-1800),
    isRefreshing: false,
    snapshot: PopoverPreviewData.serverErrorSnapshot,
    showAllStale: .constant(false),
    onRefresh: {},
    onOpenSettings: {}
  )
  .frame(width: 340)
  .preferredColorScheme(.dark)
}

#Preview("6. First Run Setup - Light") {
  PopoverContentView(
    state: .setup,
    repoCount: 0,
    lastUpdated: nil,
    isRefreshing: false,
    snapshot: nil,
    showAllStale: .constant(false),
    onRefresh: {},
    onOpenSettings: {}
  )
  .frame(width: 340)
  .preferredColorScheme(.light)
}

#Preview("6. First Run Setup - Dark") {
  PopoverContentView(
    state: .setup,
    repoCount: 0,
    lastUpdated: nil,
    isRefreshing: false,
    snapshot: nil,
    showAllStale: .constant(false),
    onRefresh: {},
    onOpenSettings: {}
  )
  .frame(width: 340)
  .preferredColorScheme(.dark)
}
