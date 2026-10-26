import Foundation
import Testing

@testable import RepoRadarCore

@Suite(.serialized)
@MainActor
struct RefreshSchedulerTests {
  private func makeMockClient(id: String) -> GitHubGraphQLClient {
    let endpoint = URL(string: "https://api.github.com/graphql")!
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    config.httpAdditionalHeaders = ["X-Mock-Handler-ID": id]
    let session = URLSession(configuration: config)
    return GitHubGraphQLClient(session: session, endpoint: endpoint)
  }

  private func loadRecordedPublicFixture() throws -> Data {
    try TestFixtures.loadData(named: "recorded-public")
  }

  private struct TestContext {
    let suiteName: String
    let defaults: UserDefaults
    let configStore: ConfigStore
    let tokenStore: InMemoryTokenStore
    let tempDir: URL
    let snapshotStore: SnapshotStore
    let mockID: String
    let client: GitHubGraphQLClient
    let service: RepoRadarService

    init(
      repos: [String] = ["Cwander83/repo-radar"],
      pollInterval: PollInterval = .fiveMinutes,
      ciNotifications: Bool = false
    ) throws {
      self.suiteName = "test-scheduler-\(UUID().uuidString)"
      self.defaults = UserDefaults(suiteName: suiteName)!
      self.configStore = ConfigStore(userDefaults: defaults)
      try configStore.save(
        RepoRadarConfig(
          watchedRepos: repos,
          pollInterval: pollInterval,
          staleDays: 30,
          ciNotifications: ciNotifications
        )
      )

      self.tokenStore = InMemoryTokenStore(initialToken: "test-valid-pat")
      self.tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("SchedulerTest-\(UUID().uuidString)")
      let snapshotFile = tempDir.appendingPathComponent("snapshot.json")
      self.snapshotStore = SnapshotStore(fileURL: snapshotFile)

      self.mockID = UUID().uuidString
      let endpoint = URL(string: "https://api.github.com/graphql")!
      let config = URLSessionConfiguration.ephemeral
      config.protocolClasses = [MockURLProtocol.self]
      config.httpAdditionalHeaders = ["X-Mock-Handler-ID": mockID]
      let session = URLSession(configuration: config)
      self.client = GitHubGraphQLClient(session: session, endpoint: endpoint)

      self.service = RepoRadarService(
        configStore: configStore,
        tokenStore: tokenStore,
        client: client,
        snapshotStore: snapshotStore
      )
    }

    func cleanup() {
      defaults.removePersistentDomain(forName: suiteName)
      try? FileManager.default.removeItem(at: tempDir)
      MockURLProtocol.unregisterHandler(id: mockID)
    }
  }

  @Test("Observable state publishes values and counts on successful refresh")
  func testObservableStateUpdates() async throws {
    let ctx = try TestContext()
    defer { ctx.cleanup() }

    let fixtureData = try loadRecordedPublicFixture()
    MockURLProtocol.registerHandler(id: ctx.mockID) { _ in
      let response = HTTPURLResponse(
        url: URL(string: "https://api.github.com/graphql")!,
        statusCode: 200,
        httpVersion: nil,
        headerFields: ["Content-Type": "application/json"]
      )!
      return (response, fixtureData)
    }

    let fakeClock = FakeClock()
    let scheduler = RefreshScheduler(service: ctx.service, clock: fakeClock)

    #expect(scheduler.isRefreshing == false)
    #expect(scheduler.status == .missing)
    #expect(scheduler.lastUpdated == nil)
    #expect(scheduler.failingCICount == 0)

    let snapshot = try await scheduler.performRefresh()

    #expect(scheduler.isRefreshing == false)
    #expect(scheduler.status == .ok)
    #expect(scheduler.lastUpdated == fakeClock.now)
    #expect(scheduler.failingCICount == snapshot.failingCI.count)
    #expect(scheduler.pullRequestCount == snapshot.pullRequests.count)
    #expect(scheduler.staleBranchCount == snapshot.staleBranches.count)
    #expect(scheduler.lastError == nil)
  }

