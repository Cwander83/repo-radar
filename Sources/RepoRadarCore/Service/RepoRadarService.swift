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
  /// Returns nil if the App Group container or suite is unavailable.
  public init?(
    userDefaults: UserDefaults? = nil,
    appGroupIdentifier: String = SnapshotStore.defaultAppGroupIdentifier,
    snapshotFilename: String = SnapshotStore.defaultFilename,
    keychainService: String = KeychainTokenStore.defaultService,
    keychainAccount: String = KeychainTokenStore.defaultAccount,
    client: GitHubGraphQLClient = GitHubGraphQLClient()
  ) {
    let config: ConfigStore
    if let userDefaults {
      config = ConfigStore(userDefaults: userDefaults)
    } else if let appGroupConfig = ConfigStore(suiteName: appGroupIdentifier) {
      config = appGroupConfig
    } else {
      return nil
    }

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
      let stored = try tokenStore.read()
      guard let stored, !stored.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw RepoRadarError.tokenMissing
      }
      token = stored
    } catch let error as RepoRadarError {
      let errorStatus = SnapshotStatus(error: error)
      let errorSnapshot = WidgetSnapshot.empty(status: errorStatus, updatedAt: now)
      try? snapshotStore.write(errorSnapshot)
      throw error
    } catch {
      let radarError = RepoRadarError.tokenUnauthorized(detail: error.localizedDescription)
      let errorStatus = SnapshotStatus.tokenError(detail: error.localizedDescription)
      let errorSnapshot = WidgetSnapshot.empty(status: errorStatus, updatedAt: now)
      try? snapshotStore.write(errorSnapshot)
      throw radarError
    }

    // Execute query and classify.
    do {
      let queryResponse = try await client.fetch(repos: config.watchedRepos, token: token)
      let report = Classifier.classify(
        response: queryResponse,
        watchedRepos: config.watchedRepos,
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

    if shouldPreserveData, let last = try? snapshotStore.read() {
      let lastHoldsData: Bool
      switch last.status {
      case .ok, .offline, .rateLimited:
        lastHoldsData = true
      default:
        lastHoldsData = false
      }

      if lastHoldsData {
        return WidgetSnapshot(
          schemaVersion: last.schemaVersion,
          updatedAt: last.updatedAt,
          status: status,
          failingCI: last.failingCI,
          runningCI: last.runningCI,
          pullRequests: last.pullRequests,
          staleBranches: last.staleBranches,
          repositoryAccess: last.repositoryAccess,
          rateLimit: last.rateLimit
        )
      }
    }

    return WidgetSnapshot.empty(status: status, updatedAt: now)
  }
}
