import Foundation

/// Status of the latest repository sync represented in the widget snapshot.
public enum SnapshotStatus: Sendable, Equatable {
  case ok
  case offline(detail: String? = nil)
  case rateLimited(resetAt: Date? = nil, detail: String? = nil)
  case tokenError(detail: String)
  case serverError(detail: String? = nil)
  case missing
  case corrupt(detail: String)
  case unsupportedVersion(version: Int)

  public var isOK: Bool {
    if case .ok = self { return true }
    return false
  }

  public var displayTitle: String {
    switch self {
    case .ok:
      return "All systems normal"
    case .offline:
      return "Offline"
    case .rateLimited:
      return "Rate limited"
    case .tokenError:
      return "Authentication error"
    case .serverError:
      return "GitHub error"
    case .missing:
      return "No data"
    case .corrupt:
      return "Data corrupted"
    case .unsupportedVersion:
      return "Update required"
    }
  }

  public var errorDetail: String? {
    switch self {
    case .tokenError(let detail):
      return detail
    case .serverError(let detail):
      return detail
    case .corrupt(let detail):
      return detail
    case .unsupportedVersion(let version):
      return "Unsupported snapshot version \(version)"
    case .offline(let detail):
      return detail
    case .rateLimited(_, let detail):
      return detail
    case .ok, .missing:
      return nil
    }
  }

  public init(error: RepoRadarError) {
    switch error {
    case .tokenMissing:
      self = .tokenError(detail: "GitHub personal access token missing")
    case .tokenUnauthorized(let detail):
      self = .tokenError(detail: detail)
    case .rateLimited(let resetAt):
      self = .rateLimited(resetAt: resetAt, detail: "GitHub rate limit exceeded")
    case .offline(let detail):
      self = .offline(detail: detail)
    case .serverError(let statusCode, let detail):
      self = .serverError(
        detail: detail.isEmpty ? "GitHub server error (HTTP \(statusCode))" : detail)
    case .graphQL(let errors):
      let message = errors.map(\.message).joined(separator: "; ")
      self = .serverError(detail: message.isEmpty ? "GraphQL query failed" : message)
    case .decodingError(let detail):
      self = .serverError(detail: "Failed to decode GitHub response: \(detail)")
    }
  }
}

extension SnapshotStatus: Codable {
  private enum CodingKeys: String, CodingKey {
    case type
    case detail
    case resetAt
    case version
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .ok:
      try container.encode("ok", forKey: .type)
    case .offline(let detail):
      try container.encode("offline", forKey: .type)
      try container.encodeIfPresent(detail, forKey: .detail)
    case .rateLimited(let resetAt, let detail):
      try container.encode("rateLimited", forKey: .type)
      try container.encodeIfPresent(resetAt, forKey: .resetAt)
      try container.encodeIfPresent(detail, forKey: .detail)
    case .tokenError(let detail):
      try container.encode("tokenError", forKey: .type)
      try container.encode(detail, forKey: .detail)
    case .serverError(let detail):
      try container.encode("serverError", forKey: .type)
      try container.encodeIfPresent(detail, forKey: .detail)
    case .missing:
      try container.encode("missing", forKey: .type)
    case .corrupt(let detail):
      try container.encode("corrupt", forKey: .type)
      try container.encode(detail, forKey: .detail)
    case .unsupportedVersion(let version):
      try container.encode("unsupportedVersion", forKey: .type)
      try container.encode(version, forKey: .version)
    }
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let type = try container.decode(String.self, forKey: .type)
    switch type {
    case "ok":
      self = .ok
    case "offline":
      let detail = try container.decodeIfPresent(String.self, forKey: .detail)
      self = .offline(detail: detail)
    case "rateLimited":
      let resetAt = try container.decodeIfPresent(Date.self, forKey: .resetAt)
      let detail = try container.decodeIfPresent(String.self, forKey: .detail)
      self = .rateLimited(resetAt: resetAt, detail: detail)
    case "tokenError":
      let detail =
        try container.decodeIfPresent(String.self, forKey: .detail) ?? "GitHub token error"
      self = .tokenError(detail: detail)
    case "serverError":
      let detail = try container.decodeIfPresent(String.self, forKey: .detail)
      self = .serverError(detail: detail)
    case "missing":
      self = .missing
    case "corrupt":
      let detail = try container.decodeIfPresent(String.self, forKey: .detail) ?? "Data corrupted"
      self = .corrupt(detail: detail)
    case "unsupportedVersion":
      let version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 0
      self = .unsupportedVersion(version: version)
    default:
      let detail =
        try container.decodeIfPresent(String.self, forKey: .detail) ?? "Unknown status: \(type)"
      self = .corrupt(detail: detail)
    }
  }
}