  @Test("Widget reloads after successful refresh and on error")
  func testWidgetReloads() async throws {
    let ctx = try TestContext()
    defer { ctx.cleanup() }

    let fixtureData = try loadRecordedPublicFixture()
    var returnError = false

    MockURLProtocol.registerHandler(id: ctx.mockID) { _ in
      if returnError {
        let response = HTTPURLResponse(
          url: URL(string: "https://api.github.com/graphql")!,
          statusCode: 500,
          httpVersion: nil,
          headerFields: nil
        )!
        return (response, Data())
      }
      let response = HTTPURLResponse(
        url: URL(string: "https://api.github.com/graphql")!,
        statusCode: 200,
        httpVersion: nil,
        headerFields: ["Content-Type": "application/json"]
      )!
      return (response, fixtureData)
    }

    final class ReloadTracker: @unchecked Sendable {
      var count = 0
    }
    let tracker = ReloadTracker()
    let fakeClock = FakeClock()

    let scheduler = RefreshScheduler(
      service: ctx.service,
      clock: fakeClock,
      widgetReloader: { tracker.count += 1 }
    )

    // 1. Success triggers reload
    try await scheduler.performRefresh()
    #expect(tracker.count == 1)

    // 2. Error write triggers reload as well
    returnError = true
    do {
      try await scheduler.performRefresh()
      Issue.record("Expected server error")
    } catch {
      #expect(tracker.count == 2)
      #expect(scheduler.status != .ok)
    }
  }

  @Test("No overlapping runs when concurrent refreshes are triggered")
  func testNoOverlappingRuns() async throws {
    let ctx = try TestContext()
    defer { ctx.cleanup() }

    let fixtureData = try loadRecordedPublicFixture()
    final class CallCounter: @unchecked Sendable {
      var calls = 0
    }
    let counter = CallCounter()

    MockURLProtocol.registerHandler(id: ctx.mockID) { _ in
      counter.calls += 1
      Thread.sleep(forTimeInterval: 0.05)
      let response = HTTPURLResponse(
        url: URL(string: "https://api.github.com/graphql")!,
        statusCode: 200,
        httpVersion: nil,
        headerFields: ["Content-Type": "application/json"]
      )!
      return (response, fixtureData)
    }

    let fakeClock = FakeClock()
    let scheduler = RefreshScheduler(service: ctx.service, clock: fakeClock)

    async let first = scheduler.performRefresh()
    async let second = scheduler.performRefresh()

    let (snap1, snap2) = try await (first, second)
    #expect(snap1.updatedAt == snap2.updatedAt)
    #expect(counter.calls == 1)
  }

  @Test("Timer loop triggers periodic refresh at configured interval")
  func testPeriodicTimerRefresh() async throws {
    let ctx = try TestContext(pollInterval: .fiveMinutes)
    defer { ctx.cleanup() }

    let fixtureData = try loadRecordedPublicFixture()
    final class QueryCounter: @unchecked Sendable {
      var count = 0
    }
    let counter = QueryCounter()

    MockURLProtocol.registerHandler(id: ctx.mockID) { _ in
      counter.count += 1
      let response = HTTPURLResponse(
        url: URL(string: "https://api.github.com/graphql")!,
        statusCode: 200,
        httpVersion: nil,
        headerFields: ["Content-Type": "application/json"]
      )!
      return (response, fixtureData)
    }

    let fakeClock = FakeClock()
    let scheduler = RefreshScheduler(service: ctx.service, clock: fakeClock)

    scheduler.start()
    defer { scheduler.stop() }

    // Wait for initial refresh and subsequent sleep scheduling
    try await fakeClock.waitForSleepCalls(count: 1)
    #expect(counter.count == 1)
    #expect(fakeClock.lastSleepRequestedDuration == 300)

    // Advance clock by 300 seconds to trigger second refresh
    fakeClock.advance(by: 300)
    try await fakeClock.waitForSleepCalls(count: 2)
    #expect(counter.count == 2)
  }

