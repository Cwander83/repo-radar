import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Coordinates periodic background refresh, backoff, and observable state for the macOS host app.
@MainActor
public final class RefreshScheduler: ObservableObject {
  /// Reloader closure invoked after each snapshot write to reload WidgetKit timelines.
  public typealias WidgetReloader = @Sendable () -> Void

  /// Underlying repository service performing GraphQL queries and snapshot updates.
  public let service: RepoRadarService

  /// Clock abstraction driving timers and sleep intervals.
  public let clock: ClockProtocol

  /// Widget reloader closure.
  public let widgetReloader: WidgetReloader

  /// Waits for a usable network path before a refresh on wake.
  public let networkMonitor: NetworkPathMonitoring

  /// Notification manager responsible for posting local alerts when CI fails.
  public let notificationManager: any CINotificationManaging

  /// Identifiers of failing CI items from the previous evaluation.
  public private(set) var knownFailingCheckIDs: Set<String>

  /// Cached configuration loaded from ConfigStore to prevent UserDefaults reads during renders.
  @Published public private(set) var cachedConfig: RepoRadarConfig

  /// Cached indication of whether a GitHub token is present in the TokenStore to prevent Keychain reads during renders.
  @Published public private(set) var hasToken: Bool = false

  /// Latest snapshot loaded or produced by refresh.
  @Published public private(set) var latestSnapshot: WidgetSnapshot?

  /// Whether a refresh cycle is currently executing.
  @Published public private(set) var isRefreshing: Bool = false

  /// The most recent error encountered during refresh, if any.
  @Published public private(set) var lastError: Error?

  /// Number of consecutive offline failures, used for exponential backoff.
  public private(set) var consecutiveOfflineCount: Int = 0

  /// Whether the periodic background refresh loop is currently running.
  @Published public private(set) var isRunning: Bool = false

  /// Active background loop task.
  private var timerTask: Task<Void, Never>?

  /// Currently active in-flight refresh task to prevent overlapping runs.
  private var activeRefreshTask: Task<WidgetSnapshot, Error>?

  /// Refresh on wake that is waiting for the network.
  private var wakeTask: Task<Void, Never>?

  // MARK: - Observable Status & Counts

  /// Current sync status derived from the latest snapshot.
  public var status: SnapshotStatus {
    latestSnapshot?.status ?? .missing
  }

  /// Timestamp of the latest snapshot.
  public var lastUpdated: Date? {
    latestSnapshot?.updatedAt
  }

  /// Number of failing CI check runs or statuses.
  public var failingCICount: Int {
    latestSnapshot?.failingCI.count ?? 0
  }

  /// Number of running CI check runs or statuses.
  public var runningCICount: Int {
    latestSnapshot?.runningCI.count ?? 0
  }

  /// Number of pull requests in scope.
  public var pullRequestCount: Int {
    latestSnapshot?.pullRequests.count ?? 0
  }

  /// Number of stale branches.
  public var staleBranchCount: Int {
    latestSnapshot?.staleBranches.count ?? 0
  }

  /// Current menu bar state derived from snapshot status, failing CI count, and configuration.
  public var menuBarState: MenuBarState {
    MenuBarState.current(
      status: status,
      failingCICount: failingCICount,
      showMenuBarCount: cachedConfig.showMenuBarCount,
      hasToken: hasToken,
      hasWatchedRepos: !cachedConfig.watchedRepos.isEmpty
    )
  }

  // MARK: - Initialization

  /// Creates a scheduler with explicit dependencies.
  public init(
    service: RepoRadarService,
    clock: ClockProtocol = SystemClock(),
    networkMonitor: NetworkPathMonitoring = SystemNetworkPathMonitor(),
    notificationManager: any CINotificationManaging = SystemCINotificationManager(),
    widgetReloader: @escaping WidgetReloader = {
      #if canImport(WidgetKit)
      WidgetCenter.shared.reloadAllTimelines()
      #endif
    }
  ) {
    self.service = service
    self.clock = clock
    self.networkMonitor = networkMonitor
    self.notificationManager = notificationManager
    self.widgetReloader = widgetReloader
    self.cachedConfig = service.configStore.load()
    self.hasToken = service.tokenStore.hasToken()
    let initialSnapshot = try? service.snapshotStore.read()
    self.latestSnapshot = initialSnapshot
    self.knownFailingCheckIDs = Set(initialSnapshot?.failingCI.map(\.id) ?? [])
  }

  /// Convenience initializer targeting the standard App Group configuration and Keychain storage.
  /// Returns nil if the App Group container or suite is unavailable.
  public convenience init?(
    userDefaults: UserDefaults? = nil,
    appGroupIdentifier: String = SnapshotStore.defaultAppGroupIdentifier,
    snapshotFilename: String = SnapshotStore.defaultFilename,
    keychainService: String = KeychainTokenStore.defaultService,
    keychainAccount: String = KeychainTokenStore.defaultAccount,
    client: GitHubGraphQLClient = GitHubGraphQLClient(),
    clock: ClockProtocol = SystemClock(),
    networkMonitor: NetworkPathMonitoring = SystemNetworkPathMonitor(),
    notificationManager: any CINotificationManaging = SystemCINotificationManager(),
    widgetReloader: @escaping WidgetReloader = {
      #if canImport(WidgetKit)
      WidgetCenter.shared.reloadAllTimelines()
      #endif
    }
  ) {
    guard
      let service = RepoRadarService(
        userDefaults: userDefaults,
        appGroupIdentifier: appGroupIdentifier,
        snapshotFilename: snapshotFilename,
        keychainService: keychainService,
        keychainAccount: keychainAccount,
        client: client
      )
    else {
      return nil
    }
    self.init(
      service: service,
      clock: clock,
      networkMonitor: networkMonitor,
      notificationManager: notificationManager,
      widgetReloader: widgetReloader
    )
  }