/// Rate limit usage information stored in the snapshot.
public struct SnapshotRateLimit: Codable, Sendable, Equatable {
  public let remaining: Int
  public let limit: Int
  public let resetAt: Date
  public let cost: Int

  public init(remaining: Int, limit: Int = 5000, resetAt: Date, cost: Int = 1) {
    self.remaining = remaining
    self.limit = limit
    self.resetAt = resetAt
    self.cost = cost
  }

  public init(rateLimit: RateLimit) {
    self.remaining = rateLimit.remaining
    self.limit = rateLimit.limit
    self.resetAt = rateLimit.resetAt
    self.cost = rateLimit.cost
  }
}

/// Top-level snapshot data structure written by host app and read by widget extension.
public struct WidgetSnapshot: Codable, Sendable, Equatable {
  /// Current schema version.
  public static let currentSchemaVersion = 1

  public let schemaVersion: Int
  public let updatedAt: Date
  public let status: SnapshotStatus
  public let failingCI: [FailingCIItem]
  public let runningCI: [RunningCIItem]
  public let pullRequests: [ClassifiedPullRequest]
  public let staleBranches: [StaleBranchItem]
  public let rateLimit: SnapshotRateLimit?

  /// Aggregated classified report view.
  public var report: ClassifiedReport {
    ClassifiedReport(
      failingCI: failingCI,
      runningCI: runningCI,
      pullRequests: pullRequests,
      staleBranches: staleBranches
    )
  }

  public init(
    schemaVersion: Int = WidgetSnapshot.currentSchemaVersion,
    updatedAt: Date = Date(),
    status: SnapshotStatus = .ok,
    failingCI: [FailingCIItem] = [],
    runningCI: [RunningCIItem] = [],
    pullRequests: [ClassifiedPullRequest] = [],
    staleBranches: [StaleBranchItem] = [],
    rateLimit: SnapshotRateLimit? = nil
  ) {
    self.schemaVersion = schemaVersion
    self.updatedAt = updatedAt
    self.status = status
    self.failingCI = failingCI
    self.runningCI = runningCI
    self.pullRequests = pullRequests
    self.staleBranches = staleBranches
    self.rateLimit = rateLimit
  }

  public init(
    schemaVersion: Int = WidgetSnapshot.currentSchemaVersion,
    updatedAt: Date = Date(),
    status: SnapshotStatus = .ok,
    report: ClassifiedReport,
    rateLimit: SnapshotRateLimit? = nil
  ) {
    self.init(
      schemaVersion: schemaVersion,
      updatedAt: updatedAt,
      status: status,
      failingCI: report.failingCI,
      runningCI: report.runningCI,
      pullRequests: report.pullRequests,
      staleBranches: report.staleBranches,
      rateLimit: rateLimit
    )
  }

  /// Creates a fallback empty snapshot with specified status.
  public static func empty(
    status: SnapshotStatus = .missing,
    updatedAt: Date = Date()
  ) -> WidgetSnapshot {
    WidgetSnapshot(
      schemaVersion: currentSchemaVersion,
      updatedAt: updatedAt,
      status: status,
      failingCI: [],
      runningCI: [],
      pullRequests: [],
      staleBranches: [],
      rateLimit: nil
    )
  }
}