  @Test("Manual refresh executes immediately and restarts timer interval")
  func testManualRefreshRestartsTimer() async throws {
    let ctx = try TestContext(pollInterval: .tenMinutes)
    defer { ctx.cleanup() }

    let fixtureData = try loadRecordedPublicFixture()
    final class QueryCounter: @unchecked Sendable {
      var count = 0
    }
    let counter = QueryCounter()

    MockURLProtocol.registerHandler(id: ctx.mockID) { _ in
      counter.count += 1
      let response = HTTPURLResponse(
        url: URL(string: "https://api.github.com/graphql")!,
        statusCode: 200,
        httpVersion: nil,
        headerFields: ["Content-Type": "application/json"]
      )!
      return (response, fixtureData)
    }

    let fakeClock = FakeClock()
    let scheduler = RefreshScheduler(service: ctx.service, clock: fakeClock)

    scheduler.start()
    defer { scheduler.stop() }

    try await fakeClock.waitForSleepCalls(count: 1)
    #expect(counter.count == 1)

    // Manual refresh now
    let snap = try await scheduler.refreshNow()
    #expect(snap.status == .ok)
    #expect(counter.count == 2)

    // Timer was rescheduled to sleep 600s
    try await fakeClock.waitForSleepCalls(count: 2)
    #expect(fakeClock.lastSleepRequestedDuration == 600)
  }

  @Test("Rate limit backoff calculates delay until resetAt")
  func testRateLimitBackoff() throws {
    let ctx = try TestContext(pollInterval: .fiveMinutes)
    defer { ctx.cleanup() }

    let fakeClock = FakeClock(now: Date(timeIntervalSince1970: 10000))
    let scheduler = RefreshScheduler(service: ctx.service, clock: fakeClock)

    // Normal interval when no error
    #expect(scheduler.computeDelay(after: nil) == 300)

    // Rate limited with future resetAt
    let resetAt = Date(timeIntervalSince1970: 10750)
    let rateLimitError = RepoRadarError.rateLimited(resetAt: resetAt)
    let delay = scheduler.computeDelay(after: rateLimitError)
    #expect(delay == 750)

    // Rate limited with past resetAt uses 60s floor
    let pastReset = Date(timeIntervalSince1970: 9000)
    let pastError = RepoRadarError.rateLimited(resetAt: pastReset)
    #expect(scheduler.computeDelay(after: pastError) == 60)
  }

  @Test("Offline backoff increases exponentially on consecutive failures")
  func testOfflineBackoff() async throws {
    let ctx = try TestContext(pollInterval: .fifteenMinutes) // 900s
    defer { ctx.cleanup() }

    MockURLProtocol.registerHandler(id: ctx.mockID) { _ in
      throw URLError(.notConnectedToInternet)
    }

    let fakeClock = FakeClock()
    let scheduler = RefreshScheduler(service: ctx.service, clock: fakeClock)

    // First offline failure: 60s
    do { _ = try await scheduler.performRefresh() } catch {}
    #expect(scheduler.consecutiveOfflineCount == 1)
    #expect(scheduler.computeDelay(after: scheduler.lastError) == 60)

    // Second consecutive offline failure: 120s
    do { _ = try await scheduler.performRefresh() } catch {}
    #expect(scheduler.consecutiveOfflineCount == 2)
    #expect(scheduler.computeDelay(after: scheduler.lastError) == 120)

    // Third consecutive offline failure: 240s
    do { _ = try await scheduler.performRefresh() } catch {}
    #expect(scheduler.consecutiveOfflineCount == 3)
    #expect(scheduler.computeDelay(after: scheduler.lastError) == 240)
  }

  @Test("Offline retries start faster than a poll and cap at the poll interval (CHR-97)")
  func testOfflineBackoffCapsAtPollInterval() async throws {
    let ctx = try TestContext(pollInterval: .fiveMinutes) // 300s
    defer { ctx.cleanup() }

    MockURLProtocol.registerHandler(id: ctx.mockID) { _ in
      throw URLError(.notConnectedToInternet)
    }

    let fakeClock = FakeClock()
    let scheduler = RefreshScheduler(service: ctx.service, clock: fakeClock)

    // Intended fast recovery: early retries come sooner than the 300s poll,
    // then every retry is capped at the poll interval, never slower.
    let expected: [TimeInterval] = [60, 120, 240, 300, 300, 300, 300, 300]
    var delays: [TimeInterval] = []
    for _ in expected {
      do { _ = try await scheduler.performRefresh() } catch {}
      delays.append(scheduler.computeDelay(after: scheduler.lastError))
    }
    #expect(delays == expected)
    #expect(scheduler.consecutiveOfflineCount == expected.count)
  }

