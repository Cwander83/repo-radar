import Foundation

/// Top-level response wrapper for the RepoRadar GraphQL query.
public struct GraphQLQueryResponse: Codable, Sendable, Equatable {
  public let data: RepoRadarQueryData?
  public let errors: [GraphQLError]?

  public init(data: RepoRadarQueryData?, errors: [GraphQLError]? = nil) {
    self.data = data
    self.errors = errors
  }
}

/// An error returned by the GitHub GraphQL API.
public struct GraphQLError: Codable, Sendable, Equatable {
  public let message: String
  public let type: String?
  public let path: [String]?

  private enum CodingKeys: String, CodingKey {
    case message, type, path
  }

  public init(message: String, type: String? = nil, path: [String]? = nil) {
    self.message = message
    self.type = type
    self.path = path
  }

  /// GitHub error paths mix field names and list indexes (e.g. `["search", "nodes", 0]`); indexes are kept as strings.
  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.message = try container.decode(String.self, forKey: .message)
    self.type = try container.decodeIfPresent(String.self, forKey: .type)
    if var pathContainer = try? container.nestedUnkeyedContainer(forKey: .path) {
      var path: [String] = []
      while !pathContainer.isAtEnd {
        if let index = try? pathContainer.decode(Int.self) {
          path.append(String(index))
        } else {
          path.append(try pathContainer.decode(String.self))
        }
      }
      self.path = path
    } else {
      self.path = nil
    }
  }
}

/// The `data` payload of the RepoRadar GraphQL query.
public struct RepoRadarQueryData: Codable, Sendable, Equatable {
  public let viewer: Viewer
  public let rateLimit: RateLimit?
  public let search: RepositorySearch

  public init(viewer: Viewer, rateLimit: RateLimit? = nil, search: RepositorySearch) {
    self.viewer = viewer
    self.rateLimit = rateLimit
    self.search = search
  }
}

/// Authenticated user login from `viewer`.
public struct Viewer: Codable, Sendable, Equatable {
  public let login: String

  public init(login: String) {
    self.login = login
  }
}

/// Rate limit information for the query execution.
public struct RateLimit: Codable, Sendable, Equatable {
  public let cost: Int
  public let limit: Int
  public let remaining: Int
  public let resetAt: Date

  public init(cost: Int, limit: Int, remaining: Int, resetAt: Date) {
    self.cost = cost
    self.limit = limit
    self.remaining = remaining
    self.resetAt = resetAt
  }
}

/// Repository search results connection.
public struct RepositorySearch: Codable, Sendable, Equatable {
  public let repositoryCount: Int
  public let nodes: [RepositoryNode]

  public init(repositoryCount: Int, nodes: [RepositoryNode]) {
    self.repositoryCount = repositoryCount
    self.nodes = nodes
  }
}

/// A repository matching the search qualifiers.
public struct RepositoryNode: Codable, Sendable, Equatable {
  public let nameWithOwner: String
  public let url: URL
  public let isPrivate: Bool
  public let isArchived: Bool
  public let defaultBranchRef: RefBranch?
  public let mainRef: RefBranch?
  public let pullRequests: PullRequestConnection
  public let refs: RefConnection

  public init(
    nameWithOwner: String,
    url: URL,
    isPrivate: Bool,
    isArchived: Bool,
    defaultBranchRef: RefBranch? = nil,
    mainRef: RefBranch? = nil,
    pullRequests: PullRequestConnection,
    refs: RefConnection
  ) {
    self.nameWithOwner = nameWithOwner
    self.url = url
    self.isPrivate = isPrivate
    self.isArchived = isArchived
    self.defaultBranchRef = defaultBranchRef
    self.mainRef = mainRef
    self.pullRequests = pullRequests
    self.refs = refs
  }
}

/// A Git reference pointing to a branch head.
public struct RefBranch: Codable, Sendable, Equatable {
  public let name: String
  public let target: CommitTarget?

  public init(name: String, target: CommitTarget? = nil) {
    self.name = name
    self.target = target
  }
}

/// A Git commit object with status rollup and date.
public struct CommitTarget: Codable, Sendable, Equatable {
  public let oid: String
  public let committedDate: Date
  public let url: URL?
  public let statusCheckRollup: StatusCheckRollup?

  public init(
    oid: String,
    committedDate: Date,
    url: URL? = nil,
    statusCheckRollup: StatusCheckRollup? = nil
  ) {
    self.oid = oid
    self.committedDate = committedDate
    self.url = url
    self.statusCheckRollup = statusCheckRollup
  }
}

/// Combined status check rollup across check runs and commit statuses.
public struct StatusCheckRollup: Codable, Sendable, Equatable {
  public let state: String
  public let contexts: StatusCheckRollupContextConnection?

  public init(state: String, contexts: StatusCheckRollupContextConnection? = nil) {
    self.state = state
    self.contexts = contexts
  }
}

