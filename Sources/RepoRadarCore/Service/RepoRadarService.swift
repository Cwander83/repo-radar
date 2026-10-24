import Foundation

/// Coordinates end-to-end refresh: config → token → GitHub query → decoding → classification → snapshot.
public struct RepoRadarService: Sendable {
  /// Configuration store.
  public let configStore: ConfigStore

  /// Token store for authentication.
  public let tokenStore: any TokenStore

  /// GitHub GraphQL API client.
  public let client: GitHubGraphQLClient

  /// Snapshot storage manager.
  public let snapshotStore: SnapshotStore

  /// Creates a service with explicit dependencies.
  public init(
    configStore: ConfigStore,
    tokenStore: any TokenStore,
    client: GitHubGraphQLClient = GitHubGraphQLClient(),
    snapshotStore: SnapshotStore
  ) {
    self.configStore = configStore
    self.tokenStore = tokenStore
    self.client = client
    self.snapshotStore = snapshotStore
  }

  /// Convenience initializer targeting the standard App Group configuration and Keychain storage.
  public init?(
    userDefaults: UserDefaults? = nil,
    appGroupIdentifier: String = SnapshotStore.defaultAppGroupIdentifier,
    snapshotFilename: String = SnapshotStore.defaultFilename,
    keychainService: String = KeychainTokenStore.defaultService,
    keychainAccount: String = KeychainTokenStore.defaultAccount,
    client: GitHubGraphQLClient = GitHubGraphQLClient()
  ) {
    let defaults = userDefaults ?? UserDefaults(suiteName: appGroupIdentifier) ?? .standard
    let config = ConfigStore(userDefaults: defaults)
    let token = KeychainTokenStore(service: keychainService, account: keychainAccount)
    guard
      let snapshot = SnapshotStore(
        appGroupIdentifier: appGroupIdentifier, filename: snapshotFilename)
    else {
      return nil
    }

    self.init(
      configStore: config,
      tokenStore: token,
      client: client,
      snapshotStore: snapshot
    )
  }

  /// Executes an end-to-end refresh cycle.
  ///
  /// Steps:
  /// 1. Loads configuration from `ConfigStore`.
  /// 2. If no repos are watched, writes an empty OK snapshot.
  /// 3. Reads PAT from `TokenStore`, throwing `RepoRadarError.tokenMissing` if not present.
  /// 4. Executes the GraphQL query via `GitHubGraphQLClient`.
  /// 5. Classifies the response with `Classifier`.
  /// 6. Writes the resulting `WidgetSnapshot` to `SnapshotStore`.
  ///
  /// On error, writes an appropriate error snapshot (preserving cached data on offline or rate-limiting)
  /// and rethrows the underlying error.
  @discardableResult
  public func refresh(now: Date = Date()) async throws -> WidgetSnapshot {
    let config = configStore.load()

    // When no repositories are configured, write an empty ok snapshot and return immediately.
    guard !config.watchedRepos.isEmpty else {
      let emptySnapshot = WidgetSnapshot(
        updatedAt: now,
        status: .ok,
        report: ClassifiedReport(),
        rateLimit: nil
      )
      try snapshotStore.write(emptySnapshot)
      return emptySnapshot
    }

    // Read authentication token.
    let token: String
    do {
      guard let storedToken = try tokenStore.read(),
        !storedToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      else {
        throw RepoRadarError.tokenMissing
      }
      token = storedToken
    } catch {
      let radarError = (error as? RepoRadarError) ?? .tokenMissing
      let errorStatus = SnapshotStatus(error: radarError)
      let errorSnapshot = WidgetSnapshot.empty(status: errorStatus, updatedAt: now)
      try? snapshotStore.write(errorSnapshot)
      throw radarError
    }

    // Execute query and classify.
    do {
      let queryResponse = try await client.fetch(repos: config.watchedRepos, token: token)
      let report = Classifier.classify(
        response: queryResponse,
        viewerLogin: queryResponse.data?.viewer.login,
        staleDays: config.staleDays,
        now: now
      )
      let rateLimit = queryResponse.data?.rateLimit.map { SnapshotRateLimit(rateLimit: $0) }
      let snapshot = WidgetSnapshot(
        updatedAt: now,
        status: .ok,
        report: report,
        rateLimit: rateLimit
      )
      try snapshotStore.write(snapshot)
      return snapshot
    } catch is CancellationError {
      // Do not overwrite snapshot on task cancellation
      throw CancellationError()
    } catch let error as RepoRadarError {
      let status = SnapshotStatus(error: error)
      let snapshot = makeFallbackSnapshot(status: status, now: now)
      try? snapshotStore.write(snapshot)
      throw error
    } catch {
      let status = SnapshotStatus.serverError(detail: error.localizedDescription)
      let snapshot = makeFallbackSnapshot(status: status, now: now)
      try? snapshotStore.write(snapshot)
      throw error
    }
  }

  /// Builds a fallback snapshot for error states, preserving cached data when offline or rate-limited.
  private func makeFallbackSnapshot(status: SnapshotStatus, now: Date) -> WidgetSnapshot {
    let shouldPreserveData: Bool
    switch status {
    case .offline, .rateLimited:
      shouldPreserveData = true
    default:
      shouldPreserveData = false
    }

    if shouldPreserveData, let last = try? snapshotStore.read(), last.status.isOK {
      return WidgetSnapshot(
        schemaVersion: last.schemaVersion,
        updatedAt: last.updatedAt,
        status: status,
        failingCI: last.failingCI,
        runningCI: last.runningCI,
        pullRequests: last.pullRequests,
        staleBranches: last.staleBranches,
        rateLimit: last.rateLimit
      )
    }

    return WidgetSnapshot.empty(status: status, updatedAt: now)
  }
}
