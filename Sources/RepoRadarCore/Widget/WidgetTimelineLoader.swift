import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

/// A timeline entry representing the state of the RepoRadar widget at a specific point in time.
public struct RepoRadarWidgetEntry: Sendable, Equatable {
  public let date: Date
  public let state: WidgetState
  public let watchedRepos: [String]
  public let section: WidgetSectionChoice
  public let repositoryFilter: String?

  public var snapshot: WidgetSnapshot? {
    state.snapshot
  }

  public init(
    date: Date = Date(),
    state: WidgetState,
    watchedRepos: [String] = [],
    section: WidgetSectionChoice = .all,
    repositoryFilter: String? = nil
  ) {
    self.date = date
    self.state = state
    self.watchedRepos = watchedRepos
    self.section = section
    self.repositoryFilter = repositoryFilter
  }
}

#if canImport(WidgetKit)
extension RepoRadarWidgetEntry: TimelineEntry {}
#endif

/// Reads snapshot and configuration from the shared App Group container and constructs widget timeline entries.
public final class WidgetTimelineLoader: Sendable {
  public let snapshotStore: SnapshotStore?
  public let configStore: ConfigStore?

  public init(
    snapshotStore: SnapshotStore? = SnapshotStore(),
    configStore: ConfigStore? = ConfigStore()
  ) {
    self.snapshotStore = snapshotStore
    self.configStore = configStore
  }

  /// Loads the latest snapshot and config to build the active widget entry, applying optional section and repo filters.
  public func loadEntry(
    section: WidgetSectionChoice = .all,
    repository: String? = nil,
    now: Date = Date()
  ) -> RepoRadarWidgetEntry {
    let watchedRepos = configStore?.load().watchedRepos ?? []

    guard let snapshotStore else {
      return RepoRadarWidgetEntry(
        date: now,
        state: .error(detail: "App Group container unavailable"),
        watchedRepos: watchedRepos,
        section: section,
        repositoryFilter: repository
      )
    }

    if let repository, !repository.isEmpty, repository.lowercased() != "all" {
      let trimmedTarget = repository.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      let isWatched = watchedRepos.contains {
        $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == trimmedTarget
      }
      if !isWatched {
        return RepoRadarWidgetEntry(
          date: now,
          state: .error(detail: "\(repository) is no longer watched. Edit the widget to pick another."),
          watchedRepos: watchedRepos,
          section: section,
          repositoryFilter: repository
        )
      }
    }

    let readResult = snapshotStore.readResult()
    switch readResult {
    case .missing:
      return RepoRadarWidgetEntry(
        date: now,
        state: .firstRun,
        watchedRepos: watchedRepos,
        section: section,
        repositoryFilter: repository
      )

    case .corrupt(let detail):
      return RepoRadarWidgetEntry(
        date: now,
        state: .error(detail: detail),
        watchedRepos: watchedRepos,
        section: section,
        repositoryFilter: repository
      )

    case .unsupportedVersion(let version):
      return RepoRadarWidgetEntry(
        date: now,
        state: .error(detail: "Unsupported snapshot version \(version). Update Repo Radar."),
        watchedRepos: watchedRepos,
        section: section,
        repositoryFilter: repository
      )

    case .success(let rawSnapshot):
      let filteredSnapshot = rawSnapshot.filtered(section: section, repository: repository)
      let state = WidgetState.current(snapshot: filteredSnapshot, watchedRepos: watchedRepos)
      return RepoRadarWidgetEntry(
        date: now,
        state: state,
        watchedRepos: watchedRepos,
        section: section,
        repositoryFilter: repository
      )
    }
  }
}

// MARK: - Preview Fixtures

extension RepoRadarWidgetEntry {
  /// Sample entry filtered by section and repository for widget gallery previews.
  public static func previewData(
    section: WidgetSectionChoice = .all,
    repository: String? = nil
  ) -> RepoRadarWidgetEntry {
    guard case .data(let snapshot) = previewData.state else {
      return previewData
    }
    let filtered = snapshot.filtered(section: section, repository: repository)
    let state = WidgetState.current(snapshot: filtered, watchedRepos: previewData.watchedRepos)
    return RepoRadarWidgetEntry(
      date: previewData.date,
      state: state,
      watchedRepos: previewData.watchedRepos,
      section: section,
      repositoryFilter: repository
    )
  }