/// Contexts connection under a status check rollup.
public struct StatusCheckRollupContextConnection: Codable, Sendable, Equatable {
  public let totalCount: Int
  public let nodes: [StatusCheckRollupContext]

  public init(totalCount: Int, nodes: [StatusCheckRollupContext]) {
    self.totalCount = totalCount
    self.nodes = nodes
  }
}

/// Polymorphic rollup context: either a GitHub Actions `CheckRun` or third-party `StatusContext`.
public enum StatusCheckRollupContext: Codable, Sendable, Equatable {
  case checkRun(CheckRun)
  case statusContext(StatusContext)

  private enum CodingKeys: String, CodingKey {
    case typename = "__typename"
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let typename = try container.decode(String.self, forKey: .typename)
    switch typename {
    case "CheckRun":
      self = .checkRun(try CheckRun(from: decoder))
    case "StatusContext":
      self = .statusContext(try StatusContext(from: decoder))
    default:
      throw DecodingError.dataCorruptedError(
        forKey: .typename,
        in: container,
        debugDescription: "Unsupported rollup context __typename: \(typename)"
      )
    }
  }

  public func encode(to encoder: Encoder) throws {
    switch self {
    case .checkRun(let run):
      try run.encode(to: encoder)
    case .statusContext(let context):
      try context.encode(to: encoder)
    }
  }
}

/// A GitHub Actions check run.
public struct CheckRun: Codable, Sendable, Equatable {
  public let typename: String
  public let name: String
  public let status: String
  public let conclusion: String?
  public let detailsUrl: URL?
  public let startedAt: Date?
  public let completedAt: Date?
  public let checkSuite: CheckSuite?

  public var workflowName: String? {
    checkSuite?.workflowRun?.workflow?.name
  }

  private enum CodingKeys: String, CodingKey {
    case typename = "__typename"
    case name, status, conclusion, detailsUrl, startedAt, completedAt, checkSuite
  }

  public init(
    name: String,
    status: String,
    conclusion: String? = nil,
    detailsUrl: URL? = nil,
    startedAt: Date? = nil,
    completedAt: Date? = nil,
    checkSuite: CheckSuite? = nil
  ) {
    self.typename = "CheckRun"
    self.name = name
    self.status = status
    self.conclusion = conclusion
    self.detailsUrl = detailsUrl
    self.startedAt = startedAt
    self.completedAt = completedAt
    self.checkSuite = checkSuite
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.typename = try container.decodeIfPresent(String.self, forKey: .typename) ?? "CheckRun"
    self.name = try container.decode(String.self, forKey: .name)
    self.status = try container.decode(String.self, forKey: .status)
    self.conclusion = try container.decodeIfPresent(String.self, forKey: .conclusion)
    self.detailsUrl = try container.decodeIfPresent(URL.self, forKey: .detailsUrl)
    self.startedAt = try container.decodeIfPresent(Date.self, forKey: .startedAt)
    self.completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
    self.checkSuite = try container.decodeIfPresent(CheckSuite.self, forKey: .checkSuite)
  }
}

/// Check suite housing the workflow run.
public struct CheckSuite: Codable, Sendable, Equatable {
  public let workflowRun: WorkflowRun?

  public init(workflowRun: WorkflowRun? = nil) {
    self.workflowRun = workflowRun
  }
}

/// Workflow run metadata.
public struct WorkflowRun: Codable, Sendable, Equatable {
  public let workflow: Workflow?

  public init(workflow: Workflow? = nil) {
    self.workflow = workflow
  }
}

/// Workflow identity.
public struct Workflow: Codable, Sendable, Equatable {
  public let name: String

  public init(name: String) {
    self.name = name
  }
}

/// A legacy commit status context (e.g. Vercel, external CI).
public struct StatusContext: Codable, Sendable, Equatable {
  public let typename: String
  public let context: String
  public let state: String
  public let targetUrl: URL?
  public let createdAt: Date?

  private enum CodingKeys: String, CodingKey {
    case typename = "__typename"
    case context, state, targetUrl, createdAt
  }

  public init(
    context: String,
    state: String,
    targetUrl: URL? = nil,
    createdAt: Date? = nil
  ) {
    self.typename = "StatusContext"
    self.context = context
    self.state = state
    self.targetUrl = targetUrl
    self.createdAt = createdAt
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.typename = try container.decodeIfPresent(String.self, forKey: .typename) ?? "StatusContext"
    self.context = try container.decode(String.self, forKey: .context)
    self.state = try container.decode(String.self, forKey: .state)
    self.targetUrl = try container.decodeIfPresent(URL.self, forKey: .targetUrl)
    self.createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
  }
}

/// Pull requests connection.
public struct PullRequestConnection: Codable, Sendable, Equatable {
  public let totalCount: Int
  public let nodes: [PullRequestNode]

  public init(totalCount: Int, nodes: [PullRequestNode]) {
    self.totalCount = totalCount
    self.nodes = nodes
  }
}

