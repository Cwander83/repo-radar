import Foundation

/// High-level presentation states of the RepoRadar desktop widget.
public enum WidgetState: Sendable, Equatable {
  /// First run before the host app writes any snapshot.
  case firstRun

  /// No repositories configured to watch.
  case noRepos

  /// Authentication token was rejected by GitHub (expired, missing, or unauthorized).
  case tokenError(detail: String)

  /// Repositories have active items (failing CI, pull requests, or stale branches).
  case data(WidgetSnapshot)

  /// All watched repositories are clear (all CI checks passing, no open PRs or stale branches).
  case allClear(WidgetSnapshot)

  /// Network is unreachable. Displays cached snapshot (dimmed) if available.
  case offline(snapshot: WidgetSnapshot?, detail: String?)

  /// GitHub rate limit exceeded. Displays cached snapshot (dimmed) with reset time.
  case rateLimited(snapshot: WidgetSnapshot?, resetAt: Date?, detail: String?)

  /// Non-token error occurred (server 5xx, corrupt file, unsupported version).
  case error(detail: String)

  /// Whether data displayed in the widget should appear dimmed.
  public var isDimmed: Bool {
    switch self {
    case .offline, .rateLimited:
      return true
    default:
      return false
    }
  }

  /// The underlying snapshot if one is associated with this state.
  public var snapshot: WidgetSnapshot? {
    switch self {
    case .data(let snapshot), .allClear(let snapshot):
      return snapshot
    case .offline(let snapshot, _), .rateLimited(let snapshot, _, _):
      return snapshot
    case .firstRun, .noRepos, .tokenError, .error:
      return nil
    }
  }

  /// Headline title for empty, error, or status displays.
  public var statusTitle: String {
    switch self {
    case .firstRun:
      return "Welcome to Repo Radar"
    case .noRepos:
      return "No Repositories"
    case .tokenError:
      return "Authentication Error"
    case .allClear:
      return "All Clear"
    case .data:
      return "Repo Radar"
    case .offline:
      return "Offline"
    case .rateLimited:
      return "Rate Limited"
    case .error:
      return "Error"
    }
  }

  /// Secondary descriptive text explaining the current state.
  public var statusSubtitle: String? {
    switch self {
    case .firstRun:
      return "Open Repo Radar in the menu bar to get started."
    case .noRepos:
      return "Add repositories to watch in Settings."
    case .tokenError(let detail):
      return detail
    case .allClear:
      return "All CI checks passing and branches up to date."
    case .data:
      return nil
    case .offline(_, let detail):
      return detail ?? "Showing cached data"
    case .rateLimited(_, let resetAt, let detail):
      if let resetAt {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return "Resets at \(formatter.string(from: resetAt))"
      }
      return detail ?? "GitHub rate limit exceeded"
    case .error(let detail):
      return detail
    }
  }

  /// Number of active failing CI runs.
  public var failingCount: Int {
    snapshot?.failingCI.count ?? 0
  }

  /// Number of in-progress CI runs.
  public var runningCount: Int {
    snapshot?.runningCI.count ?? 0
  }

  /// Number of open pull requests.
  public var prCount: Int {
    snapshot?.pullRequests.count ?? 0
  }

  /// Number of PRs awaiting user review.
  public var reviewRequestCount: Int {
    snapshot?.pullRequests.filter { $0.isReviewRequested }.count ?? 0
  }

  /// Number of stale branches.
  public var staleCount: Int {
    snapshot?.staleBranches.count ?? 0
  }

  /// Whether the state contains any failing CI or review requests requiring action.
  public var hasActionableItems: Bool {
    failingCount > 0 || reviewRequestCount > 0
  }

  /// Computes the active widget state from a snapshot read result and watched repositories.
  public static func current(
    readResult: SnapshotReadResult,
    watchedRepos: [String] = []
  ) -> WidgetState {
    switch readResult {
    case .missing:
      return .firstRun

    case .corrupt(let detail):
      return .error(detail: detail)

    case .unsupportedVersion(let version):
      return .error(detail: "Unsupported snapshot version \(version). Update Repo Radar.")

    case .success(let snapshot):
      return current(snapshot: snapshot, watchedRepos: watchedRepos)
    }
  }

  /// Computes the active widget state from an existing snapshot and watched repositories.
  public static func current(
    snapshot: WidgetSnapshot?,
    watchedRepos: [String] = []
  ) -> WidgetState {
    guard let snapshot else {
      return .firstRun
    }

    switch snapshot.status {
    case .missing:
      return .firstRun

    case .tokenError(let detail):
      return .tokenError(detail: detail)

    case .serverError(let detail):
      return .error(detail: detail ?? "GitHub server error")

    case .corrupt(let detail):
      return .error(detail: detail)

    case .unsupportedVersion(let version):
      return .error(detail: "Unsupported snapshot version \(version)")

    case .offline(let detail):
      return .offline(snapshot: snapshot, detail: detail)

    case .rateLimited(let resetAt, let detail):
      return .rateLimited(snapshot: snapshot, resetAt: resetAt, detail: detail)

    case .ok:
      // Check if watched repositories list is empty
      if !watchedRepos.isEmpty {
        // Explicit watched repos present
      } else if snapshot.repositoryAccess.isEmpty &&
                snapshot.failingCI.isEmpty &&
                snapshot.runningCI.isEmpty &&
                snapshot.pullRequests.isEmpty &&
                snapshot.staleBranches.isEmpty &&
                snapshot.rateLimit == nil {
        return .noRepos
      }

      let hasItems = !snapshot.failingCI.isEmpty ||
                     !snapshot.pullRequests.isEmpty ||
                     !snapshot.staleBranches.isEmpty

      if hasItems {
        return .data(snapshot)
      } else {
        return .allClear(snapshot)
      }
    }
  }
}
