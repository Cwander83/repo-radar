import Foundation
import Combine
import Testing

@testable import RepoRadarCore

@Suite("GitHubSettingsViewModelTests")
struct GitHubSettingsViewModelTests {
  private func makeTestDefaults() -> (UserDefaults, String) {
    let suiteName = "test-reporadar-github-settings-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    return (defaults, suiteName)
  }

  @Test("Initializes with missing state when no token exists")
  @MainActor
  func initializesWithNoToken() {
    let (defaults, suite) = makeTestDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let tokenStore = InMemoryTokenStore()
    let configStore = ConfigStore(userDefaults: defaults)

    let vm = GitHubSettingsViewModel(tokenStore: tokenStore, configStore: configStore)

    #expect(vm.hasToken == false)
    #expect(vm.maskedToken == nil)
    #expect(vm.status == .missing)
    #expect(vm.status.label == "Missing")
    #expect(vm.status.isExpired == false)
  }

  @Test("Initializes with valid state and masked token when token exists in store")
  @MainActor
  func initializesWithExistingToken() {
    let (defaults, suite) = makeTestDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let tokenStore = InMemoryTokenStore(initialToken: "github_pat_11ABCDEFGHIJKLM3fK2")
    let configStore = ConfigStore(userDefaults: defaults)
    defaults.set("Cwander83", forKey: GitHubSettingsViewModel.CacheKeys.cachedAccount)
    let futureDate = Date().addingTimeInterval(86400 * 30)
    defaults.set(futureDate.timeIntervalSince1970, forKey: GitHubSettingsViewModel.CacheKeys.cachedExpiration)

    let vm = GitHubSettingsViewModel(tokenStore: tokenStore, configStore: configStore)

    #expect(vm.hasToken == true)
    #expect(vm.maskedToken == "github_pat_••••••••••••3fK2")
    #expect(vm.account == "Cwander83")
    #expect(vm.status == .valid)
    #expect(vm.status.label == "Valid")
    #expect(vm.status.isExpired == false)
  }

  @Test("Initializes as expired when cached expiration is in the past")
  @MainActor
  func initializesWithExpiredCachedToken() {
    let (defaults, suite) = makeTestDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let tokenStore = InMemoryTokenStore(initialToken: "github_pat_11ABCDEFGHIJKLM3fK2")
    let configStore = ConfigStore(userDefaults: defaults)
    let pastDate = Date().addingTimeInterval(-86400 * 4)
    defaults.set(pastDate.timeIntervalSince1970, forKey: GitHubSettingsViewModel.CacheKeys.cachedExpiration)

    let vm = GitHubSettingsViewModel(tokenStore: tokenStore, configStore: configStore)

    #expect(vm.hasToken == true)
    #expect(vm.status.isExpired == true)
    #expect(vm.status.label == "Expired")
    #expect(vm.expiredBannerText.contains("Token expired"))
  }

  @Test("Validating and saving a valid token updates store, metadata, and triggers refresh")
  @MainActor
  func validatesAndSavesValidToken() async throws {
    let (defaults, suite) = makeTestDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let tokenStore = InMemoryTokenStore()
    let configStore = ConfigStore(userDefaults: defaults)
    var refreshCount = 0

    let futureExp = Date().addingTimeInterval(86400 * 90)
    let vm = GitHubSettingsViewModel(
      tokenStore: tokenStore,
      configStore: configStore,
      tokenValidator: { token in
        #expect(token == "github_pat_99VALIDTOKEN3fK2")
        return TokenValidationResult(
          viewer: "octocat",
          rateLimit: RateLimit(cost: 1, limit: 5000, remaining: 4950, resetAt: Date()),
          expiresAt: futureExp
        )
      },
      onRefreshRequest: { refreshCount += 1 }
    )

    vm.tokenInput = "  github_pat_99VALIDTOKEN3fK2  "
    await vm.saveToken()

    #expect(vm.validationError == nil)
    #expect(vm.hasToken == true)
    #expect(vm.maskedToken == "github_pat_••••••••••••3fK2")
    #expect(vm.account == "octocat")
    #expect(vm.status == .valid)
    #expect(vm.rateLimit?.remaining == 4950)
    #expect(try tokenStore.read() == "github_pat_99VALIDTOKEN3fK2")
    #expect(refreshCount == 1)
    #expect(vm.tokenInput == "")
    #expect(vm.isReplacingToken == false)
  }