  deinit {
    timerTask?.cancel()
    wakeTask?.cancel()
  }

  // MARK: - Lifecycle & Control

  /// Starts periodic background refreshing if not already running.
  public func start() {
    refreshCachedState()
    guard !isRunning else { return }
    isRunning = true
    timerTask = Task { [weak self] in
      await self?.runLoop(skipInitialRefresh: false)
    }
  }

  /// Stops periodic background refreshing.
  public func stop() {
    isRunning = false
    timerTask?.cancel()
    timerTask = nil
    wakeTask?.cancel()
    wakeTask = nil
  }

  /// Triggers a manual refresh now and reschedules the timer.
  @discardableResult
  public func refreshNow() async throws -> WidgetSnapshot {
    let snapshot = try await performRefresh()
    restartTimer()
    return snapshot
  }

  /// Executes a single refresh cycle, joining any in-flight refresh to prevent overlaps.
  @discardableResult
  public func performRefresh() async throws -> WidgetSnapshot {
    if let inFlight = activeRefreshTask {
      return try await inFlight.value
    }

    isRefreshing = true
    refreshCachedState()
    let task = Task<WidgetSnapshot, Error> {
      try await service.refresh(now: clock.now)
    }
    activeRefreshTask = task

    defer {
      activeRefreshTask = nil
      isRefreshing = false
      refreshCachedState()
    }

    do {
      let snapshot = try await task.value
      self.lastError = nil
      self.consecutiveOfflineCount = 0
      self.latestSnapshot = snapshot
      self.widgetReloader()

      if cachedConfig.ciNotifications {
        let newlyFailing = snapshot.failingCI.filter { !knownFailingCheckIDs.contains($0.id) }
        for item in newlyFailing {
          try? await notificationManager.postNotification(for: item)
        }
      }
      self.knownFailingCheckIDs = Set(snapshot.failingCI.map(\.id))

      return snapshot
    } catch {
      self.lastError = error
      if let radarError = error as? RepoRadarError, case .offline = radarError {
        self.consecutiveOfflineCount += 1
      } else {
        self.consecutiveOfflineCount = 0
      }
      if let updated = try? service.snapshotStore.read() {
        self.latestSnapshot = updated
        self.widgetReloader()
      }
      throw error
    }
  }

  /// Refreshes after the Mac wakes, once the network path is satisfied (CHR-91).
  ///
  /// Skipped while stopped, when "Refresh on wake" is off, or while a rate-limit reset is still
  /// ahead. A later wake or `stop()` cancels a refresh that is still waiting for the network.
  /// Returns the waiting task, or nil when skipped.
  @discardableResult
  public func handleWake() -> Task<Void, Never>? {
    wakeTask?.cancel()
    wakeTask = nil
    guard isRunning, cachedConfig.refreshOnWake else { return nil }

    if case .rateLimited(let resetAt) = lastError as? RepoRadarError,
      (resetAt ?? .distantFuture) > clock.now
    {
      // The timer sleeps on uptime, which pauses while the Mac sleeps. Re-arm it so the
      // rate-limit retry lands on the reset time instead of late by the sleep length.
      restartTimer()
      return nil
    }

    let task = Task { [weak self, networkMonitor] in
      do {
        try await networkMonitor.waitUntilSatisfied()
      } catch {
        return
      }
      guard !Task.isCancelled else { return }
      _ = try? await self?.refreshNow()
    }
    wakeTask = task
    return task
  }

  // MARK: - Timer & Backoff

  /// Computes the delay in seconds before the next scheduled refresh.
  public func computeDelay(after error: Error?) -> TimeInterval {
    let normalInterval = cachedConfig.pollInterval.timeInterval

    guard let error else {
      return normalInterval
    }

    if let radarError = error as? RepoRadarError {
      switch radarError {
      case .rateLimited(let resetAt):
        if let resetAt {
          let delta = resetAt.timeIntervalSince(clock.now)
          return max(delta, 60.0)
        }
        return 60.0

      case .offline:
        // Exponential backoff starting at 60s: 60s, 120s, 240s... capped at normalInterval.
        // Intentional (CHR-97): early offline retries may come sooner than a normal poll so the
        // widget recovers quickly once the network returns. Offline attempts never reach GitHub,
        // so they cost no rate limit. The cap keeps retries from ever being slower than a poll.
        let exponent = Double(min(max(consecutiveOfflineCount - 1, 0), 5))
        let backoff = 60.0 * pow(2.0, exponent)
        return min(normalInterval, backoff)

      default:
        return normalInterval
      }
    }

    return normalInterval
  }

  private func runLoop(skipInitialRefresh: Bool) async {
    if !skipInitialRefresh {
      _ = try? await performRefresh()
    }

    while !Task.isCancelled {
      let delay = computeDelay(after: lastError)
      do {
        try await clock.sleep(seconds: delay)
      } catch {
        break
      }

      guard !Task.isCancelled else { break }
      _ = try? await performRefresh()
    }
  }

  /// Restarts the background timer to apply updated polling intervals immediately.
  public func restartTimer() {
    guard isRunning else { return }
    timerTask?.cancel()
    timerTask = Task { [weak self] in
      await self?.runLoop(skipInitialRefresh: true)
    }
  }

  /// Refreshes cached token and configuration state to avoid Keychain/UserDefaults reads during renders.
  public func refreshCachedState() {
    self.cachedConfig = service.configStore.load()
    self.hasToken = service.tokenStore.hasToken()
  }

  /// Notifies the scheduler that configuration changed, restarting the timer and refreshing published state.
  public func configurationDidChange() {
    refreshCachedState()
    restartTimer()
    objectWillChange.send()
  }
}
