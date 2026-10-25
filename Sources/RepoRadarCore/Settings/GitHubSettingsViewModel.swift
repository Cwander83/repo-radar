import Foundation
import Combine

/// Status of the GitHub personal access token.
public enum GitHubTokenStatus: Equatable, Sendable {
  case valid
  case expired(Date?)
  case invalid(String?)
  case missing

  public var label: String {
    switch self {
    case .valid:
      return "Valid"
    case .expired:
      return "Expired"
    case .invalid:
      return "Invalid"
    case .missing:
      return "Missing"
    }
  }

  public var isExpired: Bool {
    if case .expired = self { return true }
    return false
  }
}

/// Closure type for token validation.
public typealias TokenValidator = @Sendable (String) async throws -> TokenValidationResult

/// View model driving the GitHub Token tab in Settings.
@MainActor
public final class GitHubSettingsViewModel: ObservableObject {
  public let tokenStore: any TokenStore
  public let configStore: ConfigStore
  public let client: GitHubGraphQLClient
  public var tokenValidator: TokenValidator?
  public var onRefreshRequest: (() -> Void)?

  private var cancellables = Set<AnyCancellable>()

  // Keychain & status state
  @Published public var hasToken: Bool = false
  @Published public var maskedToken: String?
  @Published public var status: GitHubTokenStatus = .missing
  @Published public var account: String?
  @Published public var expiresAt: Date?
  @Published public var rateLimit: SnapshotRateLimit?
  @Published public var lastRefreshDate: Date?
  @Published public var latestSnapshot: WidgetSnapshot?

  // Replace / Add token form state
  @Published public var isReplacingToken: Bool = false
  @Published public var tokenInput: String = ""
  @Published public var isValidating: Bool = false
  @Published public var validationError: String?

  // UserDefaults cache keys for token metadata
  public enum CacheKeys {
    public static let cachedAccount = "reporadar.github.cachedAccount"
    public static let cachedExpiration = "reporadar.github.cachedExpiration"
  }

  public init(
    tokenStore: any TokenStore,
    configStore: ConfigStore,
    snapshot: WidgetSnapshot? = nil,
    snapshotPublisher: AnyPublisher<WidgetSnapshot?, Never>? = nil,
    client: GitHubGraphQLClient = GitHubGraphQLClient(),
    tokenValidator: TokenValidator? = nil,
    onRefreshRequest: (() -> Void)? = nil
  ) {
    self.tokenStore = tokenStore
    self.configStore = configStore
    self.client = client
    self.tokenValidator = tokenValidator
    self.onRefreshRequest = onRefreshRequest

    loadInitialState()
    updateFromSnapshot(snapshot)

    if let snapshotPublisher {
      snapshotPublisher
        .sink { [weak self] newSnapshot in
          if Thread.isMainThread {
            self?.updateFromSnapshot(newSnapshot)
          } else {
            Task { @MainActor [weak self] in
              self?.updateFromSnapshot(newSnapshot)
            }
          }
        }
        .store(in: &cancellables)
    }
  }

  public convenience init(
    tokenStore: any TokenStore,
    configStore: ConfigStore,
    scheduler: RefreshScheduler?,
    client: GitHubGraphQLClient = GitHubGraphQLClient(),
    tokenValidator: TokenValidator? = nil,
    onRefreshRequest: (() -> Void)? = nil
  ) {
    self.init(
      tokenStore: tokenStore,
      configStore: configStore,
      snapshot: scheduler?.latestSnapshot,
      snapshotPublisher: scheduler?.$latestSnapshot.eraseToAnyPublisher(),
      client: client,
      tokenValidator: tokenValidator,
      onRefreshRequest: onRefreshRequest
    )
  }