  @Test("Validating an invalid token sets validationError and does not save")
  @MainActor
  func rejectsInvalidToken() async throws {
    let (defaults, suite) = makeTestDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let tokenStore = InMemoryTokenStore()
    let configStore = ConfigStore(userDefaults: defaults)

    let vm = GitHubSettingsViewModel(
      tokenStore: tokenStore,
      configStore: configStore,
      tokenValidator: { _ in
        throw RepoRadarError.tokenUnauthorized(detail: "Bad credentials")
      }
    )

    vm.tokenInput = "invalid-token"
    await vm.saveToken()

    #expect(vm.validationError?.contains("Bad credentials") == true)
    #expect(vm.hasToken == false)
    #expect(try tokenStore.read() == nil)
  }

  @Test("Validating an already-expired token sets validationError and does not save")
  @MainActor
  func rejectsExpiredToken() async throws {
    let (defaults, suite) = makeTestDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let tokenStore = InMemoryTokenStore()
    let configStore = ConfigStore(userDefaults: defaults)

    let vm = GitHubSettingsViewModel(
      tokenStore: tokenStore,
      configStore: configStore,
      tokenValidator: { _ in
        return TokenValidationResult(
          viewer: "octocat",
          rateLimit: nil,
          expiresAt: Date().addingTimeInterval(-3600)
        )
      }
    )

    vm.tokenInput = "github_pat_expired"
    await vm.saveToken()

    #expect(vm.validationError?.contains("already expired") == true)
    #expect(vm.hasToken == false)
    #expect(try tokenStore.read() == nil)
  }

  @Test("Saving empty token sets validation error without calling validator")
  @MainActor
  func rejectsEmptyToken() async {
    let (defaults, suite) = makeTestDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let tokenStore = InMemoryTokenStore()
    let configStore = ConfigStore(userDefaults: defaults)

    let vm = GitHubSettingsViewModel(
      tokenStore: tokenStore,
      configStore: configStore,
      tokenValidator: { _ in
        Issue.record("Validator should not be called for empty token input")
        return TokenValidationResult(viewer: "test", rateLimit: nil)
      }
    )

    vm.tokenInput = "   "
    await vm.saveToken()

    #expect(vm.validationError != nil)
    #expect(vm.hasToken == false)
  }

  @Test("Removing token deletes from store, clears metadata, and triggers refresh")
  @MainActor
  func removesToken() throws {
    let (defaults, suite) = makeTestDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let tokenStore = InMemoryTokenStore(initialToken: "github_pat_valid")
    let configStore = ConfigStore(userDefaults: defaults)
    defaults.set("Cwander83", forKey: GitHubSettingsViewModel.CacheKeys.cachedAccount)
    var refreshCount = 0

    let vm = GitHubSettingsViewModel(
      tokenStore: tokenStore,
      configStore: configStore,
      onRefreshRequest: { refreshCount += 1 }
    )

    #expect(vm.hasToken == true)
    vm.removeToken()

    #expect(vm.hasToken == false)
    #expect(vm.status == .missing)
    #expect(vm.account == nil)
    #expect(vm.maskedToken == nil)
    #expect(try tokenStore.read() == nil)
    #expect(defaults.string(forKey: GitHubSettingsViewModel.CacheKeys.cachedAccount) == nil)
    #expect(refreshCount == 1)
  }

  @Test("Failed token removal sets error and preserves token state")
  @MainActor
  func failedRemoveLeavesTokenStateIntact() {
    let (defaults, suite) = makeTestDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    struct FailingTokenStore: TokenStore {
      func read() throws -> String? { "github_pat_persistent" }
      func save(token: String) throws {}
      func delete() throws {
        throw KeychainError.osStatus(status: -25299, message: "Keychain locked or inaccessible")
      }
      func hasToken() -> Bool { true }
    }

    let tokenStore = FailingTokenStore()
    let configStore = ConfigStore(userDefaults: defaults)
    defaults.set("Cwander83", forKey: GitHubSettingsViewModel.CacheKeys.cachedAccount)
    var refreshCount = 0

    let vm = GitHubSettingsViewModel(
      tokenStore: tokenStore,
      configStore: configStore,
      onRefreshRequest: { refreshCount += 1 }
    )

    #expect(vm.hasToken == true)
    vm.removeToken()

    #expect(vm.validationError?.contains("Failed to remove token") == true)
    #expect(vm.hasToken == true)
    #expect(vm.status == .valid)
    #expect(vm.account == "Cwander83")
    #expect(defaults.string(forKey: GitHubSettingsViewModel.CacheKeys.cachedAccount) == "Cwander83")
    #expect(refreshCount == 0)
  }