  /// Sample entry showing active data with failing CI, review requested PRs, and stale branches.
  public static var previewData: RepoRadarWidgetEntry {
    RepoRadarWidgetEntry(
      date: Date(),
      state: .data(
        WidgetSnapshot(
          updatedAt: Date().addingTimeInterval(-180),
          status: .ok,
          failingCI: [
            FailingCIItem(
              repo: "Cwander83/gravity-bar",
              ref: "main",
              kind: .mainBranch,
              check: "Build & Test (macOS)",
              conclusion: "FAILURE",
              url: URL(string: "https://github.com/Cwander83/gravity-bar/actions/runs/1")!,
              startedAt: Date().addingTimeInterval(-720),
              completedAt: Date().addingTimeInterval(-660)
            ),
            FailingCIItem(
              repo: "Cwander83/repo-radar",
              ref: "#12 add-graphql-fetcher",
              kind: .myPullRequest,
              check: "Security & Secret Scan",
              conclusion: "FAILURE",
              url: URL(string: "https://github.com/Cwander83/repo-radar/actions/runs/2")!,
              startedAt: Date().addingTimeInterval(-3600),
              completedAt: Date().addingTimeInterval(-3540)
            )
          ],
          runningCI: [
            RunningCIItem(
              repo: "Cwander83/ollama-bar",
              ref: "develop",
              kind: .defaultBranch,
              check: "Build & Test (macOS)",
              status: "IN_PROGRESS",
              url: URL(string: "https://github.com/Cwander83/ollama-bar/actions/runs/3")!,
              startedAt: Date().addingTimeInterval(-180)
            )
          ],
          pullRequests: [
            ClassifiedPullRequest(
              repo: "Cwander83/gravity-bar",
              number: 14,
              title: "Fix popover hover state",
              url: URL(string: "https://github.com/Cwander83/gravity-bar/pull/14")!,
              headRefName: "fix-hover",
              reason: .reviewRequested,
              authorLogin: "collaborator",
              updatedAt: Date().addingTimeInterval(-18000)
            ),
            ClassifiedPullRequest(
              repo: "Cwander83/repo-radar",
              number: 12,
              title: "Add GraphQL fetcher",
              url: URL(string: "https://github.com/Cwander83/repo-radar/pull/12")!,
              headRefName: "add-graphql-fetcher",
              reason: .mine,
              authorLogin: "Cwander83",
              updatedAt: Date().addingTimeInterval(-172800)
            )
          ],
          staleBranches: [
            StaleBranchItem(
              repo: "Cwander83/gravity-bar",
              branch: "feat/weekly-window",
              ageDays: 58,
              lastCommitDate: Date().addingTimeInterval(-86400 * 58),
              lastCommitOid: "abc1234"
            ),
            StaleBranchItem(
              repo: "Cwander83/repo-radar",
              branch: "spike/app-groups",
              ageDays: 41,
              lastCommitDate: Date().addingTimeInterval(-86400 * 41),
              lastCommitOid: "def5678"
            )
          ],
          repositoryAccess: [
            RepositoryAccessItem(name: "Cwander83/repo-radar", defaultBranch: "develop", hasAccess: true),
            RepositoryAccessItem(name: "Cwander83/gravity-bar", defaultBranch: "main", hasAccess: true),
            RepositoryAccessItem(name: "Cwander83/ollama-bar", defaultBranch: "main", hasAccess: true)
          ],
          rateLimit: SnapshotRateLimit(remaining: 4950, limit: 5000, resetAt: Date().addingTimeInterval(3000), cost: 1)
        )
      ),
      watchedRepos: ["Cwander83/repo-radar", "Cwander83/gravity-bar", "Cwander83/ollama-bar"]
    )
  }

  /// Sample entry showing all repositories clear (no failing CI, PRs, or stale branches).
  public static var previewAllClear: RepoRadarWidgetEntry {
    RepoRadarWidgetEntry(
      date: Date(),
      state: .allClear(
        WidgetSnapshot(
          updatedAt: Date().addingTimeInterval(-60),
          status: .ok,
          failingCI: [],
          runningCI: [],
          pullRequests: [],
          staleBranches: [],
          repositoryAccess: [
            RepositoryAccessItem(name: "Cwander83/repo-radar", defaultBranch: "develop", hasAccess: true),
            RepositoryAccessItem(name: "Cwander83/gravity-bar", defaultBranch: "main", hasAccess: true)
          ],
          rateLimit: SnapshotRateLimit(remaining: 4980, limit: 5000, resetAt: Date().addingTimeInterval(3200), cost: 1)
        )
      ),
      watchedRepos: ["Cwander83/repo-radar", "Cwander83/gravity-bar"]
    )
  }

  /// Sample entry showing first run before host app writes snapshot.
  public static var previewFirstRun: RepoRadarWidgetEntry {
    RepoRadarWidgetEntry(
      date: Date(),
      state: .firstRun,
      watchedRepos: []
    )
  }

  /// Sample entry showing no repositories configured.
  public static var previewNoRepos: RepoRadarWidgetEntry {
    RepoRadarWidgetEntry(
      date: Date(),
      state: .noRepos,
      watchedRepos: []
    )
  }

  /// Sample entry showing authentication / token error.
  public static var previewTokenError: RepoRadarWidgetEntry {
    RepoRadarWidgetEntry(
      date: Date(),
      state: .tokenError(detail: "GitHub token expired on Oct 24, 2026"),
      watchedRepos: ["Cwander83/repo-radar"]
    )
  }

  /// Sample entry showing offline state with cached data.
  public static var previewOffline: RepoRadarWidgetEntry {
    var cached = previewData
    if case .data(let snapshot) = cached.state {
      cached = RepoRadarWidgetEntry(
        date: Date(),
        state: .offline(snapshot: snapshot, detail: "Network unreachable"),
        watchedRepos: cached.watchedRepos
      )
    }
    return cached
  }

  /// Sample entry showing rate-limited state with cached data.
  public static var previewRateLimited: RepoRadarWidgetEntry {
    var cached = previewData
    if case .data(let snapshot) = cached.state {
      cached = RepoRadarWidgetEntry(
        date: Date(),
        state: .rateLimited(
          snapshot: snapshot,
          resetAt: Date().addingTimeInterval(1240),
          detail: "GitHub rate limit exceeded"
        ),
        watchedRepos: cached.watchedRepos
      )
    }
    return cached
  }

  /// Sample entry showing general error state.
  public static var previewError: RepoRadarWidgetEntry {
    RepoRadarWidgetEntry(
      date: Date(),
      state: .error(detail: "GitHub API error (HTTP 503)"),
      watchedRepos: ["Cwander83/repo-radar"]
    )
  }
}
