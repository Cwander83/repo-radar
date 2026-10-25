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