  @Test("Validation handles rate limit errors with specific message")
  @MainActor
  func validationHandlesRateLimitError() async {
    let (defaults, suite) = makeTestDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let tokenStore = InMemoryTokenStore()
    let configStore = ConfigStore(userDefaults: defaults)

    let vm = GitHubSettingsViewModel(
      tokenStore: tokenStore,
      configStore: configStore,
      tokenValidator: { _ in
        throw RepoRadarError.rateLimited(resetAt: Date().addingTimeInterval(1800))
      }
    )

    vm.tokenInput = "github_pat_valid_but_limited"
    await vm.saveToken()

    #expect(vm.validationError?.contains("rate limit exceeded") == true)
    #expect(vm.hasToken == false)
  }

  @Test("Table facts show dash when rate limit or repository access is unknown")
  @MainActor
  func factsShowDashWhenUnknown() {
    let (defaults, suite) = makeTestDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let tokenStore = InMemoryTokenStore(initialToken: "github_pat_valid")
    let configStore = ConfigStore(userDefaults: defaults)

    let vm = GitHubSettingsViewModel(
      tokenStore: tokenStore,
      configStore: configStore,
      snapshot: nil
    )

    #expect(vm.apiBudgetText == "—")
    #expect(vm.repositoryAccessText == "—")

    // Deliver snapshot with repository access and rate limit
    let snapshot = WidgetSnapshot(
      status: .ok,
      repositoryAccess: [
        RepositoryAccessItem(name: "Cwander83/repo-radar", defaultBranch: "main", hasAccess: true),
        RepositoryAccessItem(name: "Cwander83/private-repo", defaultBranch: nil, hasAccess: false)
      ],
      rateLimit: SnapshotRateLimit(remaining: 4500, limit: 5000, resetAt: Date(), cost: 1)
    )
    vm.updateFromSnapshot(snapshot)

    #expect(vm.apiBudgetText == "4,500 of 5,000 points left")
    #expect(vm.repositoryAccessText == "1 of 2 watched repos readable")
  }

  @Test("Snapshot delivery updates rate limit, last refresh date, and error state")
  @MainActor
  func liveSnapshotUpdatesMetadata() {
    let (defaults, suite) = makeTestDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let tokenStore = InMemoryTokenStore(initialToken: "github_pat_valid")
    let configStore = ConfigStore(userDefaults: defaults)
    let snapshotSubject = PassthroughSubject<WidgetSnapshot?, Never>()

    let vm = GitHubSettingsViewModel(
      tokenStore: tokenStore,
      configStore: configStore,
      snapshotPublisher: snapshotSubject.eraseToAnyPublisher()
    )

    let refreshDate = Date(timeIntervalSince1970: 1792881240)
    let updatedSnapshot = WidgetSnapshot(
      updatedAt: refreshDate,
      status: .ok,
      rateLimit: SnapshotRateLimit(remaining: 4800, limit: 5000, resetAt: Date(), cost: 1)
    )

    snapshotSubject.send(updatedSnapshot)

    #expect(vm.rateLimit?.remaining == 4800)
    #expect(vm.lastRefreshDate == refreshDate)
    #expect(vm.status == .valid)

    // Send error snapshot indicating token expired
    let errorSnapshot = WidgetSnapshot(
      status: .tokenError(detail: "Token expired on GitHub")
    )
    snapshotSubject.send(errorSnapshot)

    #expect(vm.status.isExpired == true)
    #expect(vm.status.label == "Expired")
  }

  @Test("Formatting helpers produce expected strings")
  func formattingHelpers() {
    // 1. Mask token
    #expect(GitHubSettingsViewModel.maskToken("github_pat_11ABCDEFGHIJKLM3fK2") == "github_pat_••••••••••••3fK2")
    #expect(GitHubSettingsViewModel.maskToken("ghp_1234567890abcdef") == "ghp_••••••••••••cdef")
    #expect(GitHubSettingsViewModel.maskToken("short") == "••••••••••••")

    // 2. Relative expiration
    let now = Date()
    let future90 = Calendar.current.date(byAdding: .day, value: 90, to: now)!
    let formattedFuture = GitHubSettingsViewModel.formatExpiration(date: future90, now: now)
    #expect(formattedFuture.contains("in 90 days"))

    let past4 = Calendar.current.date(byAdding: .day, value: -4, to: now)!
    let formattedPast = GitHubSettingsViewModel.formatExpiration(date: past4, now: now)
    #expect(formattedPast.contains("4 days ago"))

    // 3. API budget
    let budget = GitHubSettingsViewModel.formatAPIBudget(remaining: 4912, limit: 5000)
    #expect(budget == "4,912 of 5,000 points left")

    // 4. Expired banner
    let banner = GitHubSettingsViewModel.formatExpiredBanner(date: past4)
    #expect(banner.contains("Token expired on"))
    #expect(banner.contains("Repo Radar stopped refreshing"))
  }
}