  @Test("FakeClock removes and cancels a sleeper when its task is cancelled")
  func testFakeClockCancelledSleeperIsRemoved() async throws {
    let fakeClock = FakeClock()
    let sleeper = Task { try await fakeClock.sleep(seconds: 300) }

    try await fakeClock.waitForSleepCalls(count: 1)
    #expect(fakeClock.pendingSleepCount() == 1)

    sleeper.cancel()
    let result = await sleeper.result
    switch result {
    case .success:
      Issue.record("Expected CancellationError")
    case .failure(let error):
      #expect(error is CancellationError)
    }
    #expect(fakeClock.pendingSleepCount() == 0)
  }

  @Test("FakeClock rejects a sleep that starts on an already-cancelled task")
  func testFakeClockSleepOnCancelledTask() async throws {
    let fakeClock = FakeClock()
    let sleeper = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      try await fakeClock.sleep(seconds: 300)
    }

    let result = await sleeper.result
    switch result {
    case .success:
      Issue.record("Expected CancellationError")
    case .failure(let error):
      #expect(error is CancellationError)
    }
    #expect(fakeClock.pendingSleepCount() == 0)
    #expect(fakeClock.sleepCallCount == 0)
  }

  @Test("stop() and restartTimer() leave no orphaned sleepers")
  func testStopAndRestartLeaveNoOrphanedSleepers() async throws {
    let ctx = try TestContext(pollInterval: .fiveMinutes)
    defer { ctx.cleanup() }

    let fixtureData = try loadRecordedPublicFixture()
    MockURLProtocol.registerHandler(id: ctx.mockID) { _ in
      let response = HTTPURLResponse(
        url: URL(string: "https://api.github.com/graphql")!,
        statusCode: 200,
        httpVersion: nil,
        headerFields: ["Content-Type": "application/json"]
      )!
      return (response, fixtureData)
    }

    let fakeClock = FakeClock()
    let scheduler = RefreshScheduler(service: ctx.service, clock: fakeClock)

    scheduler.start()
    try await fakeClock.waitForSleepCalls(count: 1)
    #expect(fakeClock.pendingSleepCount() == 1)

    // restartTimer() cancels the old loop; only the new loop's sleep stays pending.
    scheduler.restartTimer()
    try await fakeClock.waitForSleepCalls(count: 2)
    try await fakeClock.waitForPendingSleepCount(1)

    // stop() cancels the loop; its sleeper is removed, not leaked.
    scheduler.stop()
    try await fakeClock.waitForPendingSleepCount(0)
  }

  @Test("refreshNow does not restart periodic timer after stop")
  func testRefreshNowDoesNotRestartAfterStop() async throws {
    let ctx = try TestContext(pollInterval: .fiveMinutes)
    defer { ctx.cleanup() }

    let fixtureData = try loadRecordedPublicFixture()
    final class QueryCounter: @unchecked Sendable {
      var count = 0
    }
    let counter = QueryCounter()

    MockURLProtocol.registerHandler(id: ctx.mockID) { _ in
      counter.count += 1
      let response = HTTPURLResponse(
        url: URL(string: "https://api.github.com/graphql")!,
        statusCode: 200,
        httpVersion: nil,
        headerFields: ["Content-Type": "application/json"]
      )!
      return (response, fixtureData)
    }

    let fakeClock = FakeClock()
    let scheduler = RefreshScheduler(service: ctx.service, clock: fakeClock)

    scheduler.start()
    #expect(scheduler.isRunning == true)
    try await fakeClock.waitForSleepCalls(count: 1)
    #expect(counter.count == 1)

    scheduler.stop()
    #expect(scheduler.isRunning == false)

    let sleepCallsBefore = fakeClock.sleepCallCount

    // Trigger manual refresh while stopped
    let snap = try await scheduler.refreshNow()
    #expect(snap.status == .ok)
    #expect(counter.count == 2)
    #expect(scheduler.isRunning == false)

    // Ensure no further sleeps are scheduled after stop
    #expect(fakeClock.sleepCallCount == sleepCallsBefore)
  }

  // MARK: - Refresh on wake (CHR-91)

  private final class WakeQueryCounter: @unchecked Sendable {
    var count = 0
  }

  /// Serves the recorded fixture for every query and counts the queries.
  private func registerCountingFixture(_ ctx: TestContext) throws -> WakeQueryCounter {
    let fixtureData = try loadRecordedPublicFixture()
    let counter = WakeQueryCounter()
    MockURLProtocol.registerHandler(id: ctx.mockID) { _ in
      counter.count += 1
      let response = HTTPURLResponse(
        url: URL(string: "https://api.github.com/graphql")!,
        statusCode: 200,
        httpVersion: nil,
        headerFields: ["Content-Type": "application/json"]
      )!
      return (response, fixtureData)
    }
    return counter
  }

  @Test("Wake waits for a satisfied network path, then refreshes (CHR-91)")
  func testWakeRefreshesOnceNetworkIsSatisfied() async throws {
    let ctx = try TestContext(pollInterval: .fiveMinutes)
    defer { ctx.cleanup() }
    let counter = try registerCountingFixture(ctx)

    let fakeClock = FakeClock()
    let network = FakeNetworkPathMonitor(isSatisfied: false)
    let scheduler = RefreshScheduler(
      service: ctx.service, clock: fakeClock, networkMonitor: network)

    scheduler.start()
    defer { scheduler.stop() }
    try await fakeClock.waitForSleepCalls(count: 1)
    #expect(counter.count == 1)

    // Wi-Fi is still reconnecting: no query goes out yet.
    let wake = try #require(scheduler.handleWake())
    try await network.waitForPendingWaitCount(1)
    #expect(counter.count == 1)

    network.satisfy()
    await wake.value
    #expect(counter.count == 2)

    // The wake refresh restarts the poll timer with a full interval.
    try await fakeClock.waitForSleepCalls(count: 2)
    try await fakeClock.waitForPendingSleepCount(1)
    #expect(fakeClock.lastSleepRequestedDuration == 300)
  }

  @Test("Wake does nothing while Refresh on wake is off (CHR-91)")
  func testWakeRespectsToggle() async throws {
    let ctx = try TestContext(pollInterval: .fiveMinutes)
    defer { ctx.cleanup() }
    var config = ctx.configStore.load()
    config.refreshOnWake = false
    try ctx.configStore.save(config)
    let counter = try registerCountingFixture(ctx)

    let fakeClock = FakeClock()
    let scheduler = RefreshScheduler(
      service: ctx.service, clock: fakeClock, networkMonitor: FakeNetworkPathMonitor())

    scheduler.start()
    defer { scheduler.stop() }
    try await fakeClock.waitForSleepCalls(count: 1)

    #expect(scheduler.handleWake() == nil)
    #expect(counter.count == 1)

    // Turning the toggle back on in Settings applies without restarting the app.
    config.refreshOnWake = true
    try ctx.configStore.save(config)
    scheduler.configurationDidChange()
    let wake = try #require(scheduler.handleWake())
    await wake.value
    #expect(counter.count == 2)
  }

  @Test("Wake waits out a pending rate-limit reset, then refreshes once it passes (CHR-91)")
  func testWakeRespectsRateLimitReset() async throws {
    let ctx = try TestContext(pollInterval: .fiveMinutes)
    defer { ctx.cleanup() }

    let fakeClock = FakeClock()
    let resetEpoch = Int(fakeClock.now.timeIntervalSince1970) + 1800
    let counter = WakeQueryCounter()
    MockURLProtocol.registerHandler(id: ctx.mockID) { request in
      counter.count += 1
      let response = HTTPURLResponse(
        url: request.url!,
        statusCode: 403,
        httpVersion: nil,
        headerFields: [
          "x-ratelimit-remaining": "0",
          "x-ratelimit-reset": "\(resetEpoch)",
        ]
      )!
      return (response, Data("rate limit exceeded".utf8))
    }

    let scheduler = RefreshScheduler(
      service: ctx.service, clock: fakeClock, networkMonitor: FakeNetworkPathMonitor())

    scheduler.start()
    defer { scheduler.stop() }
    try await fakeClock.waitForSleepCalls(count: 1)
    #expect(counter.count == 1)
    #expect(fakeClock.lastSleepRequestedDuration == 1800)

    // Wake 10 minutes later, before the reset: no query, and the timer is re-armed for the
    // 20 minutes left instead of running late by the sleep length.
    fakeClock.advance(by: 600)
    #expect(scheduler.handleWake() == nil)
    #expect(counter.count == 1)
    try await fakeClock.waitForSleepCalls(count: 2)
    try await fakeClock.waitForPendingSleepCount(1)
    #expect(fakeClock.lastSleepRequestedDuration == 1200)

    // The timer retries at the reset. Once the reset has passed, a wake refreshes right away.
    fakeClock.advance(by: 1201)
    try await fakeClock.waitForSleepCalls(count: 3)
    #expect(counter.count == 2)

    let wake = try #require(scheduler.handleWake())
    await wake.value
    #expect(counter.count == 3)
  }

  @Test("A new wake or stop() cancels a wake refresh still waiting for the network (CHR-91)")
  func testWakeWaitIsReplacedAndCancelled() async throws {
    let ctx = try TestContext(pollInterval: .fiveMinutes)
    defer { ctx.cleanup() }
    let counter = try registerCountingFixture(ctx)

    let fakeClock = FakeClock()
    let network = FakeNetworkPathMonitor(isSatisfied: false)
    let scheduler = RefreshScheduler(
      service: ctx.service, clock: fakeClock, networkMonitor: network)

    scheduler.start()
    defer { scheduler.stop() }
    try await fakeClock.waitForSleepCalls(count: 1)

    // A second wake replaces the first wait instead of stacking monitors.
    let first = try #require(scheduler.handleWake())
    try await network.waitForPendingWaitCount(1)
    let second = try #require(scheduler.handleWake())
    await first.value
    try await network.waitForPendingWaitCount(1)

    // stop() cancels the remaining wait, and a stopped scheduler ignores wakes.
    scheduler.stop()
    await second.value
    #expect(network.pendingWaitCount == 0)
    #expect(scheduler.handleWake() == nil)

    network.satisfy()
    #expect(counter.count == 1)
  }

  private func loadSyntheticFixture() throws -> Data {
    try TestFixtures.loadData(named: "synthetic-edge-cases")
  }

  @Test("Pass-to-fail transition notifies once, fail-to-fail stays quiet, and recovery resets state (CHR-68)")
  func testNewlyFailingCINotifications() async throws {
    let ctx = try TestContext(
      repos: ["octo-user/alpha", "octo-user/delta"],
      pollInterval: .fiveMinutes,
      ciNotifications: true
    )
    defer { ctx.cleanup() }

    let passingData = try loadRecordedPublicFixture()
    let failingData = try loadSyntheticFixture()

    final class FixtureHolder: @unchecked Sendable {
      var currentData: Data
      init(data: Data) { self.currentData = data }
    }
    let holder = FixtureHolder(data: passingData)

    MockURLProtocol.registerHandler(id: ctx.mockID) { _ in
      let response = HTTPURLResponse(
        url: URL(string: "https://api.github.com/graphql")!,
        statusCode: 200,
        httpVersion: nil,
        headerFields: ["Content-Type": "application/json"]
      )!
      return (response, holder.currentData)
    }

    let fakeClock = FakeClock()
    let mockNotifications = MockCINotificationManager()
    let scheduler = RefreshScheduler(
      service: ctx.service,
      clock: fakeClock,
      notificationManager: mockNotifications
    )

    // 1. Initial refresh with passing checks: no notifications posted
    try await scheduler.refreshNow()
    #expect(scheduler.failingCICount == 0)
    #expect(mockNotifications.postedItems.isEmpty)

    // 2. Transition from passing to failing: notifies once per newly failing check
    holder.currentData = failingData
    try await scheduler.refreshNow()
    #expect(scheduler.failingCICount == 4)
    #expect(mockNotifications.postedItems.count == 4)

    // Grouping: each notification names repo, ref, and check, with target URL
    for item in mockNotifications.postedItems {
      #expect(!item.repo.isEmpty)
      #expect(!item.ref.isEmpty)
      #expect(!item.check.isEmpty)
      #expect(WidgetGitHubURL.url(for: item).scheme == "https")
    }

    // 3. Consecutive refresh with same failing checks (fail -> fail): stays quiet
    mockNotifications.reset()
    try await scheduler.refreshNow()
    #expect(scheduler.failingCICount == 4)
    #expect(mockNotifications.postedItems.isEmpty)

    // 4. Checks recover / pass: stays quiet
    holder.currentData = passingData
    try await scheduler.refreshNow()
    #expect(scheduler.failingCICount == 0)
    #expect(mockNotifications.postedItems.isEmpty)

    // 5. Checks fail again (pass -> fail): notifies once more
    holder.currentData = failingData
    try await scheduler.refreshNow()
    #expect(scheduler.failingCICount == 4)
    #expect(mockNotifications.postedItems.count == 4)
  }

  @Test("Opt-in ciNotifications off by default suppresses notifications on failures (CHR-68)")
  func testCINotificationsDisabledStaysQuiet() async throws {
    let ctx = try TestContext(
      repos: ["octo-user/alpha", "octo-user/delta"],
      pollInterval: .fiveMinutes,
      ciNotifications: false
    )
    defer { ctx.cleanup() }

    let failingData = try loadSyntheticFixture()
    MockURLProtocol.registerHandler(id: ctx.mockID) { _ in
      let response = HTTPURLResponse(
        url: URL(string: "https://api.github.com/graphql")!,
        statusCode: 200,
        httpVersion: nil,
        headerFields: ["Content-Type": "application/json"]
      )!
      return (response, failingData)
    }

    let fakeClock = FakeClock()
    let mockNotifications = MockCINotificationManager()
    let scheduler = RefreshScheduler(
      service: ctx.service,
      clock: fakeClock,
      notificationManager: mockNotifications
    )

    try await scheduler.refreshNow()
    #expect(scheduler.failingCICount == 4)
    #expect(mockNotifications.postedItems.isEmpty)
  }

  @Test("Pre-existing snapshot on launch populates known failures so first refresh stays quiet (CHR-68)")
  func testPreExistingSnapshotSuppressesNotificationOnRelaunch() async throws {
    let ctx = try TestContext(
      repos: ["octo-user/alpha", "octo-user/delta"],
      pollInterval: .fiveMinutes,
      ciNotifications: true
    )
    defer { ctx.cleanup() }

    let failingData = try loadSyntheticFixture()
    MockURLProtocol.registerHandler(id: ctx.mockID) { _ in
      let response = HTTPURLResponse(
        url: URL(string: "https://api.github.com/graphql")!,
        statusCode: 200,
        httpVersion: nil,
        headerFields: ["Content-Type": "application/json"]
      )!
      return (response, failingData)
    }

    // First instance refreshes and writes failing snapshot to disk
    let mockNotifications1 = MockCINotificationManager()
    let scheduler1 = RefreshScheduler(
      service: ctx.service,
      notificationManager: mockNotifications1
    )
    try await scheduler1.refreshNow()
    #expect(mockNotifications1.postedItems.count == 4)

    // Second instance launches (like app reboot/relaunch) with existing snapshot already on disk
    let mockNotifications2 = MockCINotificationManager()
    let scheduler2 = RefreshScheduler(
      service: ctx.service,
      notificationManager: mockNotifications2
    )
    #expect(scheduler2.knownFailingCheckIDs.count == 4)

    // First refresh in new session with same failing checks stays quiet
    try await scheduler2.refreshNow()
    #expect(scheduler2.failingCICount == 4)
    #expect(mockNotifications2.postedItems.isEmpty)
  }
}
