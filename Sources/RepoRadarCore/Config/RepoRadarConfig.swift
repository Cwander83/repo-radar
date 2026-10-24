import Foundation

/// Polling intervals supported by RepoRadar.
public enum PollInterval: Int, Codable, Sendable, CaseIterable, Comparable {
  case fiveMinutes = 5
  case tenMinutes = 10
  case fifteenMinutes = 15

  public static let `default`: PollInterval = .fiveMinutes

  public var minutes: Int { rawValue }

  public var timeInterval: TimeInterval {
    TimeInterval(rawValue * 60)
  }

  public static func < (lhs: PollInterval, rhs: PollInterval) -> Bool {
    lhs.rawValue < rhs.rawValue
  }

  public init(minutes: Int) {
    switch minutes {
    case 10:
      self = .tenMinutes
    case 15:
      self = .fifteenMinutes
    default:
      self = .fiveMinutes
    }
  }
}

/// Errors occurring during repository identifier validation.
public enum RepoValidationError: Error, Sendable, Equatable, CustomStringConvertible {
  case empty
  case missingSlash(String)
  case multipleSlashes(String)
  case emptyOwner(String)
  case emptyRepo(String)
  case invalidCharacters(String)
  case duplicate(String)

  public var description: String {
    switch self {
    case .empty:
      return "Repository name cannot be empty."
    case .missingSlash(let repo):
      return "Repository '\(repo)' must be in 'owner/name' format."
    case .multipleSlashes(let repo):
      return "Repository '\(repo)' contains multiple slashes."
    case .emptyOwner(let repo):
      return "Repository '\(repo)' has an empty owner."
    case .emptyRepo(let repo):
      return "Repository '\(repo)' has an empty repository name."
    case .invalidCharacters(let repo):
      return "Repository '\(repo)' contains invalid characters."
    case .duplicate(let repo):
      return "Duplicate repository: '\(repo)'."
    }
  }
}

/// Errors occurring during configuration validation.
public enum ConfigValidationError: Error, Sendable, Equatable, CustomStringConvertible {
  case invalidRepo(RepoValidationError)
  case invalidStaleDays(Int)
  case tooManyRepos(count: Int, max: Int)

  public var description: String {
    switch self {
    case .invalidRepo(let error):
      return error.description
    case .invalidStaleDays(let days):
      return "Stale days must be at least 1 (got \(days))."
    case .tooManyRepos(let count, let max):
      return "Maximum of \(max) watched repositories allowed (got \(count))."
    }
  }
}

/// Strongly typed configuration for RepoRadar.
public struct RepoRadarConfig: Codable, Sendable, Equatable {
  /// Maximum number of watched repositories supported by the single-query GraphQL fetcher.
  public static let maxWatchedRepos: Int = 25

  public static let defaultPollInterval: PollInterval = .fiveMinutes
  public static let defaultStaleDays: Int = 30
  public static let defaultRefreshOnWake: Bool = true
  public static let defaultLaunchAtLogin: Bool = false
  public static let defaultShowMenuBarCount: Bool = true
  public static let defaultCINotifications: Bool = false

  /// Repositories watched by RepoRadar, formatted as 'owner/name'.
  public var watchedRepos: [String]

  /// Interval between automatic background refreshes.
  public var pollInterval: PollInterval

  /// Inactivity threshold in days for classifying a branch as stale.
  public var staleDays: Int

  /// Whether to refresh immediately when the Mac wakes from sleep.
  public var refreshOnWake: Bool

  /// Whether to launch the host app automatically on login.
  public var launchAtLogin: Bool

  /// Whether to show the failing CI count badge in the menu bar.
  public var showMenuBarCount: Bool

  /// Whether to trigger a local notification when CI status changes to failing.
  public var ciNotifications: Bool

  public init(
    watchedRepos: [String] = [],
    pollInterval: PollInterval = defaultPollInterval,
    staleDays: Int = defaultStaleDays,
    refreshOnWake: Bool = defaultRefreshOnWake,
    launchAtLogin: Bool = defaultLaunchAtLogin,
    showMenuBarCount: Bool = defaultShowMenuBarCount,
    ciNotifications: Bool = defaultCINotifications
  ) {
    self.watchedRepos = watchedRepos
    self.pollInterval = pollInterval
    self.staleDays = staleDays
    self.refreshOnWake = refreshOnWake
    self.launchAtLogin = launchAtLogin
    self.showMenuBarCount = showMenuBarCount
    self.ciNotifications = ciNotifications
  }

  /// Default configuration instance.
  public static let `default` = RepoRadarConfig()

  /// Validates a single repository string in 'owner/name' format.
  @discardableResult
  public static func validate(repo: String) throws -> String {
    let trimmed = repo.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      throw RepoValidationError.empty
    }

    let parts = trimmed.split(separator: "/", omittingEmptySubsequences: false)
    guard parts.count >= 2 else {
      throw RepoValidationError.missingSlash(trimmed)
    }
    guard parts.count == 2 else {
      throw RepoValidationError.multipleSlashes(trimmed)
    }

    let owner = String(parts[0])
    let repoName = String(parts[1])

    guard !owner.isEmpty else {
      throw RepoValidationError.emptyOwner(trimmed)
    }
    guard !repoName.isEmpty else {
      throw RepoValidationError.emptyRepo(trimmed)
    }

    let allowed = CharacterSet(
      charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.-")
    guard trimmed.unicodeScalars.allSatisfy({ allowed.contains($0) || $0 == "/" }) else {
      throw RepoValidationError.invalidCharacters(trimmed)
    }

    return "\(owner)/\(repoName)"
  }

  /// Validates an array of repository identifiers, verifying format and absence of duplicates.
  public static func validate(repos: [String]) throws -> [String] {
    var seen = Set<String>()
    var validated: [String] = []

    for raw in repos {
      let clean = try validate(repo: raw)
      let canonicalKey = clean.lowercased()
      if seen.contains(canonicalKey) {
        throw RepoValidationError.duplicate(clean)
      }
      seen.insert(canonicalKey)
      validated.append(clean)
    }

    return validated
  }

  /// Validates the configuration, throwing on malformed repos, duplicates, excess repos, or invalid stale days.
  public func validate() throws {
    guard watchedRepos.count <= Self.maxWatchedRepos else {
      throw ConfigValidationError.tooManyRepos(count: watchedRepos.count, max: Self.maxWatchedRepos)
    }

    do {
      _ = try Self.validate(repos: watchedRepos)
    } catch let error as RepoValidationError {
      throw ConfigValidationError.invalidRepo(error)
    }

    guard staleDays >= 1 else {
      throw ConfigValidationError.invalidStaleDays(staleDays)
    }
  }

  /// Returns a sanitized copy with trimmed, deduplicated repos clamped to maxWatchedRepos and clamped staleDays.
  public func sanitized() -> RepoRadarConfig {
    var seen = Set<String>()
    var deduplicated: [String] = []

    for raw in watchedRepos {
      if let clean = try? Self.validate(repo: raw) {
        let canonicalKey = clean.lowercased()
        if !seen.contains(canonicalKey) {
          seen.insert(canonicalKey)
          deduplicated.append(clean)
          if deduplicated.count == Self.maxWatchedRepos {
            break
          }
        }
      }
    }

    return RepoRadarConfig(
      watchedRepos: deduplicated,
      pollInterval: pollInterval,
      staleDays: max(1, staleDays),
      refreshOnWake: refreshOnWake,
      launchAtLogin: launchAtLogin,
      showMenuBarCount: showMenuBarCount,
      ciNotifications: ciNotifications
    )
  }
}