/// A pull request on the repository.
public struct PullRequestNode: Codable, Sendable, Equatable {
  public let number: Int
  public let title: String
  public let url: URL
  public let isDraft: Bool
  public let createdAt: Date
  public let updatedAt: Date
  public let headRefName: String
  public let reviewDecision: String?
  public let author: Actor?
  public let reviewRequests: ReviewRequestConnection
  public let commits: PullRequestCommitConnection

  public var headCommit: CommitTarget? {
    commits.nodes.last?.commit
  }

  public init(
    number: Int,
    title: String,
    url: URL,
    isDraft: Bool,
    createdAt: Date,
    updatedAt: Date,
    headRefName: String,
    reviewDecision: String? = nil,
    author: Actor? = nil,
    reviewRequests: ReviewRequestConnection,
    commits: PullRequestCommitConnection
  ) {
    self.number = number
    self.title = title
    self.url = url
    self.isDraft = isDraft
    self.createdAt = createdAt
    self.updatedAt = updatedAt
    self.headRefName = headRefName
    self.reviewDecision = reviewDecision
    self.author = author
    self.reviewRequests = reviewRequests
    self.commits = commits
  }
}

/// An actor (user or bot) who authored a pull request.
public struct Actor: Codable, Sendable, Equatable {
  public let login: String

  public init(login: String) {
    self.login = login
  }
}

/// Review requests connection.
public struct ReviewRequestConnection: Codable, Sendable, Equatable {
  public let nodes: [ReviewRequestNode]

  public init(nodes: [ReviewRequestNode]) {
    self.nodes = nodes
  }
}

/// A review request entry.
public struct ReviewRequestNode: Codable, Sendable, Equatable {
  public let requestedReviewer: RequestedReviewer?

  public init(requestedReviewer: RequestedReviewer? = nil) {
    self.requestedReviewer = requestedReviewer
  }
}

/// Polymorphic reviewer: User or Team.
public enum RequestedReviewer: Codable, Sendable, Equatable {
  case user(login: String)
  case team(slug: String)
  case other(typename: String)

  private enum CodingKeys: String, CodingKey {
    case typename = "__typename"
    case login
    case slug
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let typename = try container.decode(String.self, forKey: .typename)
    switch typename {
    case "User":
      let login = try container.decode(String.self, forKey: .login)
      self = .user(login: login)
    case "Team":
      let slug = try container.decode(String.self, forKey: .slug)
      self = .team(slug: slug)
    default:
      self = .other(typename: typename)
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .user(let login):
      try container.encode("User", forKey: .typename)
      try container.encode(login, forKey: .login)
    case .team(let slug):
      try container.encode("Team", forKey: .typename)
      try container.encode(slug, forKey: .slug)
    case .other(let typename):
      try container.encode(typename, forKey: .typename)
    }
  }
}

/// Pull request commit connection.
public struct PullRequestCommitConnection: Codable, Sendable, Equatable {
  public let nodes: [PullRequestCommitNode]

  public init(nodes: [PullRequestCommitNode]) {
    self.nodes = nodes
  }
}

/// Commit entry inside a pull request.
public struct PullRequestCommitNode: Codable, Sendable, Equatable {
  public let commit: CommitTarget

  public init(commit: CommitTarget) {
    self.commit = commit
  }
}

/// Git refs (branches) connection.
public struct RefConnection: Codable, Sendable, Equatable {
  public let totalCount: Int
  public let pageInfo: PageInfo?
  public let nodes: [RefNode]

  public init(totalCount: Int, pageInfo: PageInfo? = nil, nodes: [RefNode]) {
    self.totalCount = totalCount
    self.pageInfo = pageInfo
    self.nodes = nodes
  }
}

/// Pagination information for ref connections.
public struct PageInfo: Codable, Sendable, Equatable {
  public let hasNextPage: Bool
  public let endCursor: String?

  public init(hasNextPage: Bool, endCursor: String? = nil) {
    self.hasNextPage = hasNextPage
    self.endCursor = endCursor
  }
}

/// A ref (branch) node with protection rule and target commit.
public struct RefNode: Codable, Sendable, Equatable {
  public let name: String
  public let branchProtectionRule: BranchProtectionRule?
  public let associatedPullRequests: AssociatedPullRequests?
  public let target: CommitTarget?

  public init(
    name: String,
    branchProtectionRule: BranchProtectionRule? = nil,
    associatedPullRequests: AssociatedPullRequests? = nil,
    target: CommitTarget? = nil
  ) {
    self.name = name
    self.branchProtectionRule = branchProtectionRule
    self.associatedPullRequests = associatedPullRequests
    self.target = target
  }
}

/// Branch protection rule identity.
public struct BranchProtectionRule: Codable, Sendable, Equatable {
  public let id: String

  public init(id: String) {
    self.id = id
  }
}

/// Open pull requests associated with a branch.
public struct AssociatedPullRequests: Codable, Sendable, Equatable {
  public let totalCount: Int

  public init(totalCount: Int) {
    self.totalCount = totalCount
  }
}