  /// Reloads token presence, masked representation, and cached metadata from storage.
  public func loadInitialState() {
    do {
      if let token = try tokenStore.read(), !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        self.hasToken = true
        self.maskedToken = Self.maskToken(token)

        // Read cached metadata from ConfigStore UserDefaults
        let defaults = configStore.userDefaults
        self.account = defaults.string(forKey: CacheKeys.cachedAccount)
        let expTimestamp = defaults.double(forKey: CacheKeys.cachedExpiration)
        if expTimestamp > 0 {
          self.expiresAt = Date(timeIntervalSince1970: expTimestamp)
        }

        // Determine if already expired based on cached expiry date
        if let expiresAt, expiresAt < Date() {
          self.status = .expired(expiresAt)
        } else {
          self.status = .valid
        }
      } else {
        self.hasToken = false
        self.maskedToken = nil
        self.status = .missing
      }
    } catch {
      self.hasToken = false
      self.maskedToken = nil
      self.status = .invalid(error.localizedDescription)
    }
  }

  /// Updates token status and metadata from a newly published widget snapshot.
  public func updateFromSnapshot(_ snapshot: WidgetSnapshot?) {
    guard let snapshot else { return }
    self.latestSnapshot = snapshot

    if let rl = snapshot.rateLimit {
      self.rateLimit = rl
    }

    if snapshot.status.isOK {
      self.lastRefreshDate = snapshot.updatedAt
      if hasToken {
        if let expiresAt, expiresAt < Date() {
          self.status = .expired(expiresAt)
        } else {
          self.status = .valid
        }
      }
    } else {
      switch snapshot.status {
      case .tokenError(let detail):
        let lower = detail.lowercased()
        if lower.contains("expired") || (expiresAt != nil && expiresAt! < Date()) {
          self.status = .expired(expiresAt)
        } else if lower.contains("missing") {
          self.status = .missing
          self.hasToken = false
        } else {
          self.status = .invalid(detail)
        }
      default:
        break
      }
    }
  }

  /// Validates a candidate token with one API call before saving to Keychain.
  public func saveToken() async {
    validationError = nil
    let trimmed = tokenInput.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      validationError = "Personal access token cannot be empty."
      return
    }

    isValidating = true
    defer { isValidating = false }

    do {
      let result: TokenValidationResult
      if let tokenValidator {
        result = try await tokenValidator(trimmed)
      } else {
        result = try await client.validateTokenDetails(token: trimmed)
      }

      // Check if the returned expiration date is already in the past
      if let exp = result.expiresAt, exp < Date() {
        validationError = "This personal access token has already expired."
        return
      }

      // Save valid token to Keychain
      try tokenStore.save(token: trimmed)

      // Update cached metadata in ConfigStore UserDefaults
      let defaults = configStore.userDefaults
      defaults.set(result.viewer, forKey: CacheKeys.cachedAccount)
      if let exp = result.expiresAt {
        defaults.set(exp.timeIntervalSince1970, forKey: CacheKeys.cachedExpiration)
      } else {
        defaults.removeObject(forKey: CacheKeys.cachedExpiration)
      }

      self.hasToken = true
      self.maskedToken = Self.maskToken(trimmed)
      self.account = result.viewer
      self.expiresAt = result.expiresAt
      if let rl = result.rateLimit {
        self.rateLimit = SnapshotRateLimit(rateLimit: rl)
      }
      self.status = .valid
      self.isReplacingToken = false
      self.tokenInput = ""

      onRefreshRequest?()
    } catch let error as RepoRadarError {
      switch error {
      case .tokenUnauthorized(let detail):
        let lower = detail.lowercased()
        if lower.contains("expired") {
          validationError = "Token expired on GitHub. Please generate a new token."
        } else {
          validationError = "Invalid token: \(detail)"
        }
      case .rateLimited(let resetAt):
        if let resetAt {
          let timeStr = DateFormatter.localizedString(from: resetAt, dateStyle: .none, timeStyle: .short)
          validationError = "GitHub API rate limit exceeded. Resets at \(timeStr)."
        } else {
          validationError = "GitHub API rate limit exceeded. Please try again later."
        }
      case .offline(let detail):
        validationError = "Unable to validate token: \(detail)"
      case .serverError(_, let detail):
        validationError = "GitHub error: \(detail)"
      default:
        validationError = error.localizedDescription
      }
    } catch {
      validationError = error.localizedDescription
    }
  }

  /// Removes the stored token from Keychain and clears cached metadata.
  public func removeToken() {
    validationError = nil
    do {
      try tokenStore.delete()
    } catch {
      validationError = "Failed to remove token: \(error.localizedDescription)"
      return
    }

    let defaults = configStore.userDefaults
    defaults.removeObject(forKey: CacheKeys.cachedAccount)
    defaults.removeObject(forKey: CacheKeys.cachedExpiration)

    self.hasToken = false
    self.maskedToken = nil
    self.account = nil
    self.expiresAt = nil
    self.status = .missing
    self.isReplacingToken = false
    self.tokenInput = ""

    onRefreshRequest?()
  }

  public func beginReplacingToken() {
    isReplacingToken = true
    tokenInput = ""
    validationError = nil
  }

  public func cancelReplacingToken() {
    isReplacingToken = false
    tokenInput = ""
    validationError = nil
  }

  // MARK: - Display & Formatting Helpers

  public var watchedReposCount: Int {
    configStore.load().watchedRepos.count
  }

  public var repositoryAccessText: String {
    guard let snapshot = latestSnapshot, !snapshot.repositoryAccess.isEmpty else {
      return "—"
    }
    let readable = snapshot.repositoryAccess.filter(\.hasAccess).count
    let total = snapshot.repositoryAccess.count
    return "\(readable) of \(total) watched repos readable"
  }

  public var expirationText: String {
    guard let expiresAt else {
      return "No expiration date"
    }
    return Self.formatExpiration(date: expiresAt)
  }

  public var apiBudgetText: String {
    guard let rateLimit else {
      return "—"
    }
    return Self.formatAPIBudget(remaining: rateLimit.remaining, limit: rateLimit.limit)
  }

  public var lastRefreshText: String {
    guard let lastRefreshDate else {
      return "—"
    }
    return Self.formatLastRefresh(date: lastRefreshDate)
  }

  public var expiredBannerText: String {
    Self.formatExpiredBanner(date: expiresAt)
  }

  nonisolated public static func maskToken(_ token: String) -> String {
    let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.count >= 8 else {
      return "••••••••••••"
    }
    if trimmed.hasPrefix("github_pat_") && trimmed.count >= 15 {
      let suffix = String(trimmed.suffix(4))
      return "github_pat_••••••••••••\(suffix)"
    } else if trimmed.count >= 12 {
      let prefix = String(trimmed.prefix(4))
      let suffix = String(trimmed.suffix(4))
      return "\(prefix)••••••••••••\(suffix)"
    } else {
      let suffix = String(trimmed.suffix(4))
      return "••••••••••••\(suffix)"
    }
  }

  nonisolated public static func formatExpiration(date: Date, now: Date = Date()) -> String {
    let df = DateFormatter()
    df.dateFormat = "MMM d, yyyy"
    df.locale = Locale(identifier: "en_US")
    let formattedDate = df.string(from: date)

    let calendar = Calendar.current
    let components = calendar.dateComponents(
      [.day],
      from: calendar.startOfDay(for: now),
      to: calendar.startOfDay(for: date)
    )
    let days = components.day ?? 0

    if days > 0 {
      return "\(formattedDate) · in \(days) days"
    } else if days == 0 {
      return "\(formattedDate) · expires today"
    } else {
      let absDays = abs(days)
      let dayString = absDays == 1 ? "1 day ago" : "\(absDays) days ago"
      return "\(formattedDate) · \(dayString)"
    }
  }

  nonisolated public static func formatExpiredBanner(date: Date?) -> String {
    if let date {
      let df = DateFormatter()
      df.dateFormat = "MMM d"
      df.locale = Locale(identifier: "en_US")
      let shortDate = df.string(from: date)
      return "Token expired on \(shortDate). Repo Radar stopped refreshing. Paste a new token to resume."
    } else {
      return "Token expired or invalid. Repo Radar stopped refreshing. Paste a new token to resume."
    }
  }

  nonisolated public static func formatLastRefresh(date: Date) -> String {
    let df = DateFormatter()
    df.dateFormat = "MMM d, h:mm a"
    df.locale = Locale(identifier: "en_US")
    return df.string(from: date)
  }

  nonisolated public static func formatAPIBudget(remaining: Int, limit: Int) -> String {
    let nf = NumberFormatter()
    nf.numberStyle = .decimal
    let remStr = nf.string(from: NSNumber(value: remaining)) ?? "\(remaining)"
    let limStr = nf.string(from: NSNumber(value: limit)) ?? "\(limit)"
    return "\(remStr) of \(limStr) points left"
  }
}
