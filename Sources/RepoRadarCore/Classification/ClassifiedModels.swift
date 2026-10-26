import Foundation

/// Reference kind being evaluated for CI checks.
public enum CIRefKind: String, Codable, Sendable, Equatable {
  case defaultBranch
  case mainBranch
  case myPullRequest
}

/// A failing CI check item.
public struct FailingCIItem: Codable, Sendable, Equatable, Identifiable {
  public var id: String { "\(repo)#\(ref)#\(check)" }
  public let repo: String
  public let ref: String
  public let kind: CIRefKind
  public let check: String
  public let conclusion: String
  public let url: URL?
  public let startedAt: Date?
  public let completedAt: Date?

  public init(
    repo: String,
    ref: String,
    kind: CIRefKind,
    check: String,
    conclusion: String,
    url: URL? = nil,
    startedAt: Date? = nil,
    completedAt: Date? = nil
  ) {
    self.repo = repo
    self.ref = ref
    self.kind = kind
    self.check = check
    self.conclusion = conclusion
    self.url = url
    self.startedAt = startedAt
    self.completedAt = completedAt
  }

  /// VoiceOver accessibility label, e.g. "Failing CI, gravity-bar main, Build and Test, 12 minutes ago".
  public func accessibilityLabel(now: Date = Date()) -> String {
    let shortRepo = Self.shortRepositoryName(repo)
    let spokenCheck = Self.spokenText(check)
    if let completedAt {
      let timePart = WidgetSnapshot.spokenRelativeTimeString(from: completedAt, relativeTo: now)
      return "Failing CI, \(shortRepo) \(ref), \(spokenCheck), \(timePart)"
    }
    return "Failing CI, \(shortRepo) \(ref), \(spokenCheck)"
  }

  public static func shortRepositoryName(_ repo: String) -> String {
    if let slash = repo.lastIndex(of: "/") {
      return String(repo[repo.index(after: slash)...])
    }
    return repo
  }

  public static func spokenText(_ text: String) -> String {
    text
      .replacingOccurrences(of: " & ", with: " and ")
      .replacingOccurrences(of: "&", with: " and ")
  }
}

/// A running or queued CI check item.
public struct RunningCIItem: Codable, Sendable, Equatable, Identifiable {
  public var id: String { "\(repo)#\(ref)#\(check)" }
  public let repo: String
  public let ref: String
  public let kind: CIRefKind
  public let check: String
  public let status: String
  public let url: URL?
  public let startedAt: Date?

  public init(
    repo: String,
    ref: String,
    kind: CIRefKind,
    check: String,
    status: String,
    url: URL? = nil,
    startedAt: Date? = nil
  ) {
    self.repo = repo
    self.ref = ref
    self.kind = kind
    self.check = check
    self.status = status
    self.url = url
    self.startedAt = startedAt
  }

  /// VoiceOver accessibility label, e.g. "Running CI, ollama-bar develop, Build and Test, running 3 minutes".
  public func accessibilityLabel(now: Date = Date()) -> String {
    let shortRepo = FailingCIItem.shortRepositoryName(repo)
    let spokenCheck = FailingCIItem.spokenText(check)
    if let startedAt {
      let duration = WidgetSnapshot.spokenDurationString(from: startedAt, relativeTo: now)
      return "Running CI, \(shortRepo) \(ref), \(spokenCheck), running \(duration)"
    }
    return "Running CI, \(shortRepo) \(ref), \(spokenCheck), running"
  }
}

/// Reason a pull request is shown to the user.
public enum PullRequestReason: String, Codable, Sendable, Equatable {
  case reviewRequested
  case mine
}

/// A classified pull request item.
public struct ClassifiedPullRequest: Codable, Sendable, Equatable, Identifiable {
  public var id: String { "\(repo)#\(number)" }
  public let repo: String
  public let number: Int
  public let title: String
  public let url: URL
  public let headRefName: String
  public let reason: PullRequestReason
  public let authorLogin: String?
  public let updatedAt: Date

  public var isReviewRequested: Bool {
    reason == .reviewRequested
  }

  public init(
    repo: String,
    number: Int,
    title: String,
    url: URL,
    headRefName: String,
    reason: PullRequestReason,
    authorLogin: String? = nil,
    updatedAt: Date
  ) {
    self.repo = repo
    self.number = number
    self.title = title
    self.url = url
    self.headRefName = headRefName
    self.reason = reason
    self.authorLogin = authorLogin
    self.updatedAt = updatedAt
  }

  /// VoiceOver accessibility label, e.g. "Review requested pull request, Fix popover hover state, gravity-bar #14, 5 hours ago".
  public func accessibilityLabel(now: Date = Date()) -> String {
    let shortRepo = FailingCIItem.shortRepositoryName(repo)
    let timePart = WidgetSnapshot.spokenRelativeTimeString(from: updatedAt, relativeTo: now)
    let prefix = isReviewRequested ? "Review requested pull request" : "Pull request"
    return "\(prefix), \(title), \(shortRepo) #\(number), \(timePart)"
  }
}

/// A classified stale branch item.
public struct StaleBranchItem: Codable, Sendable, Equatable, Identifiable {
  public var id: String { "\(repo)#\(branch)" }
  public let repo: String
  public let branch: String
  public let ageDays: Int
  public let lastCommitDate: Date
  public let lastCommitOid: String

  public init(
    repo: String,
    branch: String,
    ageDays: Int,
    lastCommitDate: Date,
    lastCommitOid: String
  ) {
    self.repo = repo
    self.branch = branch
    self.ageDays = ageDays
    self.lastCommitDate = lastCommitDate
    self.lastCommitOid = lastCommitOid
  }

  /// VoiceOver accessibility label, e.g. "Stale branch, feat/weekly-window, gravity-bar, 58 days old".
  public var accessibilityLabel: String {
    let shortRepo = FailingCIItem.shortRepositoryName(repo)
    let unit = ageDays == 1 ? "day" : "days"
    return "Stale branch, \(branch), \(shortRepo), \(ageDays) \(unit) old"
  }
}

/// Status of repository reachability and default branch.
public struct RepositoryAccessItem: Codable, Sendable, Equatable, Identifiable {
  public var id: String { name }
  public let name: String
  public let defaultBranch: String?
  public let hasAccess: Bool

  public init(
    name: String,
    defaultBranch: String? = nil,
    hasAccess: Bool = true
  ) {
    self.name = name
    self.defaultBranch = defaultBranch
    self.hasAccess = hasAccess
  }
}

/// Classified report grouping items across all watched repositories.
public struct ClassifiedReport: Codable, Sendable, Equatable {
  public let failingCI: [FailingCIItem]
  public let runningCI: [RunningCIItem]
  public let pullRequests: [ClassifiedPullRequest]
  public let staleBranches: [StaleBranchItem]
  public let repositoryAccess: [RepositoryAccessItem]

  public init(
    failingCI: [FailingCIItem] = [],
    runningCI: [RunningCIItem] = [],
    pullRequests: [ClassifiedPullRequest] = [],
    staleBranches: [StaleBranchItem] = [],
    repositoryAccess: [RepositoryAccessItem] = []
  ) {
    self.failingCI = failingCI
    self.runningCI = runningCI
    self.pullRequests = pullRequests
    self.staleBranches = staleBranches
    self.repositoryAccess = repositoryAccess
  }
}
